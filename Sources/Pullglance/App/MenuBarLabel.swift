import AppKit
import SwiftUI

/// The status item: the icon and the count. Drawn as one template image rather than as SwiftUI text, because
/// the `MenuBarExtra` label is rasterized and only redrawn when its text or image changes; drawing it
/// ourselves is what lets the number roll like an odometer when it changes (see `BadgeRoll`).
struct MenuBarLabel: View {
    /// `badgeText` from the store: nil before the first data or when there is nothing to count.
    let text: String?
    /// Whether a refresh has ever succeeded; decides between "…" and nothing when `text` is nil.
    let hasData: Bool
    let isError: Bool
    /// The roll in flight, if any.
    var roll: BadgeRoll? = nil
    /// A timed snooze ended while the popover was closed: an orange dot on the icon until it is opened.
    var showsWokeDot = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(nsImage: Self.render(text: shown, isError: isError, roll: text == nil ? nil : roll, dot: showsWokeDot))
            // The right-click menu (`StatusItemMenu`) lives in AppKit; this is its way to the Settings scene.
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in openSettings() }
    }

    private var shown: String? {
        if let text { return text }
        if !hasData, !isError { return "…" }
        return nil
    }

    static let height: CGFloat = 18
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    private static let gap: CGFloat = 3

    private static func symbol(isError: Bool, tinted: Bool) -> NSImage {
        var configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if tinted { configuration = configuration.applying(.init(paletteColors: [.labelColor])) }
        return NSImage(systemSymbolName: isError ? "exclamationmark.triangle" : "arrow.triangle.pull", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
    }

    /// Icon, then the count. During a roll the characters that differ (right-aligned) slide, the old one out
    /// through the top and the new one in from below, the other way when the count fell; the rest stand still.
    /// Texts of different lengths roll as a whole.
    /// With `dot`, the image stops being a template (a template cannot carry color): the glyph and the
    /// count are drawn in the label color instead, which the handler resolves for the menu bar's appearance
    /// each time it draws, and an orange dot sits on the icon's top-right corner.
    static func render(text: String?, isError: Bool, roll: BadgeRoll? = nil, dot: Bool = false) -> NSImage {
        let symbol = symbol(isError: isError, tinted: dot)
        let iconSize = symbol.size
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dot ? NSColor.labelColor : NSColor.black]
        let resting = roll?.to ?? text
        let columns: [(old: String, new: String)]
        if let roll {
            let from = Array(roll.from), to = Array(roll.to)
            columns = from.count == to.count ? zip(from, to).map { (String($0), String($1)) } : [(roll.from, roll.to)]
        } else {
            columns = resting.map { [($0, $0)] } ?? []
        }
        let widths = columns.map { max(NSAttributedString(string: $0.old, attributes: attrs).size().width, NSAttributedString(string: $0.new, attributes: attrs).size().width) }
        let textWidth = widths.reduce(0, +)
        let lineHeight = NSAttributedString(string: "0", attributes: attrs).size().height
        let size = NSSize(width: ceil(iconSize.width + (columns.isEmpty ? 0 : gap + textWidth)), height: height)
        let progress = roll?.progress ?? 1
        let up = roll?.up ?? true
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: NSRect(x: 0, y: (rect.height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height))
            var x = iconSize.width + gap
            let baseY = (rect.height - lineHeight) / 2
            // Clip to the text band so the sliding glyphs appear and vanish at its edges.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: baseY - 1, width: rect.width, height: lineHeight + 2)).addClip()
            for (column, width) in zip(columns, widths) {
                if column.old == column.new {
                    NSAttributedString(string: column.new, attributes: attrs).draw(at: NSPoint(x: x, y: baseY))
                } else {
                    let travel = (lineHeight + 2) * (up ? 1 : -1)
                    NSAttributedString(string: column.old, attributes: attrs).draw(at: NSPoint(x: x, y: baseY + travel * progress))
                    NSAttributedString(string: column.new, attributes: attrs).draw(at: NSPoint(x: x, y: baseY - travel * (1 - progress)))
                }
                x += width
            }
            NSGraphicsContext.restoreGraphicsState()
            if dot {
                let dotRect = NSRect(x: iconSize.width - 5, y: rect.height - 7, width: 6, height: 6)
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = !dot
        image.accessibilityDescription = resting
        return image
    }
}
