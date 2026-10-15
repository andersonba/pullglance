import AppKit

/// The app is an accessory (no Dock icon) until one of its regular windows is up: the review window or
/// the welcome window. Closing one must not take the Dock icon from the other while it stays open.
@MainActor
enum AppActivation {
    static func windowClosed(_ window: NSWindow) {
        let others = [ReviewWindowController.shared?.window, OnboardingWindowController.window]
            .compactMap { $0 }
            .filter { $0 !== window }
            .map(\.isVisible)
        if shouldReturnToAccessory(otherVisible: others) { NSApp.setActivationPolicy(.accessory) }
    }

    nonisolated static func shouldReturnToAccessory(otherVisible: [Bool]) -> Bool { !otherVisible.contains(true) }
}
