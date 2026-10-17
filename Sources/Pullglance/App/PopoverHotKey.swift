import AppKit
import KeyboardShortcuts
import Observation

/// The popover's presentation as seen from outside SwiftUI. `MenuBarExtraAccess` binds `isPresented` to the
/// extra: it follows clicks on the icon and closes, and setting it false cancels the extra's own session,
/// the way SwiftUI does on Esc. The hotkey toggles through here; so does `PopoverDismissal`.
@MainActor @Observable
final class PopoverPresenter {
    static let shared = PopoverPresenter()
    var isPresented = false {
        didSet {
            guard isPresented, !oldValue else { return }
            // A breaker for a presentation that feeds on itself: the library re-presents a window that loses
            // the key as soon as it appears, each time the binding flips back to true, and the main thread
            // never comes up for air. Nobody opens the popover ten times in two seconds on purpose.
            let now = Date()
            openings.removeAll { now.timeIntervalSince($0) > Self.burstWindow }
            openings.append(now)
            if openings.count > Self.burstLimit {
                AppLog.shared.info("popover: \(openings.count) openings in \(Int(Self.burstWindow)) s, refusing this one")
                openings.removeAll()
                isPresented = false
            }
        }
    }
    /// The extra's status item, handed over by `menuBarExtraAccess`.
    var statusItem: NSStatusItem?
    private var lastToggle = Date.distantPast
    private var openings: [Date] = []
    static let burstLimit = 9
    static let burstWindow: TimeInterval = 2

    func toggle() {
        // One press, one toggle: the Carbon handler has been seen firing several times per press.
        let now = Date()
        guard now.timeIntervalSince(lastToggle) > 0.25 else { return }
        lastToggle = now
        if isPresented {
            isPresented = false
            AppLog.shared.debug("hotkey: popover closed")
            return
        }
        // On macOS 27 the window belongs to a session that the system's menu bar host runs, and only the
        // host's own sessions light the icon. So the host is asked to begin one, as a click would; a session
        // begun from our side (the library's path) would open the window with the icon unlit. The library
        // stays as the fallback when nothing is up shortly after, and on systems without the request.
        let request = NSSelectorFromString("_requestExpandedInterfaceSession")
        if let statusItem, statusItem.responds(to: request) {
            _ = statusItem.perform(request)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if Self.extraWindow == nil {
                isPresented = true
                AppLog.shared.debug("hotkey: popover opened through the library")
            } else {
                AppLog.shared.debug("hotkey: popover opened by the host")
            }
        }
    }

    static var extraWindow: NSWindow? {
        NSApp.windows.first { $0.className.contains("MenuBarExtraWindow") && $0.isVisible }
    }
}

/// The system-wide shortcut that opens and closes the popover from any app: ⌥⌘P unless the user records
/// another one in Settings › General. KeyboardShortcuts keeps the choice in the defaults and registers the hot
/// key (Carbon: no Accessibility grant, delivered whichever app is in front).
@MainActor
enum PopoverHotKey {
    static func install() {
        KeyboardShortcuts.onKeyDown(for: .togglePopover) { PopoverPresenter.shared.toggle() }
    }

    /// The shortcut as the cards print it ("⌥⌘P"), nil when the user removed it.
    static var current: String? { KeyboardShortcuts.getShortcut(for: .togglePopover)?.description }
}

extension KeyboardShortcuts.Name {
    static let togglePopover = Self("togglePopover", initial: .init(.p, modifiers: [.option, .command]))
}
