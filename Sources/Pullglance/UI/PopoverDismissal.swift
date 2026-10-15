import AppKit

/// MenuBarExtra offers no API to close its window, and closing it ourselves left the extra's bookkeeping
/// behind: on macOS 26 the status item is shown "active" by a replicant the system draws over it, and that
/// stayed until a real click elsewhere reached the extra's global event monitor, so the popover took two
/// clicks to come back. The extra does close on Esc, through its own path, and a key event posted to our
/// own window is delivered like a typed one. So dismissing is typing Esc at the popover.
@MainActor
enum PopoverDismissal {
    private static var escapePostedAt: Date?

    static func dismiss() {
        guard let key = NSApp.keyWindow, key.className.contains("MenuBarExtraWindow") else { return }
        escapePostedAt = Date()
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: key.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                            isARepeat: false, keyCode: 53) {
                NSApp.postEvent(event, atStart: true)
            }
        }
    }

    /// Whether a key event is the Esc posted by `dismiss`, which the triage must let through to the extra
    /// rather than spend on leaving its keyboard focus.
    static func isDismissal(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, let at = escapePostedAt, Date().timeIntervalSince(at) < 1 else { return false }
        if event.type == .keyUp { escapePostedAt = nil }
        return true
    }

    /// Before opening anything in the browser: it takes key status away from us, so dismiss first.
    static func open(_ url: URL) {
        dismiss()
        NSWorkspace.shared.open(url)
    }
}
