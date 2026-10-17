import AppKit
import Carbon.HIToolbox
import Observation

/// The popover's presentation as seen from outside SwiftUI. `MenuBarExtraAccess` binds `isPresented` to the
/// extra: it follows clicks on the icon and closes, and setting it false cancels the extra's own session,
/// the way SwiftUI does on Esc. The hotkey toggles through here; so does `PopoverDismissal`.
@MainActor @Observable
final class PopoverPresenter {
    static let shared = PopoverPresenter()
    var isPresented = false
    /// The extra's status item, handed over by `menuBarExtraAccess`.
    var statusItem: NSStatusItem?
    private var lastToggle = Date.distantPast

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

/// The system-wide shortcut that opens and closes the popover from any app: ⌥⌘P for now. Carbon's hot keys
/// need no Accessibility grant and are delivered whichever app is in front.
@MainActor
enum PopoverHotKey {
    private static var reference: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    static func install() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in PopoverPresenter.shared.toggle() }
            return noErr
        }, 1, &type, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x5047_4C4E), id: 1)  // "PGLN"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &reference)
        if status != noErr { AppLog.shared.info("hotkey: ⌥⌘P not registered, status \(status)") }
    }
}
