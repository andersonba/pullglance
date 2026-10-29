import AppKit
import SwiftUI

/// The welcome window, and the what's new tour in the same shell: an NSWindow hosting `OnboardingView`,
/// shown on the first launch, once after an update, and from the status item's menu. One instance;
/// showing the list already up just brings it forward, another list replaces it. While it is up the app
/// is a regular one (Dock icon), back to accessory on close, like the review window.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: OnboardingWindowController?
    private static var store: PRStore?
    private static var progress = OnboardingProgress()
    private static var whatsNew = WhatsNewProgress()

    /// For `AppActivation`: the window, if it was ever created.
    static var window: NSWindow? { shared?.window }

    static func configure(store: PRStore, progress: OnboardingProgress = OnboardingProgress(), whatsNew: WhatsNewProgress = WhatsNewProgress()) {
        self.store = store
        self.progress = progress
        self.whatsNew = whatsNew
    }

    static func showIfDue() {
        guard progress.isDue else { return }
        show()
    }

    /// The welcome, as the menu's "Welcome…" asks for it.
    static func show() {
        present(OnboardingStep.all, style: .welcome)
    }

    /// Once after an update: the screens newer than the last version seen, newest release first. The
    /// version is marked seen as the window opens, so a crash or ⌘Q mid-tour does not bring it back.
    static func showWhatsNewIfDue() {
        guard let steps = whatsNewSteps(welcomeDue: progress.isDue, whatsNew: whatsNew, current: AppInfo.version) else { return }
        present(steps, style: .whatsNew)
        whatsNew.markSeen(version: AppInfo.version)
    }

    /// The menu's "What's new…": the latest release that has screens, whatever was seen.
    static func showWhatsNew() {
        let steps = WhatsNewStep.latest()
        guard !steps.isEmpty else { return }
        present(steps, style: .whatsNew)
    }

    /// What the launch should open as a tour, or nil: nothing while the welcome is owed (a newcomer sees
    /// the app itself), nothing on dev, nothing when no screen is newer than the seen version.
    static func whatsNewSteps(welcomeDue: Bool, whatsNew: WhatsNewProgress, current: String) -> [OnboardingStep]? {
        guard !welcomeDue, whatsNew.isDue(current: current) else { return nil }
        return WhatsNewStep.due(after: whatsNew.seenVersion)
    }

    private static func present(_ steps: [OnboardingStep], style: OnboardingView.Style) {
        guard let store else { return }
        PopoverDismissal.dismiss()
        if shared == nil { shared = OnboardingWindowController(store: store) }
        guard let shared else { return }
        let sameList = shared.window?.isVisible == true && shared.style == style && shared.model.steps.map(\.id) == steps.map(\.id)
        if !sameList {
            shared.model = OnboardingModel(steps: steps)
            shared.style = style
            shared.host.rootView = shared.makeView()
        }
        NSApp.setActivationPolicy(.regular)
        shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        shared.window?.makeKeyAndOrderFront(nil)
    }

    private let store: PRStore
    private let checker = RequirementChecker()
    private var model = OnboardingModel(steps: OnboardingStep.all)
    private var style: OnboardingView.Style = .welcome
    private var host: NSHostingView<OnboardingView>!
    private var keyMonitor: Any?

    private init(store: PRStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Pullglance"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        host = NSHostingView(rootView: makeView())
        window.contentView = host
        window.center()
        installKeyMonitor()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func makeView() -> OnboardingView {
        OnboardingView(store: store, checker: checker, model: model, style: style,
                       ghPassed: { Self.markCompletedIfDue() },
                       finish: { [unowned self] in finish() },
                       quit: { NSApp.terminate(nil) })
    }

    /// The welcome's send-off leaves a dot on the icon so the newcomer finds it; the tour just closes.
    private func finish() {
        if style == .welcome {
            Self.markCompletedIfDue()
            store.showIconDot()
        }
        window?.close()
    }

    private static func markCompletedIfDue() {
        if progress.isDue { progress.markCompleted(version: AppInfo.version) }
    }

    /// ← → move between steps (Continue only when allowed), Esc closes; only while this window is key.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, NSApp.keyWindow === window else { return event }
            switch event.keyCode {
            case 53: window.close(); return nil
            case 123: self.model.go(to: self.model.step - 1); return nil
            case 124:
                let ghStep = self.model.steps[self.model.step].content == .requirements
                if !ghStep || self.checker.allPassed { self.model.go(to: self.model.step + 1) }
                return nil
            default: return event
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        checker.stop()
        if style == .welcome, OnboardingProgress.shouldMarkCompleted(onClose: checker.allPassed) { Self.markCompletedIfDue() }
        model.step = 0
        if let window { AppActivation.windowClosed(window) }
    }
}
