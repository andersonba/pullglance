import AppKit

/// MenuBarExtra's window grows with the content but never shrinks back: switching to a shorter tab left the
/// window at the taller height, with the content centered in it and a band of empty glass above. So the
/// popover reports its height and the window follows, keeping its top edge under the menu bar.
@MainActor
enum PopoverWindowFit {
    static func fit(height: CGFloat) {
        guard height > 0, let window = NSApp.windows.first(where: { $0.isVisible && $0.className.contains("MenuBarExtraWindow") }) else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        guard abs(content.height - height) > 0.5 else { return }
        var frame = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.minY, width: content.width, height: height))
        frame.origin.y = window.frame.maxY - frame.height
        window.setFrame(frame, display: true)
    }
}
