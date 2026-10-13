import AppKit
import SwiftUI
import QuartzCore
import WebKit

/// The review window: GitHub inside the app, with the native review bar driven by the page script, and
/// the handful of browser behaviors a page needs (address field with suggestions, back and
/// forward, reload or stop, find, zoom, downloads, popups for sign-in, error overlay). One window, reused.
///
/// Chrome follows the DuckDuckGo/Beam recipe: full-size content, transparent title bar, an empty toolbar
/// only for the unified title-bar height, and our own bar beneath the traffic lights.
@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    /// Created on first use by `configure(store:)`; nil until then (tests, snapshot runs).
    private(set) static var shared: ReviewWindowController?

    static func configure(store: PRStore) {
        if shared == nil { shared = ReviewWindowController(store: store) }
    }

    let store: PRStore
    let host: ReviewWebHost
    /// What the review bar shows and does for the page on screen.
    let session: ReviewSession
    private var observations: [NSKeyValueObservation] = []
    private var keyMonitor: Any?

    private var urlField: NSTextField!
    private var addressBar: AddressBarController!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var progress: NSProgressIndicator!
    private var findBar: NSStackView!
    private var findField: NSSearchField!
    private var findLabel: NSTextField!
    private var errorOverlay: NSView!
    private var errorTitle: NSTextField!
    private var errorMessage: NSTextField!
    private var errorRetryURL: URL?
    private var downloadNotice: NSView?
    private var barHost: NSHostingView<ReviewBar>!
    private var pillHost: NSHostingView<ReviewFilePill>!
    private var pillEdge: NSLayoutConstraint?
    private var barHeight: NSLayoutConstraint!
    private var modalHost: NSView?

    private init(store: PRStore) {
        self.store = store
        host = ReviewWebHost()
        session = ReviewSession(store: store, client: GHClient(), scripting: host.bridge, settings: .shared, defaults: .standard)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let initial = NSRect(x: 0, y: 0, width: min(1600, screen.width * 0.9), height: min(1200, screen.height * 0.9))
        let window = NSWindow(contentRect: initial,
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        host.onLog = { line in AppLog.shared.debug("review: \(line)") }
        host.bridge.onEvent = { [weak self] name, payload in self?.session.scriptEvent(name, payload) }
        window.title = Self.defaultTitle
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unifiedCompact
        window.tabbingMode = .disallowed
        window.animationBehavior = .documentWindow
        window.minSize = NSSize(width: 544, height: 300)
        window.delegate = self
        window.contentView = makeContent()
        window.initialFirstResponder = host.webView
        window.setFrameAutosaveName("ReviewWindow")
        if !window.setFrameUsingName("ReviewWindow") { window.center() }
        observe()
        observePill()
        observeBar()
        installKeyMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static let defaultTitle = String(localized: "Review", bundle: .app)

    // MARK: showing

    /// Opens a pull request. The popover is dismissed, the app activated (a menu bar app gets no keyboard
    /// otherwise), the extension loaded on first use, and the page loaded or re-used when already shown.
    func open(_ pr: PullRequest, landing: ReviewAddress.Landing) {
        open(url: ReviewAddress.url(for: pr, landing: landing))
    }

    func open(url: URL) {
        PopoverDismissal.dismiss()
        // While the window is up the app behaves like a regular one: Dock icon and ⌘-Tab, so the user can
        // come back to it after switching apps. Back to accessory when it closes.
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // Focus belongs to the page. Left alone, the window would hand it to the address field (the first
        // key view), which opens the suggestions over the page and freezes the field's text mid-edit.
        window?.makeFirstResponder(host.webView)
        refreshSuggestions()
        // Same pull request already on screen, whatever the tab: keep the page the user is on.
        if ReviewPage.classify(host.webView.url).isSamePullRequest(as: ReviewPage.classify(url)) { return }
        if host.webView.url != url { host.webView.load(URLRequest(url: url)) }
    }

    /// Owners after the owner filter, repositories, and the pull requests on screen: what the app already
    /// knows feeds the address suggestions, no request needed.
    private func refreshSuggestions() {
        var known: [String] = []
        for owner in store.knownOwners where !store.hiddenOwners.contains(owner.login) { known.append("https://github.com/\(owner.login)") }
        for repo in store.availableRepos { known.append("https://github.com/\(repo.fullName)"); known.append("https://github.com/\(repo.fullName)/pulls") }
        addressBar.known = known
        var prs: [(url: String, title: String)] = []
        let groups = store.mineGroups
        for section in [Section.needsAction, .readyToMerge, .waitingForReview, .drafts] { prs += groups[section].map { ($0.url.absoluteString, $0.title) } }
        prs += (store.directList + store.viaTeamList).map { ($0.url.absoluteString, $0.title) }
        addressBar.pullRequests = prs
    }

    // MARK: window lifecycle (the window hides; the web view stays warm so reopening is instant)

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveHistory()
        // The page script batches remembered compare state; write it before the window goes away.
        let bridge = host.bridge
        Task { _ = try? await bridge.call("flush", ["args": []]) }
        host.closeOwnedPopups()
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    // MARK: key routing (DuckDuckGo pattern)

    /// A `WKWebView` with focus swallows ⌘ shortcuts the page did not even ask for; handle the browser ones
    /// here when our window is key, and Esc in one place: find bar first, then the address bar's own Esc.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, NSApp.keyWindow === window else { return event }
            if event.keyCode == 53, self.modalHost != nil { self.dismissModal(); return nil }   // Escape
            if event.keyCode == 53, !self.findBar.isHidden { self.hideFind(); return nil }   // Escape
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let focusInWebView = window.firstResponder is WKWebView || (window.firstResponder as? NSView)?.superview is WKWebView
            guard focusInWebView || flags.contains(.command) else { return event }
            let key = event.charactersIgnoringModifiers ?? ""
            let reviewKeys = Self.handlesReviewShortcut(focusInWebView: focusInWebView, modalPresented: self.modalHost != nil, editingInPage: self.session.isEditingInPage)
            switch (flags, key) {
            case (.command, "r"): self.reload()
            case (.command, "l"): self.focusAddress()
            case (.command, "f"): self.showFind()
            case (.command, "g"): self.findNext()
            case ([.command, .shift], "G"), ([.command, .shift], "g"): self.findPrevious()
            case (.command, "w"): window.performClose(nil)
            case (.command, "["): self.goBack()
            case (.command, "]"): self.goForward()
            case (.command, "."): self.stop()
            case (.command, "+"), (.command, "="): self.zoomIn()
            case (.command, "-"): self.zoomOut()
            case (.command, "0"): self.zoomReset()
            case ([.command, .shift], "O"), ([.command, .shift], "o"): self.openInBrowser()
            // Review keys act only when the page has focus and no modal is up (text fields keep ⌘↓ etc.), and only
            // on review pages; elsewhere the page keeps them (⌘↓ scrolls to the end, etc.).
            case ([.command, .shift], "V"), ([.command, .shift], "v"):
                guard reviewKeys, self.session.page.showsBar else { return event }
                self.markTests()
            case (.command, "\r"), ([.command, .numericPad, .function], "\u{3}"):
                guard reviewKeys, self.session.showsFilePill else { return event }
                self.markViewedAndNext()
            case (.command, "\u{F701}"), ([.command, .function], "\u{F701}"), ([.command, .numericPad, .function], "\u{F701}"):
                guard reviewKeys, self.session.page.showsBar else { return event }
                self.nextUnviewed()
            case (.command, "\u{F700}"), ([.command, .function], "\u{F700}"), ([.command, .numericPad, .function], "\u{F700}"):
                guard reviewKeys, self.session.page.showsBar else { return event }
                self.previousUnviewed()
            case ([.command, .shift], "A"), ([.command, .shift], "a"):
                guard reviewKeys, self.session.pullRequest != nil else { return event }
                self.approvePR()
            case ([.command, .shift], "C"), ([.command, .shift], "c"):
                guard reviewKeys, self.session.pullRequest != nil else { return event }
                self.commentPR()
            case ([.command, .shift], "M"), ([.command, .shift], "m"):
                guard reviewKeys, self.session.pullRequest != nil else { return event }
                self.mergePR()
            case ([.command, .shift], "R"), ([.command, .shift], "r"):
                guard reviewKeys, self.session.page.showsBar else { return event }
                self.refreshReview()
            case ([.command, .option], "b"), ([.command, .option], "∫"):
                guard reviewKeys else { return event }
                self.toggleReviewBar()
            default: return event
            }
            return nil
        }
    }

    /// The review shortcuts belong to the page: never while typing in the address, find or modal fields, nor in
    /// the page's own fields (a GitHub comment box keeps ⇧⌘V Paste and Match Style and ⌘↑/⌘↓).
    nonisolated static func handlesReviewShortcut(focusInWebView: Bool, modalPresented: Bool, editingInPage: Bool) -> Bool {
        focusInWebView && !modalPresented && !editingInPage
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goBack): return activeWebView.canGoBack
        case #selector(goForward): return activeWebView.canGoForward
        case #selector(stop): return activeWebView.isLoading
        case #selector(markTests), #selector(undoMarking), #selector(nextUnviewed), #selector(previousUnviewed), #selector(refreshReview):
            return session.page.showsBar
        case #selector(approvePR), #selector(commentPR), #selector(mergePR), #selector(snoozePR):
            return session.pullRequest != nil
        case #selector(toggleReviewBar): return session.page.showsBar
        default: return true
        }
    }

    // MARK: observing the web view

    private func observe() {
        let web = host.webView
        observations = [
            web.observe(\.url, options: [.new]) { [weak self] w, _ in Task { @MainActor in
                guard let self else { return }
                self.addressBar.pageURL = w.url?.absoluteString ?? ""
                self.applyZoom(for: w.url)
                self.session.pageChanged(to: w.url)
            } },
            web.observe(\.title, options: [.new]) { [weak self] w, _ in Task { @MainActor in
                guard let self else { return }
                if let url = w.url?.absoluteString, let title = w.title, !title.isEmpty, self.addressBar.history[url] != nil {
                    self.addressBar.history[url]?.title = title
                }
                self.window?.title = ReviewAddress.windowTitle(pageTitle: w.title, url: w.url, fallback: Self.defaultTitle)
                self.window?.subtitle = w.url?.host ?? ""
            } },
            web.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in Task { @MainActor in self?.backButton.isEnabled = w.canGoBack } },
            web.observe(\.canGoForward, options: [.new]) { [weak self] w, _ in Task { @MainActor in self?.forwardButton.isEnabled = w.canGoForward } },
            web.observe(\.isLoading, options: [.new]) { [weak self] w, _ in Task { @MainActor in self?.loadingChanged(w.isLoading) } },
            web.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in Task { @MainActor in self?.progress.doubleValue = w.estimatedProgress } },
        ]
        host.onNavigationStart = { [weak self] in
            self?.errorOverlay.isHidden = true
            if self?.findBar.isHidden == false { self?.hideFind() }
        }
        host.onNavigationFinished = { [weak self] url, title in
            self?.remember(url, title: title)
            // Turbo can fire the `url` change before the content is there; a finished load settles it.
            self?.session.pageChanged(to: url)
        }
        host.onNavigationError = { [weak self] url, error in
            self?.showError(title: String(localized: "Could not load the page", bundle: .app), message: error.localizedDescription, retry: url)
        }
        host.onCrashLoop = { [weak self] in
            self?.showError(title: String(localized: "The page keeps crashing", bundle: .app), message: String(localized: "WebKit stopped rendering this page twice in a row.", bundle: .app), retry: self?.host.webView.url)
        }
        host.onDownloadFinished = { [weak self] file in self?.showDownloadNotice(file) }
    }

    private func loadingChanged(_ loading: Bool) {
        reloadButton.image = NSImage(systemSymbolName: loading ? "xmark" : "arrow.clockwise", accessibilityDescription: nil)
        reloadButton.toolTip = loading ? String(localized: "Stop (⌘.)", bundle: .app) : String(localized: "Reload (⌘R)", bundle: .app)
        reloadButton.setAccessibilityTitle(loading ? String(localized: "Stop", bundle: .app) : String(localized: "Reload", bundle: .app))
        if loading {
            progress.doubleValue = max(progress.doubleValue, 0.1)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.1; progress.animator().alphaValue = 1 }
        } else {
            progress.doubleValue = 1
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; progress.animator().alphaValue = 0 }) { [weak self] in
                Task { @MainActor in self?.progress.doubleValue = 0 }
            }
        }
    }

    // MARK: content

    private func symbolButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.toolTip = tip
        button.setAccessibilityTitle(tip.components(separatedBy: " (").first ?? tip)
        button.setAccessibilityIdentifier("ReviewWindow." + symbol)
        return button
    }

    private func makeContent() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 78, bottom: 6, right: 8)
        backButton = symbolButton("chevron.left", String(localized: "Back (⌘[)", bundle: .app), #selector(goBack))
        forwardButton = symbolButton("chevron.right", String(localized: "Forward (⌘])", bundle: .app), #selector(goForward))
        reloadButton = symbolButton("arrow.clockwise", String(localized: "Reload (⌘R)", bundle: .app), #selector(reloadOrStop))
        backButton.isEnabled = false
        forwardButton.isEnabled = false
        let field = AddressField(string: "")
        field.placeholderString = "github.com/owner/repo"
        field.cell?.sendsActionOnEndEditing = false
        field.cell?.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel(String(localized: "Address", bundle: .app))
        field.setAccessibilityIdentifier("ReviewWindow.Address")
        addressBar = AddressBarController(field: field) { [weak self] text, inBrowser in
            guard let self else { return }
            if inBrowser { self.host.openInBrowser(ReviewAddress.normalize(text)) } else { self.navigate(to: text) }
        }
        addressBar.history = loadHistory()
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlField = field
        for item in [backButton!, forwardButton!, reloadButton!, field, symbolButton("safari", String(localized: "Open page in browser (⇧⌘O)", bundle: .app), #selector(openInBrowser))] {
            bar.addArrangedSubview(item)
        }

        progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small
        progress.alphaValue = 0

        findBar = makeFindBar()
        findBar.isHidden = true

        let page = NSView()
        page.translatesAutoresizingMaskIntoConstraints = false
        errorOverlay = makeErrorOverlay()
        errorOverlay.isHidden = true
        // The web view lives in a frame-laid-out container, not under constraints: the docked Web Inspector
        // becomes a sibling of the web view and shrinks it with setFrame (WebInspectorUIProxyMac). Edge
        // constraints would restore the full frame on every layout pass, and the two fight: the page
        // flickers and the inspector ends up hidden behind it.
        let webContainer = NSView()
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        host.webView.translatesAutoresizingMaskIntoConstraints = true
        host.webView.autoresizingMask = [.width, .height]
        host.webView.frame = webContainer.bounds
        webContainer.addSubview(host.webView)
        page.addSubview(webContainer)
        page.addSubview(errorOverlay)
        pillHost = NSHostingView(rootView: ReviewFilePill(session: session))
        pillHost.translatesAutoresizingMaskIntoConstraints = false
        pillHost.isHidden = true
        pillHost.alphaValue = 0
        page.addSubview(pillHost)
        // Anchored to the web view, not the page: with the inspector docked the web view is the smaller
        // rectangle, and the pill must stay over the page, centred on it, not over the inspector.
        NSLayoutConstraint.activate([pillHost.centerXAnchor.constraint(equalTo: host.webView.centerXAnchor)])

        root.addArrangedSubview(bar)
        root.addArrangedSubview(progress)
        barHost = NSHostingView(rootView: ReviewBar(session: session, actions: barActions()))
        barHost.translatesAutoresizingMaskIntoConstraints = false
        // The height constraint owns the size (0 when hidden); SwiftUI's own min-height would fight it.
        barHost.sizingOptions = []
        barHost.clipsToBounds = true
        barHeight = barHost.heightAnchor.constraint(equalToConstant: 0)
        barHost.isHidden = true
        root.addArrangedSubview(barHost)
        NSLayoutConstraint.activate([barHost.widthAnchor.constraint(equalTo: root.widthAnchor), barHeight])
        root.addArrangedSubview(findBar)
        root.addArrangedSubview(page)
        // The field takes every point the buttons leave; hugging well below the buttons' keeps it the one that grows.
        field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        field.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalTo: root.widthAnchor),
            progress.widthAnchor.constraint(equalTo: root.widthAnchor),
            progress.heightAnchor.constraint(equalToConstant: 4),
            findBar.widthAnchor.constraint(equalTo: root.widthAnchor),
            page.widthAnchor.constraint(equalTo: root.widthAnchor),
            webContainer.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            webContainer.topAnchor.constraint(equalTo: page.topAnchor),
            webContainer.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            errorOverlay.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            errorOverlay.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            errorOverlay.topAnchor.constraint(equalTo: page.topAnchor),
            errorOverlay.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 212),
        ])
        return root
    }

    // MARK: file pill

    /// Follows `session.showsFilePill` and the position setting; fades rather than moving the page.
    private func observePill() {
        let (shows, position) = withObservationTracking { (session.showsFilePill, ReviewSettingsStore.shared.settings.filePill) } onChange: { [weak self] in
            Task { @MainActor in self?.observePill() }
        }
        placePill(position)
        guard pillHost.isHidden == shows, let edge = pillEdge else { return }
        // Slides in from its own edge (up from the bottom, down from the top) while fading; out the same way.
        let rest = Self.pillRest(position)
        let away = rest + (position == .bottom ? 14 : -14)
        if shows {
            edge.constant = away
            pillHost.superview?.layoutSubtreeIfNeeded()
            pillHost.isHidden = false
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = shows ? 0.22 : 0.15
            context.timingFunction = CAMediaTimingFunction(name: shows ? .easeOut : .easeIn)
            context.allowsImplicitAnimation = true
            edge.animator().constant = shows ? rest : away
            pillHost.animator().alphaValue = shows ? 1 : 0
            pillHost.superview?.layoutSubtreeIfNeeded()
        }) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if !self.session.showsFilePill { self.pillHost.isHidden = true }
                self.pillEdge?.constant = rest
            }
        }
    }

    private static func pillRest(_ position: FilePillPosition) -> CGFloat { position == .top ? 12 : -16 }

    private func placePill(_ position: FilePillPosition) {
        // The web view's frame is set by hand (autoresizing, and the docked inspector); its anchors follow it.
        let web = host.webView
        let wanted: NSLayoutConstraint = switch position {
        case .top: pillHost.topAnchor.constraint(equalTo: web.topAnchor, constant: Self.pillRest(.top))
        case .bottom: pillHost.bottomAnchor.constraint(equalTo: web.bottomAnchor, constant: Self.pillRest(.bottom))
        }
        if let pillEdge, pillEdge.firstAttribute == wanted.firstAttribute { return }
        pillEdge?.isActive = false
        wanted.isActive = true
        pillEdge = wanted
    }

    // MARK: review bar

    /// Follows `session.showsBar`, re-arming after each change; the bar's height animates between 0 and 32.
    private func observeBar() {
        let shows = withObservationTracking { session.showsBar } onChange: { [weak self] in
            Task { @MainActor in self?.observeBar() }
        }
        setBarVisible(shows)
    }

    private func setBarVisible(_ shows: Bool) {
        let target: CGFloat = shows ? 32 : 0
        guard barHeight.constant != target || barHost.isHidden == shows else { return }
        if shows { barHost.isHidden = false }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            barHeight.animator().constant = target
            barHost.superview?.layoutSubtreeIfNeeded()
        }) { [weak self] in
            Task { @MainActor in
                guard let self, !self.session.showsBar else { return }
                self.barHost.isHidden = true
            }
        }
    }

    private func barActions() -> ReviewBarActions {
        ReviewBarActions(
            approve: { [weak self] in self?.approvePR() },
            comment: { [weak self] in self?.commentPR() },
            merge: { [weak self] in self?.mergePR() },
            snooze: { [weak self] in self?.snoozePR() },
            openInBrowser: { [weak self] in self?.openInBrowser() },
            copyLink: { [weak self] in
                guard let url = self?.host.webView.url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            },
            hide: { [weak self] in self?.session.isBarHidden = true },
            reviewFiles: { [weak self] in
                guard let self, case .pullRequest(let repo, let number, _) = session.page,
                      let url = URL(string: "https://github.com/\(repo)/pull/\(number)/files") else { return }
                host.webView.load(URLRequest(url: url))
            })
    }

    /// The popover's modals, centered over the page; Esc or the modal's own buttons close it.
    private static func firstTextView(in view: NSView) -> NSTextView? {
        for sub in view.subviews {
            if let text = sub as? NSTextView { return text }
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }

    private func presentModal(_ make: (PullRequest, PRStore, @escaping @MainActor () -> Void) -> AnyView) {
        guard let pr = session.pullRequest, let content = window?.contentView, modalHost == nil else { return }
        let view = NSHostingView(rootView: make(pr, store, { [weak self] in self?.dismissModal() }))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 16
        shadow.shadowColor = .black.withAlphaComponent(0.25)
        view.shadow = shadow
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -40),
        ])
        modalHost = view
        // SwiftUI's own focus request fires before the hosted view is in a window; hand the keyboard to the
        // text view once it exists, so typing can start at once.
        Task { @MainActor [weak self, weak view] in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, let view, self.modalHost === view else { return }
                if let text = Self.firstTextView(in: view) { self.window?.makeFirstResponder(text); return }
            }
        }
    }

    private func dismissModal() {
        modalHost?.removeFromSuperview()
        modalHost = nil
        window?.makeFirstResponder(host.webView)
    }

    // The SwiftUI menu does not consult `validateMenuItem`, so each action checks it applies to the page.
    @objc func markTests() { if session.page.showsBar { Task { await session.mark() } } }
    @objc func markViewedAndNext() { if session.showsFilePill { Task { await session.markCurrentAndNext() } } }
    @objc func nextFile() { if session.showsFilePill { Task { await session.stepFile(1) } } }
    @objc func previousFile() { if session.showsFilePill { Task { await session.stepFile(-1) } } }
    @objc func undoMarking() { if session.page.showsBar { Task { await session.undo() } } }
    @objc func nextUnviewed() { if session.page.showsBar { Task { await session.scroll(.next) } } }
    @objc func previousUnviewed() { if session.page.showsBar { Task { await session.scroll(.previous) } } }
    @objc func refreshReview() { if session.page.showsBar { Task { await session.refresh() } } }
    @objc func toggleReviewBar() { session.isBarHidden.toggle() }

    @objc func approvePR() {
        guard modalHost == nil else { return }   // no stacked modals from the menu
        presentModal { pr, store, done in
            // The result refreshes the review state, which moves the decision chip; a failure shows in the bar.
            AnyView(ApproveView(pr: pr, store: store, onDone: { [weak self] result in
                done()
                guard let result else { return }
                Task { await self?.session.report(result) }
            }))
        }
    }

    @objc func commentPR() {
        guard modalHost == nil else { return }   // no stacked modals from the menu
        presentModal { pr, store, done in
            // The result refreshes the review state, which moves the decision chip; a failure shows in the bar.
            AnyView(CommentView(pr: pr, store: store, onDone: { [weak self] result in
                done()
                guard let result else { return }
                Task { await self?.session.report(result) }
            }))
        }
    }

    @objc func mergePR() {
        guard modalHost == nil else { return }   // no stacked modals from the menu
        presentModal { pr, store, done in
            // Same "previous failure" line as the popover's merge sheet.
            let previous: String? = if case .failed(.merge, let message) = store.actionState(for: pr) { message } else { nil }
            return AnyView(MergeConfirmView(pr: pr, store: store, previousFailure: previous) { [weak self] options in
                done()
                guard let options else { return }
                Task {
                    let result = await store.merge(pr, method: options.method, deleteBranch: options.deleteBranch)
                    await self?.session.report(result)
                }
            })
        }
    }

    @objc func snoozePR() {
        guard let pr = session.pullRequest else { return }
        if store.isDormant(pr) { store.wake(pr) } else { store.snooze(pr) }
    }

    // MARK: error overlay

    private func makeErrorOverlay() -> NSView {
        let container = NSVisualEffectView()
        container.material = .windowBackground
        container.state = .active
        container.translatesAutoresizingMaskIntoConstraints = false
        errorTitle = NSTextField(labelWithString: "")
        errorTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        errorMessage = NSTextField(wrappingLabelWithString: "")
        errorMessage.textColor = .secondaryLabelColor
        errorMessage.alignment = .center
        errorMessage.preferredMaxLayoutWidth = 420
        let retry = NSButton(title: String(localized: "Try Again", bundle: .app), target: self, action: #selector(retryFailedLoad))
        retry.keyEquivalent = "\r"
        let browser = NSButton(title: String(localized: "Open in Browser", bundle: .app), target: self, action: #selector(openFailedInBrowser))
        let buttons = NSStackView(views: [browser, retry])
        buttons.spacing = 8
        let stack = NSStackView(views: [errorTitle, errorMessage, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])
        return container
    }

    private func showError(title: String, message: String, retry: URL?) {
        errorTitle.stringValue = title
        errorMessage.stringValue = message + (retry.map { "\n\($0.absoluteString)" } ?? "")
        errorRetryURL = retry
        errorOverlay.isHidden = false
    }

    @objc func retryFailedLoad() {
        errorOverlay.isHidden = true
        if let errorRetryURL { host.webView.load(URLRequest(url: errorRetryURL)) } else { host.webView.reload() }
    }

    @objc func openFailedInBrowser() { host.openInBrowser(errorRetryURL ?? host.webView.url) }

    // MARK: download notice

    private func showDownloadNotice(_ file: URL) {
        guard let content = window?.contentView else { return }
        downloadNotice?.removeFromSuperview()
        let title = String(format: String(localized: "Downloaded %@ · Show in Finder", bundle: .app), file.lastPathComponent)
        let button = NSButton(title: title, target: self, action: #selector(revealDownload(_:)))
        button.bezelStyle = .inline
        button.controlSize = .small
        button.identifier = NSUserInterfaceItemIdentifier(file.path)
        button.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: content.topAnchor, constant: 52),
        ])
        downloadNotice = button
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak button] in button?.removeFromSuperview() }
    }

    @objc func revealDownload(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        sender.removeFromSuperview()
    }

    // MARK: history (url → visits, last visit, title)

    private static let historyKey = "reviewHistory"

    private func loadHistory() -> [String: AddressBarController.HistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([String: AddressBarController.HistoryEntry].self, from: data) else { return [:] }
        return decoded.filter { URL(string: $0.key)?.host?.contains(".") == true }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(addressBar.history) { UserDefaults.standard.set(data, forKey: Self.historyKey) }
    }

    private func remember(_ url: URL?, title: String?) {
        guard let url, let host = url.host, host.contains("."), url.scheme?.hasPrefix("http") == true else { return }
        addressBar.recordVisit(url.absoluteString, title: title)
        saveHistory()
    }

    // MARK: actions

    private var activeWebView: WKWebView {
        (NSApp.keyWindow?.contentView as? WKWebView) ?? host.webView
    }

    @objc func goBack() { activeWebView.goBack() }
    @objc func goForward() { activeWebView.goForward() }
    @objc func reload() { activeWebView.reload() }
    @objc func stop() { activeWebView.stopLoading() }
    @objc func reloadOrStop() { if activeWebView.isLoading { stop() } else { reload() } }
    @objc func openInBrowser() { host.openInBrowser(activeWebView.url) }
    @objc func focusAddress() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(urlField)
        urlField.selectText(nil)
    }

    private func navigate(to raw: String) {
        guard let url = ReviewAddress.normalize(raw) else { return }
        host.webView.load(URLRequest(url: url))
        window?.makeFirstResponder(host.webView)
    }

    // MARK: zoom (Safari's steps, remembered per host)

    private func zoomKey(_ url: URL?) -> String { "reviewZoom." + (url?.host ?? "default") }

    private func applyZoom(for url: URL?) {
        let stored = UserDefaults.standard.double(forKey: zoomKey(url))
        host.webView.pageZoom = stored == 0 ? 1 : CGFloat(stored)
    }

    private func setZoom(_ value: Double) {
        let target = activeWebView
        target.pageZoom = value
        target.magnification = 1
        if target === host.webView {
            if value == 1 { UserDefaults.standard.removeObject(forKey: zoomKey(target.url)) } else { UserDefaults.standard.set(value, forKey: zoomKey(target.url)) }
        }
    }
    @objc func zoomIn() { setZoom(ReviewAddress.zoomStep(after: activeWebView.pageZoom)) }
    @objc func zoomOut() { setZoom(ReviewAddress.zoomStep(before: activeWebView.pageZoom)) }
    @objc func zoomReset() { setZoom(1) }

    // MARK: find in page

    private func makeFindBar() -> NSStackView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        findField = NSSearchField()
        findField.placeholderString = String(localized: "Find in page", bundle: .app)
        findField.target = self
        findField.action = #selector(findNext)
        findField.sendsSearchStringImmediately = true
        findField.sendsWholeSearchString = false
        findField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        findLabel = NSTextField(labelWithString: "")
        findLabel.textColor = .secondaryLabelColor
        let prev = symbolButton("chevron.up", String(localized: "Previous (⇧⌘G)", bundle: .app), #selector(findPrevious))
        let next = symbolButton("chevron.down", String(localized: "Next (⌘G)", bundle: .app), #selector(findNext))
        let done = NSButton(title: String(localized: "Done", bundle: .app), target: self, action: #selector(hideFind))
        done.bezelStyle = .texturedRounded
        done.keyEquivalent = "\u{1b}"
        for item in [findField!, findLabel!, prev, next, done] { bar.addArrangedSubview(item) }
        return bar
    }

    @objc func showFind() {
        findBar.isHidden = false
        window?.makeFirstResponder(findField)
        findField.selectText(nil)
    }

    @objc func hideFind() {
        findBar.isHidden = true
        findLabel.stringValue = ""
        window?.makeFirstResponder(host.webView)
    }

    @objc func findNext() { find(backwards: false) }
    @objc func findPrevious() { find(backwards: true) }

    private func find(backwards: Bool) {
        let text = findField.stringValue
        guard !text.isEmpty else { findLabel.stringValue = ""; return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        host.webView.find(text, configuration: configuration) { [weak self] result in
            Task { @MainActor in self?.findLabel.stringValue = result.matchFound ? "" : String(localized: "Not found", bundle: .app) }
        }
    }
}
