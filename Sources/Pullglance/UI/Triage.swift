import AppKit
import SwiftUI

/// Keyboard triage in the popover. ↓ starts it: a focus walks the rows on screen, in display order, and
/// single letters act on the focused row. Pure state; `KeyDownMonitor` feeds it, `PopoverView` applies it.
struct TriageFocus: Equatable {
    private(set) var id: PullRequest.ID?

    /// One step down (+1) or up (-1) through `rows`. Nothing focused: ↓ takes the first row, ↑ does nothing.
    /// A focused row that left the list starts over from the first.
    mutating func move(_ step: Int, in rows: [PullRequest.ID]) {
        guard !rows.isEmpty else { id = nil; return }
        guard let id, let index = rows.firstIndex(of: id) else {
            if step > 0 { id = rows[0] }
            return
        }
        self.id = rows[min(max(index + step, 0), rows.count - 1)]
    }

    mutating func set(_ id: PullRequest.ID?) { self.id = id }
    mutating func clear() { id = nil }

    /// After pin or snooze the row leaves its place: the row below slides in and is next; at the end, the
    /// one above. Nil when it was alone.
    static func successor(of id: PullRequest.ID, in rows: [PullRequest.ID]) -> PullRequest.ID? {
        guard let index = rows.firstIndex(of: id) else { return nil }
        if index + 1 < rows.count { return rows[index + 1] }
        return index > 0 ? rows[index - 1] : nil
    }
}

/// The keys triage answers to. Plain keys only: anything with ⌘, ⌥ or ⌃ belongs to the menus.
enum TriageKey: Equatable {
    case up, down, left, right, pin, snooze, open, review, escape

    init?(characters: String?, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        if !modifiers.intersection([.command, .option, .control]).isEmpty { return nil }
        switch keyCode {
        case 125: self = .down; return
        case 126: self = .up; return
        case 123: self = .left; return
        case 124: self = .right; return
        case 53: self = .escape; return
        case 36, 76: self = .review; return
        default: break
        }
        switch characters?.lowercased() {
        case "p": self = .pin
        case "s": self = .snooze
        case "o": self = .open
        case "\r": self = .review
        default: return nil
        }
    }
}

/// Key presses of the view's own window. The handler returns true to swallow the event.
struct KeyDownMonitor: NSViewRepresentable {
    let handler: @MainActor (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { (view as? MonitorView)?.handler = handler }

    final class MonitorView: NSView {
        var handler: (@MainActor (NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window, let handler = self.handler else { return event }
                return MainActor.assumeIsolated { handler(event) } ? nil : event
            }
        }
    }
}

/// The footer while a row is focused: the keys, in place of the status line. Arrows speak for themselves;
/// the letters say what they do to this row (Unpin on a pinned one, Wake on a snoozed one). Drawn over the
/// regular footer, which gives the height, so nothing jumps.
struct TriageFooter: View {
    var isPinned = false
    var isDormant = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) { key("↑↓"); key("←→") }.layoutPriority(1)
            hint("↩", Text("Review", bundle: .app))
            hint("P", Text(isPinned ? "Unpin" : "Pin", bundle: .app))
            hint("S", Text(isDormant ? "Wake" : "Snooze", bundle: .app))
            hint("O", Text(verbatim: "GitHub"))
            Spacer(minLength: 0)
            hint("esc", Text("Exit", bundle: .app))
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    private func key(_ key: String) -> some View {
        Text(verbatim: key)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }

    private func hint(_ k: String, _ label: Text) -> some View {
        HStack(spacing: 4) {
            key(k)
            label.foregroundStyle(.secondary)
        }
        .layoutPriority(1)
    }
}
