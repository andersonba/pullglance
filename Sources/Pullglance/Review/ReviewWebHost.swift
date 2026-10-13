import AppKit
import WebKit

/// The review window's web view: navigation, popups, downloads, logging, and the page script through
/// `ReviewBridge` (injected into its own content world, storage in UserDefaults).
@MainActor
final class ReviewWebHost: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    /// Window-side hooks (the host stays UI-agnostic).
    var onNavigationError: ((URL?, Error) -> Void)?
    var onNavigationStart: (() -> Void)?
    var onCrashLoop: (() -> Void)?
    var onDownloadFinished: ((URL) -> Void)?
    /// A main-frame load that finished: the only moment a visit is worth remembering.
    var onNavigationFinished: ((URL?, String?) -> Void)?
    /// The main-frame URL last allowed by policy; a late failure for anything else is ignored.
    private(set) var pendingMainFrameURL: URL?
    private var lastCrash: Date?
    private var downloads: [WKDownload: URL] = [:]

    let webView: WKWebView
    /// The page script's native half: the only script message handler on this web view.
    let bridge: ReviewBridge
    var popups: [NSWindow] = []
    var onLog: ((String) -> Void)?

    init(userAgent: String? = nil) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()            // persistent cookies / local storage
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")   // right click > Inspect Element
        // Some sign-in providers refuse the bare WebKit UA; every open-source browser adds Safari's token.
        config.applicationNameForUserAgent = "Version/\(Self.installedSafariVersion ?? "18.0") Safari/605.1.15"
        config.preferences.javaScriptCanOpenWindowsAutomatically = false   // popups only on a user gesture
        config.upgradeKnownHostsToHTTPS = true
        let ucc = config.userContentController
        let view = ReviewWebView(frame: NSRect(x: 0, y: 0, width: 1400, height: 1000), configuration: config)
        webView = view
        bridge = ReviewBridge(storage: ReviewStorage(defaults: .standard), log: { line in AppLog.shared.debug("review: \(line)") })
        bridge.attach(to: view)
        super.init()
        view.openInBrowser = { [weak self] url in self?.openInBrowser(url) }

        bridge.install(into: ucc)
        if let userAgent { webView.customUserAgent = userAgent }
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .windowBackgroundColor   // no white flash in dark mode
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    static var installedSafariVersion: String? {
        Bundle(path: "/Applications/Safari.app")?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Hosts that stay inside the window. Everything else a *click* leads to goes to the default browser;
    /// redirects and form posts (login, SSO) are not clicks and stay, so sign-in flows keep working.
    static func staysInside(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com") || host.hasSuffix(".githubassets.com")
    }

    /// Identity providers a sign-in flow may land on; clicks there must stay in a sign-in popup or the user
    /// is thrown out of the SSO flow halfway (hivra's list plus the usual enterprise ones). Popups only: the
    /// main window never keeps one on a click, so a page cannot dress a phishing form up as GitHub's window.
    static func isIdentityProvider(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        let exact: Set<String> = ["accounts.google.com", "appleid.apple.com", "login.microsoftonline.com", "login.live.com", "login.microsoft.com"]
        if exact.contains(host) { return true }
        for suffix in [".okta.com", ".oktapreview.com", ".auth0.com", ".onelogin.com", ".pingidentity.com", ".duosecurity.com", ".accounts.dev"] where host.hasSuffix(suffix) { return true }
        return false
    }

    static let webContentSchemes: Set<String> = ["http", "https", "about", "blob", "data", "javascript"]
    static let externalSchemes: Set<String> = ["mailto", "tel", "facetime", "sms"]

    /// mailto:/tel: links go to the app registered for them, only from a click in the main frame.
    func openExternally(_ url: URL) {
        log("open externally \(Self.redacted(url))")
        NSWorkspace.shared.open(url)
    }

    /// Only web URLs leave the window: a page must not be able to hand `file:` or custom schemes to the system.
    func openInBrowser(_ url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        log("open in browser \(Self.redacted(url))")
        NSWorkspace.shared.open(url)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let url = navigationAction.request.url
        let scheme = url?.scheme?.lowercased() ?? ""
        let isClick = navigationAction.navigationType == .linkActivated
        // <a download>, or anything WebKit itself flags as a download: handled natively (the session travels).
        if navigationAction.shouldPerformDownload { return .download }
        // Scheme table (hivra): web content stays; mailto/tel go to their app on a main-frame click; the rest is refused.
        if Self.externalSchemes.contains(scheme) {
            if isMainFrame, isClick, let url { openExternally(url) } else { log("refused \(scheme): not a main-frame click") }
            return .cancel
        }
        if !Self.webContentSchemes.contains(scheme) {
            log("refused scheme \(scheme.isEmpty ? "(none)" : scheme)")
            return .cancel
        }
        guard isMainFrame else { return .allow }
        if isClick {
            // ⌘-click (or middle click) on a link: a new tab in a browser; here, the browser itself.
            if navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 4 {
                openInBrowser(url)
                return .cancel
            }
            if Self.clickLeavesWindow(url, from: webView.url, inPopup: webView !== self.webView) {
                openInBrowser(url)
                return .cancel
            }
        }
        if webView === self.webView { pendingMainFrameURL = url }
        return .allow
    }

    /// A main-frame click leaves for the browser when it goes to a GitHub-foreign host, unless the page
    /// already is that host (an SSO provider reached by redirect) or, inside a sign-in popup only, the
    /// host is a known identity provider.
    static func clickLeavesWindow(_ url: URL?, from current: URL?, inPopup: Bool) -> Bool {
        if staysInside(url) { return false }
        let currentHost = current?.host?.lowercased()
        if currentHost != nil, currentHost == url?.host?.lowercased() { return false }
        if inPopup, isIdentityProvider(url) { return false }
        return true
    }

    // MARK: logging

    /// Log form of a URL: scheme, host and path only. Queries and fragments can carry sign-in tokens;
    /// titles never reach the log at all (the file log rule: repository and number, nothing from the PR).
    nonisolated static func redacted(_ url: URL?) -> String {
        guard let url else { return "-" }
        return (url.scheme.map { $0 + "://" } ?? "") + (url.host ?? "") + url.path
    }

    func log(_ line: String) {
        onLog?(line)
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        log("nav.start \(Self.redacted(webView.url))")
        if webView === self.webView { onNavigationStart?() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if let http = navigationResponse.response as? HTTPURLResponse, navigationResponse.isForMainFrame {
            log("nav.response \(http.statusCode) \(Self.redacted(http.url))")
        }
        // A download (patch, diff, archive, anything served as an attachment) is handled natively: the
        // cookies travel with it, so private artifacts work, which they would not in another browser.
        let http = navigationResponse.response as? HTTPURLResponse
        let status = http?.statusCode ?? 200
        let disposition = http?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().split(separator: ";").first.map(String.init) ?? ""
        if navigationResponse.isForMainFrame, (300..<400).contains(status) { return .allow }   // redirects are never downloads
        if navigationResponse.isForMainFrame, !navigationResponse.canShowMIMEType || disposition == "attachment" {
            return .download
        }
        return .allow
    }

    // MARK: downloads (WKDownload, native)

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    static func downloadsFolder() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }

    /// "report.pdf", "report (1).pdf", …; keeps compound extensions like .tar.gz; strips what a file name cannot hold.
    static func availableFileURL(for suggested: String, in folder: URL) -> URL {
        var name = suggested.components(separatedBy: CharacterSet.controlCharacters).joined()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "\\", with: "_")
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "download" }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let (base, ext): (String, String) = {
            if parts.count >= 3, parts[parts.count - 2].lowercased() == "tar" { return (parts.dropLast(2).joined(separator: "."), "." + parts.suffix(2).joined(separator: ".")) }
            if parts.count >= 2 { return (parts.dropLast().joined(separator: "."), "." + parts.last!) }
            return (name, "")
        }()
        var candidate = folder.appending(path: name)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(base) (\(index))\(ext)")
            index += 1
        }
        return candidate
    }

    /// Types that run when opened: the window never saves them (a page could otherwise drop an installer or
    /// a script into Downloads with the user's session behind it).
    static let refusedDownloadExtensions: Set<String> = ["app", "pkg", "dmg", "sh", "command", "scpt", "zsh", "bash", "pl", "py", "rb", "jar"]

    static func isRefusedDownload(_ filename: String) -> Bool {
        // Invisible characters (controls, zero-width and bidi marks) and trailing dots or spaces would hide
        // the real extension from a plain check.
        let visible = String(String.UnicodeScalarView(filename.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format
        }))
        let trimmed = visible.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return refusedDownloadExtensions.contains((trimmed as NSString).pathExtension.lowercased())
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = Self.downloadsFolder()
        let destination = Self.availableFileURL(for: suggestedFilename, in: folder)
        // Checked on the name the file is actually saved under, after sanitizing.
        if Self.isRefusedDownload(destination.lastPathComponent) {
            log("download refused: executable type")
            return nil
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        downloads[download] = destination
        log("download → .\(destination.pathExtension)")
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = downloads.removeValue(forKey: download) else { return }
        log("download finished .\(destination.pathExtension)")
        // Bounces the Downloads stack in the Dock, as Safari does.
        DistributedNotificationCenter.default().post(name: Notification.Name("com.apple.DownloadFileFinished"), object: destination.resolvingSymlinksInPath().path)
        onDownloadFinished?(destination)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads[download] = nil
        log("download failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log("nav.finish \(Self.redacted(webView.url))")
        if webView === self.webView { onNavigationFinished?(webView.url, webView.title) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log("nav.fail \(error.localizedDescription)")
    }

    /// A failure worth showing: not a cancellation, not a policy hand-off, and about the navigation that is
    /// actually pending (a late failure for a page the user already left is noise).
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log("nav.failProvisional \(error.localizedDescription)")
        guard webView === self.webView else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102) { return }
        let failing = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        if let failing, let pending = pendingMainFrameURL, failing != pending { log("ignoring stale failure for \(Self.redacted(failing))"); return }
        onNavigationError?(failing ?? pendingMainFrameURL, error)
    }

    /// One free reload; a second crash within 10 s means the page itself is the problem, so stop and tell.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let now = Date()
        if let lastCrash, now.timeIntervalSince(lastCrash) < 10 {
            log("web content process terminated again within 10 s; not reloading")
            onCrashLoop?()
            return
        }
        lastCrash = now
        log("web content process terminated (memory pressure / crash); reloading once")
        if webView.backForwardList.currentItem == nil || webView.reload() == nil, let url = pendingMainFrameURL ?? webView.url {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: WKUIDelegate (window.open / target=_blank popups: needed by SSO and some OAuth flows)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        log("ui.createWebView requested for \(Self.redacted(navigationAction.request.url)) type=\(navigationAction.navigationType.rawValue)")
        // A *click* on a target=_blank link is "a new tab": GitHub pages stay in this window, other sites go
        // to the browser. Anything scripted (window.open, with or without a URL) is a real popup with the
        // opener relationship intact, which sign-in and SSO flows need whatever their first URL is.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            if Self.staysInside(url), webView === self.webView {
                self.webView.load(navigationAction.request)
            } else {
                openInBrowser(url)
            }
            return nil
        }
        // The popup MUST be created with the configuration WebKit hands us (shares the data store + opener
        // relationship), but with a clean user content controller: our handlers and shim have no business
        // in an identity provider's page.
        configuration.userContentController = WKUserContentController()
        let screen = (self.webView.window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let requested = NSSize(width: windowFeatures.width?.doubleValue ?? 980, height: windowFeatures.height?.doubleValue ?? 760)
        let size = NSSize(width: min(screen.width, max(360, requested.width)), height: min(screen.height, max(280, requested.height)))
        let popup = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false   // ARC owns it through `popups`; AppKit must not release it too
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.title = navigationAction.request.url?.host ?? "Sign in"
        window.contentView = popup
        // Centred over the review window, clamped to its screen.
        if let parent = self.webView.window?.frame {
            let origin = NSPoint(x: max(screen.minX, min(screen.maxX - size.width, parent.midX - size.width / 2)),
                                 y: max(screen.minY, min(screen.maxY - size.height, parent.midY - size.height / 2)))
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        popupObservations[ObjectIdentifier(popup)] = [
            popup.observe(\.title, options: [.new]) { [weak window] w, _ in Task { @MainActor in
                let origin = w.url?.host ?? ""
                window?.title = [origin, w.title ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
            } },
            popup.observe(\.url, options: [.new]) { [weak window] w, _ in Task { @MainActor in if window?.title.isEmpty ?? true { window?.title = w.url?.host ?? "" } } },
        ]
        window.makeKeyAndOrderFront(nil)
        popups.append(window)
        // One teardown path for the red button, ⌘W and window.close(): the close notification.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] note in
            guard let closing = note.object as? NSWindow else { return }
            Task { @MainActor in self?.popups.removeAll { $0 === closing } }
        }
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.first { $0.contentView === webView }?.close()
    }

    private var popupObservations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]

    /// The review window closing takes its popups with it; a sign-in window without its opener is a trap.
    func closeOwnedPopups() {
        for window in popups { window.close() }
        popups.removeAll()
        popupObservations.removeAll()
    }

    // MARK: JavaScript dialogs and file uploads (WebKit has no built-in panels on macOS: without these,
    // every confirm() answers "cancel" in silence and <input type=file> does nothing)

    private func sheet(_ alert: NSAlert, on webView: WKWebView) async -> NSApplication.ModalResponse {
        if let window = webView.window, window.isVisible { return await alert.beginSheetModal(for: window) }
        return alert.runModal()
    }

    private func dialog(_ message: String, origin: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        let host = origin.securityOrigin.host.isEmpty ? "This page" : origin.securityOrigin.host
        alert.messageText = String(format: "%@ says", host)
        alert.informativeText = String(message.prefix(2000))
        return alert
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = dialog(message, origin: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = await sheet(alert, on: webView)
        log("js.confirm → \(response == .alertFirstButtonReturn)")
        return response == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = dialog(prompt, origin: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = await sheet(alert, on: webView)
        return response == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = !parameters.allowsDirectories
        panel.resolvesAliases = true
        panel.message = "Choose a file for \(frame.securityOrigin.host)"
        let response: NSApplication.ModalResponse
        if let window = webView.window, window.isVisible { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
        return response == .OK ? panel.urls : nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        log("js.alert")
        let alert = dialog(message, origin: frame)
        alert.addButton(withTitle: "OK")
        _ = await sheet(alert, on: webView)
    }
}

/// The page's own context menu offers "Open Link in New Window", which reaches `createWebViewWith` as a
/// scripted navigation and would become an in-app popup. Here "new window" means the default browser.
final class ReviewWebView: WKWebView {
    var openInBrowser: ((URL?) -> Void)?
    private var contextLink: URL?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items where item.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" {
            item.title = "Open Link in Browser"
            item.target = self
            item.action = #selector(openLinkInBrowser(_:))
            item.representedObject = contextLink
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Resolve the link under the pointer before the menu is built.
        let point = convert(event.locationInWindow, from: nil)
        let js = "(() => { const e = document.elementFromPoint(\(point.x), \(point.y)); const a = e && e.closest('a[href]'); return a ? a.href : null; })()"
        evaluateJavaScript(js) { [weak self] result, _ in self?.contextLink = (result as? String).flatMap(URL.init(string:)) }
        super.rightMouseDown(with: event)
    }

    @objc private func openLinkInBrowser(_ sender: NSMenuItem) {
        openInBrowser?(sender.representedObject as? URL ?? contextLink)
    }
}
