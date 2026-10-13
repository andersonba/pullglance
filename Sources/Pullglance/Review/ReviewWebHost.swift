import AppKit
import WebKit

/// The review window's web view: navigation, popups, downloads, logging, and the page script through
/// `ReviewBridge` (injected into its own content world, storage in UserDefaults).
enum ExtensionEngine { case shim, webext }

@MainActor
final class ReviewWebHost: NSObject, WKNavigationDelegate, WKUIDelegate, WKWebExtensionControllerDelegate, WKDownloadDelegate {
    static let extensionID = "ghra-pullglance"

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
    let engine: ExtensionEngine
    /// Where our probes run: our isolated world with the shim, the page world with WebKit's engine (the
    /// extension's own world is WebKit's business; the DOM it changes is shared).
    var scriptWorld: WKContentWorld { engine == .shim ? Self.world : .page }
    private var extensionController: WKWebExtensionController?
    private(set) var extensionContext: WKWebExtensionContext?
    private var extensionWindow: ExtensionWindow?
    private var extensionTab: ExtensionTab?
    static let world = WKContentWorld.world(name: "ghra")

    let webView: WKWebView
    /// The page script's native half: the only script message handler on this web view.
    let bridge: ReviewBridge
    private(set) var logs: [String] = []
    private(set) var navigations: [String] = []
    var popups: [NSWindow] = []
    var onLog: ((String) -> Void)?

    init(userAgent: String? = nil, engine: ExtensionEngine = .webext) {
        self.engine = engine
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()            // persistent cookies / local storage
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")   // right click > Inspect Element
        // Some sign-in providers refuse the bare WebKit UA; every open-source browser adds Safari's token.
        config.applicationNameForUserAgent = "Version/\(Self.installedSafariVersion ?? "18.0") Safari/605.1.15"
        config.preferences.javaScriptCanOpenWindowsAutomatically = false   // popups only on a user gesture
        config.upgradeKnownHostsToHTTPS = true
        if engine == .webext {
            // Persistent, app-specific store for the extension's own data (chrome.storage), separate from ours.
            let controllerConfiguration = WKWebExtensionController.Configuration(identifier: UUID(uuidString: "6F3C2B1A-9D4E-4C8B-A1F2-0E5D7C9B3A21")!)
            controllerConfiguration.defaultWebsiteDataStore = .default()
            // The page web view's configuration is the basis for the extension's own web views; a controller
            // merely attached to a configuration does not deliver content scripts in every case.
            controllerConfiguration.webViewConfiguration = config
            let controller = WKWebExtensionController(configuration: controllerConfiguration)
            config.webExtensionController = controller   // must be set before the web view exists
            extensionController = controller
        }
        let ucc = config.userContentController
        let view = ReviewWebView(frame: NSRect(x: 0, y: 0, width: 1400, height: 1000), configuration: config)
        webView = view
        bridge = ReviewBridge(storage: ReviewStorage(defaults: .standard), log: { line in AppLog.shared.debug("review: \(line)") })
        bridge.attach(to: view)
        super.init()
        view.openInBrowser = { [weak self] url in self?.openInBrowser(url) }
        extensionController?.delegate = self

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

    /// Identity providers a sign-in flow may land on; clicks there must stay in the window or the user is
    /// thrown out of the SSO flow halfway (hivra's list plus the usual enterprise ones).
    static func isIdentityProvider(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        let exact: Set<String> = ["accounts.google.com", "appleid.apple.com", "login.microsoftonline.com", "login.live.com", "login.microsoft.com"]
        if exact.contains(host) { return true }
        for suffix in [".okta.com", ".oktapreview.com", ".auth0.com", ".onelogin.com", ".pingidentity.com", ".duosecurity.com", ".accounts.dev"] where host.hasSuffix(suffix) { return true }
        return false
    }

    /// `webkit-extension` is the extension's own pages (options), served by WebKit.
    static let webContentSchemes: Set<String> = ["http", "https", "about", "blob", "data", "javascript", "webkit-extension"]
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
            // Clicks leave for GitHub-foreign hosts, unless the page already is that host (an SSO provider
            // reached by redirect) or the host is a known identity provider.
            let currentHost = webView.url?.host?.lowercased()
            let sameHost = currentHost != nil && currentHost == url?.host?.lowercased()
            if !Self.staysInside(url), !sameHost, !Self.isIdentityProvider(url) {
                openInBrowser(url)
                return .cancel
            }
        }
        if webView === self.webView { pendingMainFrameURL = url }
        return .allow
    }

    // MARK: WebKit's extension engine (WKWebExtensionController, macOS 15.4+)

    /// Loads the extension bundle exactly as built for Chrome (Manifest V3) and tells WebKit about our one
    /// window and tab, which is what makes `tabs`/`runtime` behave and content scripts find their targets.
    func loadWebExtension() async throws {
        guard let controller = extensionController, extensionContext == nil else { return }
        guard let base = Bundle.app.url(forResource: "gh-review-assistant", withExtension: nil) else {
            throw NSError(domain: "Pullglance", code: 1, userInfo: [NSLocalizedDescriptionKey: "extension bundle missing from resources"])
        }
        let webExtension = try await WKWebExtension(resourceBaseURL: base)
        let context = WKWebExtensionContext(for: webExtension)
        // Storage is keyed by this identifier; left to WebKit it is a fresh UUID per launch, and every launch
        // would start the extension with an empty chrome.storage. Fix it, and the base URL stops changing too.
        context.uniqueIdentifier = "gh-review-assistant"
        // A fixed base URL too, so extension resources (CSS, options page) keep one origin across launches.
        context.baseURL = URL(string: "webkit-extension://7f1e2d3c-4b5a-4968-8c7d-6e5f4a3b2c1d/")!
        context.isInspectable = true
        // A bundled, trusted extension gets everything it asks for. `allRequestedMatchPatterns` already
        // includes the content scripts' `matches` (the manifest has no host_permissions), which is what
        // WebKit needs before it injects anything.
        for permission in webExtension.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
        for pattern in webExtension.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
        context.hasAccessToPrivateData = true
        try controller.load(context)
        extensionContext = context
        let window = ExtensionWindow(host: self)
        let tab = ExtensionTab(webView: webView, window: window, host: self)
        window.tabs = [tab]
        extensionWindow = window
        extensionTab = tab
        // The order WebKit expects, then the tab's properties kept current so `tabs.onUpdated` fires on
        // GitHub's soft navigations too (URL, title and loading change without a new document).
        controller.didOpenWindow(window)
        controller.didOpenTab(tab)
        controller.didActivateTab(tab, previousActiveTab: nil)
        controller.didFocusWindow(window)
        tabObservations = [
            webView.observe(\.url, options: [.new]) { [weak self, weak tab] _, _ in Task { @MainActor in
                guard let self, let tab else { return }; self.extensionController?.didChangeTabProperties([.URL], for: tab) } },
            webView.observe(\.title, options: [.new]) { [weak self, weak tab] _, _ in Task { @MainActor in
                guard let self, let tab else { return }; self.extensionController?.didChangeTabProperties([.title], for: tab) } },
            webView.observe(\.isLoading, options: [.new]) { [weak self, weak tab] _, _ in Task { @MainActor in
                guard let self, let tab else { return }; self.extensionController?.didChangeTabProperties([.loading], for: tab) } },
        ]
        if webExtension.hasBackgroundContent {
            do { try await context.loadBackgroundContent() } catch { log("webext background failed: \(error)") }
        }
        if !context.errors.isEmpty { log("webext context errors: \(context.errors.map(\.localizedDescription))") }
        log("webext loaded: \(webExtension.displayName ?? "?") v\(webExtension.version ?? "?") background=\(webExtension.hasBackgroundContent) permissions=\(context.currentPermissions.map(\.rawValue).sorted()) patterns=\(context.currentPermissionMatchPatterns.map(\.string).sorted()) options=\(context.optionsPageURL?.absoluteString ?? "-")")
    }

    private var tabObservations: [NSKeyValueObservation] = []

    /// Called when the review window closes: the extension must forget our tab and window.
    func closeExtensionTab() {
        guard let controller = extensionController, let tab = extensionTab, let window = extensionWindow else { return }
        controller.didCloseTab(tab, windowIsClosing: true)
        controller.didCloseWindow(window)
        tabObservations = []
    }

    /// `tabs.create` / `openOptionsPage` fallback: everything opens in the one web view we have.
    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration, for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void) {
        if let url = configuration.url {
            log("webext tabs.create \(Self.redacted(url)) → main web view")
            webView.load(URLRequest(url: url))
        }
        completionHandler(extensionTab, nil)
    }

    /// `runtime.sendNativeMessage`: the bridge from the extension to the app. Envelope `{method, params, id}`;
    /// the app answers in kind. Nothing uses it yet; this is where `gh` and local models will plug in.
    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?, for extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, Error?) -> Void) {
        log("webext native message received")
        replyHandler(["ok": true, "host": "pullglance-spike"], nil)
    }

    /// Bytes WebKit holds for the extension per storage type (local/session/sync): the only window we have into
    /// `chrome.storage` when WebKit owns it.
    func extensionStorageSizes() async -> [String: Int] {
        guard let controller = extensionController else { return [:] }
        let records = await controller.dataRecords(ofTypes: [.local, .session, .synchronized])
        var sizes: [String: Int] = [:]
        for record in records {
            sizes["local"] = (sizes["local"] ?? 0) + Int(record.sizeInBytes(ofTypes: [WKWebExtension.DataType.local]))
            sizes["session"] = (sizes["session"] ?? 0) + Int(record.sizeInBytes(ofTypes: [WKWebExtension.DataType.session]))
            sizes["sync"] = (sizes["sync"] ?? 0) + Int(record.sizeInBytes(ofTypes: [WKWebExtension.DataType.synchronized]))
        }
        return sizes
    }

    func extensionReport() -> [String: Any] {
        guard let context = extensionContext else { return ["loaded": false] }
        return [
            "loaded": context.isLoaded,
            "permissions": context.currentPermissions.map(\.rawValue).sorted(),
            "patterns": context.currentPermissionMatchPatterns.map(\.string).sorted(),
            "hasAccessToGitHub": context.hasAccess(to: URL(string: "https://github.com/")!),
            "hasInjectedContentForGitHub": context.hasInjectedContent(for: URL(string: "https://github.com/cli/cli/pull/1/files")!),
            "errors": context.errors.map { $0.localizedDescription },
            "optionsPage": context.optionsPageURL?.absoluteString ?? "",
        ]
    }

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        extensionWindow.map { [$0] } ?? []
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        extensionWindow
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        log("webext asked for permissions \(permissions.map(\.rawValue).sorted()); granted")
        completionHandler(permissions, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        log("webext asked for access to \(urls.map { Self.redacted($0) }.sorted()); granted")
        completionHandler(urls, nil)
    }

    /// The extension's own options page (its Preact UI), in a window of ours, served by WebKit.
    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let url = extensionContext.optionsPageURL else { return completionHandler(nil) }
        // Extension pages (webkit-extension://) only load in a web view built from the context's own
        // configuration; a plain configuration with the controller attached renders them blank.
        guard let configuration = extensionContext.webViewConfiguration else {
            log("webext: no webViewConfiguration for the options page")
            return completionHandler(nil)
        }
        let options = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 520), configuration: configuration)
        options.navigationDelegate = self
        let window = NSWindow(contentRect: options.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Extension options"
        window.contentView = options
        window.center()
        window.makeKeyAndOrderFront(nil)
        popups.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] note in
            guard let closing = note.object as? NSWindow else { return }
            Task { @MainActor in self?.popups.removeAll { $0 === closing } }
        }
        options.load(URLRequest(url: url))
        completionHandler(nil)
    }

    func openExtensionOptions() {
        guard let controller = extensionController, let context = extensionContext else { return }
        webExtensionController(controller, openOptionsPageFor: context) { _ in }
    }

    static func resource(_ name: String) -> String {
        guard let url = Bundle.app.url(forResource: name, withExtension: nil) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: logging

    /// Set by the interactive window: every line is appended here as it happens, so a test session can be
    /// read back even when stderr went nowhere.
    var logFileURL: URL?

    /// Log form of a URL: scheme, host and path only. Queries and fragments can carry sign-in tokens;
    /// titles never reach the log at all (the file log rule: repository and number, nothing from the PR).
    nonisolated static func redacted(_ url: URL?) -> String {
        guard let url else { return "-" }
        return (url.scheme.map { $0 + "://" } ?? "") + (url.host ?? "") + url.path
    }


    func log(_ line: String) {
        let stamp = String(format: "%.1f", Date().timeIntervalSince(ProcessInfo.processInfo.startTime))
        let full = "[\(stamp)s] \(line)"
        logs.append(full)
        onLog?(full)
        FileHandle.standardError.write(Data((full + "\n").utf8))
        if let logFileURL, let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((full + "\n").utf8))
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigations.append("start \(webView.url?.absoluteString ?? "-")")
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

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = Self.downloadsFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = Self.availableFileURL(for: suggestedFilename, in: folder)
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
        navigations.append("finish \(webView.url?.absoluteString ?? "-")")
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

    // MARK: helpers

    func evalInExtensionWorld(_ js: String) async -> Any? {
        do { return try await webView.evaluateJavaScript(js, in: nil, contentWorld: Self.world) }
        catch { log("eval error: \(error)"); return nil }
    }

    /// Probes run where the DOM is reachable for the engine in use (see `scriptWorld`).
    func evalInScriptWorld(_ js: String) async -> Any? {
        do { return try await webView.evaluateJavaScript(js, in: nil, contentWorld: scriptWorld) }
        catch { log("eval error: \(error)"); return nil }
    }

    /// Runs an async function body (may `await`) in the extension world and returns its resolved value.
    func callAsyncInExtensionWorld(_ body: String) async -> Any? {
        do { return try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: Self.world) }
        catch { log("callAsync error: \(error)"); return nil }
    }

    func callAsyncInPage(_ body: String) async -> Any? {
        do { return try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page) }
        catch { log("callAsync(page) error: \(error)"); return nil }
    }

    func evalInPage(_ js: String) async -> Any? {
        do { return try await webView.evaluateJavaScript(js, in: nil, contentWorld: .page) }
        catch { log("eval(page) error: \(error)"); return nil }
    }

    func snapshot(to url: URL) async {
        do {
            let image = try await webView.takeSnapshot(configuration: nil)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return log("snapshot: encode failed") }
            try png.write(to: url)
            log("snapshot written \(url.path) (\(Int(image.size.width))x\(Int(image.size.height)))")
        } catch {
            log("snapshot failed: \(error)")
        }
    }

    func cookies() async -> [HTTPCookie] {
        await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    }
}

extension ProcessInfo {
    var startTime: Date { ProcessStart.date }
}

enum ProcessStart {
    static let date = Date()
}

// MARK: - The one window and tab we tell WebKit's extension engine about

/// `WKWebExtensionWindow`: one normal window holding our tab, with the state WebKit may ask about.
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    var tabs: [ExtensionTab] = []
    weak var host: ReviewWebHost?
    private var nsWindow: NSWindow? { tabs.first?.webView.window }

    init(host: ReviewWebHost) { self.host = host }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { tabs }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { tabs.first }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let nsWindow else { return .normal }
        if nsWindow.isMiniaturized { return .minimized }
        if nsWindow.styleMask.contains(.fullScreen) { return .fullscreen }
        if nsWindow.isZoomed { return .maximized }
        return .normal
    }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
    func frame(for context: WKWebExtensionContext) -> CGRect { nsWindow?.frame ?? .zero }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { (nsWindow?.screen ?? NSScreen.main)?.frame ?? .zero }
    func focus(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        nsWindow?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }
}

/// `WKWebExtensionTab` around our web view, with the navigation the extension may request.
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    let webView: WKWebView
    weak var window: ExtensionWindow?
    weak var host: ReviewWebHost?

    init(webView: WKWebView, window: ExtensionWindow, host: ReviewWebHost) {
        self.webView = webView
        self.window = window
        self.host = host
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { window }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { 0 }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func title(for context: WKWebExtensionContext) -> String? { webView.title }
    func url(for context: WKWebExtensionContext) -> URL? { webView.url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !webView.isLoading }
    func isSelected(for context: WKWebExtensionContext) -> Bool { true }
    func size(for context: WKWebExtensionContext) -> CGSize { webView.bounds.size }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { webView.pageZoom }
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }
    func activate(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        webView.window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }
    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        webView.load(URLRequest(url: url))
        completionHandler(nil)
    }
    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if fromOrigin { webView.reloadFromOrigin() } else { webView.reload() }
        completionHandler(nil)
    }
    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) { webView.goBack(); completionHandler(nil) }
    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) { webView.goForward(); completionHandler(nil) }
    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        // The extension cannot close the review window; it can only clear the page.
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        completionHandler(nil)
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
