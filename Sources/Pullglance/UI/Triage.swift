import AppKit
import SwiftUI

/// Keyboard triage in the popover. ↓ starts it: a focus walks the rows on screen, in display order, and
/// single letters act on the focused row. Pure state; the list's `ScrollWheelMonitor` feeds it the keys, `PopoverView` applies it.
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

/// The keys triage answers to: plain keys, plus ⌘C (copy link) and ⌘/ (the shortcuts card), the two whose
/// plain letters are taken. Anything else with ⌘, ⌥ or ⌃ belongs to the menus.
enum TriageKey: Equatable {
    case up, down, left, right, space, pin, snooze, snoozeFor, open, review, refresh, comment, merge, copyLink, shortcuts, filter, escape

    init?(characters: String?, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let held = modifiers.intersection([.command, .option, .control])
        if held == [.command] {
            switch characters?.lowercased() {
            case "c": self = .copyLink
            case "/": self = .shortcuts
            default: return nil
            }
            return
        }
        if !held.isEmpty { return nil }
        // ⇧S asks for how long; the other letters ignore shift.
        if modifiers.contains(.shift), characters?.lowercased() == "s" { self = .snoozeFor; return }
        switch keyCode {
        case 125: self = .down; return
        case 126: self = .up; return
        case 123: self = .left; return
        case 124: self = .right; return
        case 53: self = .escape; return
        case 36, 76: self = .review; return
        case 49: self = .space; return
        default: break
        }
        switch characters?.lowercased() {
        // Vim's hjkl are the arrows; the rest of the triage never knows which was pressed.
        case "j": self = .down
        case "k": self = .up
        case "h": self = .left
        case "l": self = .right
        case "p": self = .pin
        case "s": self = .snooze
        case "o": self = .open
        case "r": self = .refresh
        case "c": self = .comment
        case "m": self = .merge
        case "f": self = .filter
        case "\r": self = .review
        default: return nil
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
            hint("↩", Text(ReviewSettingsStore.shared.settings.windowEnabled ? "Desk" : "Open", bundle: .app))
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

/// Every key the app answers to, in one card over the popover (⌘/ or the ⋯ menu). Grouped by where the
/// hands are: the popover, a focused row, the review window.
struct ShortcutsCard: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyboard shortcuts", bundle: .app).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help(Text("Exit", bundle: .app))
            }
            group(Text("Popover", bundle: .app)) {
                if let hotkey = PopoverHotKey.current { line(Text("Open from any app", bundle: .app), [hotkey]) }
                line(Text("Refresh", bundle: .app), ["⌘R"])
                line(Text("Quick filters", bundle: .app), ["0", "–", "9"])
                line(Text("Switch tab", bundle: .app), ["←", "→", "H", "L"])
                line(Text("Filter by repository or author", bundle: .app), ["F"])
                line(Text("Settings…", bundle: .app), ["⌘,"])
            }
            group(Text("Row under the pointer", bundle: .app)) {
                line(Text("Every key of a focused row", bundle: .app), ["↩", "P", "S", "R", "C", "M", "O", "⌘C"])
                line(Text("Keyboard from here", bundle: .app), ["space"])
            }
            group(Text("Focused row", bundle: .app)) {
                line(Text("Start · Move", bundle: .app), ["↓", "↑", "J", "K"])
                line(Text("Open in Desk", bundle: .app), ["↩"])
                line(Text("Row menu", bundle: .app), ["space"])
                line(Text("Pin · Snooze · Refresh", bundle: .app), ["P", "S", "R"])
                line(Text("Snooze for…", bundle: .app), ["⇧S"])
                line(Text("Comment · Merge", bundle: .app), ["C", "M"])
                line(Text("Open on GitHub · Copy link", bundle: .app), ["O", "⌘C"])
                line(Text("Exit", bundle: .app), ["esc"])
            }
            if ReviewSettingsStore.shared.settings.windowEnabled {
                group(Text("Review Desk", bundle: .app)) {
                    line(Text("Mark viewed · Mark tests", bundle: .app), ["⌘↩", "⇧⌘V"])
                    line(Text("Previous · Next file", bundle: .app), ["⌘↑", "⌘↓"])
                    line(Text("Approve · Comment · Merge", bundle: .app), ["⇧⌘A", "⇧⌘C", "⇧⌘M"])
                    line(Text("Review bar", bundle: .app), ["⌥⌘B"])
                    line(Text("Find · Address bar · Open in browser", bundle: .app), ["⌘F", "⌘L", "⇧⌘O"])
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }

    private func group(_ title: Text, @ViewBuilder lines: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            title.font(.caption2).textCase(.uppercase).foregroundStyle(.secondary).kerning(0.4)
            lines()
        }
    }

    private func line(_ label: Text, _ keys: [String]) -> some View {
        HStack(spacing: 6) {
            label.font(.system(size: 11)).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { k in
                    if k == "–" {
                        Text(verbatim: k).font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: k)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }
}

/// The ⇧S card: how long to snooze this row. "Until activity" first, then the timed ones; ↑↓ move, ↩ picks,
/// esc leaves. The current choice is highlighted the way a focused row is.
struct SnoozeCard: View {
    let pr: PullRequest
    @Binding var choice: Int
    let pick: (SnoozeDuration?) -> Void
    let close: () -> Void

    /// nil is "until activity".
    static let choices: [SnoozeDuration?] = [nil] + SnoozeDuration.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Snooze for…", bundle: .app).font(.headline)
                    Text(verbatim: pr.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help(Text("Exit", bundle: .app))
            }
            VStack(spacing: 2) {
                ForEach(Array(Self.choices.enumerated()), id: \.offset) { index, duration in
                    Button { pick(duration) } label: {
                        HStack {
                            Image(systemName: duration == nil ? "bolt" : "clock").frame(width: 14)
                            Text(verbatim: duration?.label ?? String(localized: "Until activity", bundle: .app))
                            Spacer()
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(index == choice ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { if $0 { choice = index } }
                }
            }
            Text("Until activity: a new commit, review decision or CI result", bundle: .app)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
}
