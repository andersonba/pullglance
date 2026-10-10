import AppKit

/// MenuBarExtra offers no API to close its window, so close the key window, which is the popover
/// whenever the user is interacting with it. Call it before opening anything in the browser,
/// because the browser takes key status away from us.
@MainActor
enum PopoverDismissal {
    static func dismiss() {
        NSApp.keyWindow?.close()
    }

    static func open(_ url: URL) {
        dismiss()
        NSWorkspace.shared.open(url)
    }
}
