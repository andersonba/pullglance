import AppKit
import SwiftUI

/// The welcome window: an NSWindow hosting `OnboardingView`, shown on the first launch and from the
/// status item's menu. One instance; `show()` while it is up just brings it forward. While it is up
/// the app is a regular one (Dock icon), back to accessory on close, like the review window.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: OnboardingWindowController?
    private static var store: PRStore?
    private static var progress = OnboardingProgress()

    /// For `AppActivation`: the window, if it was ever created.
    static var window: NSWindow? { shared?.window }

    static func configure(store: PRStore, progress: OnboardingProgress = OnboardingProgress()) {
        self.store = store
        self.progress = progress
    }

    static func showIfDue() {
        guard progress.isDue else { return }
        show()
    }

    static func show() {
        guard let store else { return }
        PopoverDismissal.dismiss()
        if shared == nil { shared = OnboardingWindowController(store: store) }
        NSApp.setActivationPolicy(.regular)
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    private let store: PRStore
    private let checker = RequirementChecker()
    private let model = OnboardingModel()
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
        OnboardingView(store: store, checker: checker, model: model,
                       ghPassed: { Self.markCompletedIfDue() },
                       finish: { [unowned self] in finish() },
                       quit: { NSApp.terminate(nil) })
    }

    private func finish() {
        Self.markCompletedIfDue()
        store.showIconDot()
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
                let ghStep = OnboardingStep.all[self.model.step].content == .requirements
                if !ghStep || self.checker.allPassed { self.model.go(to: self.model.step + 1) }
                return nil
            default: return event
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        checker.stop()
        if OnboardingProgress.shouldMarkCompleted(onClose: checker.allPassed) { Self.markCompletedIfDue() }
        model.step = 0
        if let window { AppActivation.windowClosed(window) }
    }
}
