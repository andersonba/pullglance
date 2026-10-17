import AppKit
import SwiftUI

/// A small capsule floating over the page on Files and compare pages: how many files are still unviewed,
/// ▲▼ to the previous and next unviewed one, and one check. The check marks the current file and moves
/// to the next unviewed; on a file already viewed it is filled and unmarks instead. No path: the current
/// file is the outlined one on the page. ⌘↑ ⌘↓ still walk every file. The tests combo lives in the bar.
struct ReviewFilePill: View {
    let session: ReviewSession
    /// The moment the last file got viewed: a green pulse on the capsule and a bounce of the seal.
    @State private var celebrating = false

    /// Unviewed files, as the session counts them.
    private var left: Int? { session.unviewedLeft }

    var body: some View {
        if let file = session.currentFile {
            HStack(spacing: 8) {
                if left == 0 {
                    Label { Text("All viewed", bundle: .app) } icon: { Image(systemName: "checkmark.seal.fill") }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
                        .symbolEffect(.bounce, value: celebrating)
                        .lineLimit(1).fixedSize()
                } else {
                    Text("\(left ?? 0) left", bundle: .app)
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize()
                }
                // With files still unviewed the arrows go to those; once everything is viewed they walk
                // every file, so a mark can be undone from here. Two plain buttons rather than a ControlGroup:
                // the group becomes one segmented control and drops its children's tooltips.
                HStack(spacing: 2) {
                    Button { Task { await session.stepUnviewed(-1) } } label: { Image(systemName: "chevron.up").frame(width: 14) }
                        .help(left == 0 ? Text("Previous file (⌘↑)", bundle: .app) : Text("Previous unviewed file (⌘↑)", bundle: .app))
                    Button { Task { await session.stepUnviewed(1) } } label: { Image(systemName: "chevron.down").frame(width: 14) }
                        .help(left == 0 ? Text("Next file (⌘↓)", bundle: .app) : Text("Next unviewed file (⌘↓)", bundle: .app))
                }
                .buttonStyle(.bordered)
                .fixedSize()
                if let threads = session.pullRequest?.unresolvedThreads, threads > 0 {
                    // Open review threads: click goes to the next file that has one, ⌥-click to the previous.
                    Button {
                        let back = NSApp.currentEvent?.modifierFlags.contains(.option) == true
                        Task { await session.stepThread(back ? -1 : 1) }
                    } label: {
                        Label { Text(verbatim: "\(threads)") } icon: { Image(systemName: "text.bubble") }
                            .labelStyle(.titleAndIcon).font(.system(size: 11)).monospacedDigit()
                    }
                    .help(Text("Next file with an open thread · ⌥ previous", bundle: .app))
                }
                Button {
                    Task { file.viewed ? await session.unmarkCurrent() : await session.markCurrentAndNext() }
                } label: {
                    Image(systemName: file.viewed ? "checkmark.circle.fill" : "checkmark")
                        .frame(width: 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(file.viewed ? .green : .accentColor)
                .help(file.viewed ? Text("Viewed · click to unmark", bundle: .app) : Text("Mark this file as viewed and go to the next unviewed one (⌘↩)", bundle: .app))
            }
            .controlSize(.small)
            .disabled(session.busy)
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .background(Color.green.opacity(celebrating ? 0.28 : 0), in: Capsule())
            .overlay(Capsule().strokeBorder(celebrating ? Color.green.opacity(0.6) : .primary.opacity(0.08)))
            .shadow(color: celebrating ? .green.opacity(0.35) : .black.opacity(0.16), radius: celebrating ? 14 : 10, y: 4)
            .scaleEffect(celebrating ? 1.06 : 1)
            .animation(.spring(duration: 0.35, bounce: 0.4), value: celebrating)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("File controls", bundle: .app))
            .onChange(of: left) { old, new in
                guard new == 0, (old ?? 1) > 0 else { return }
                celebrating = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1500))
                    celebrating = false
                }
            }
        }
    }
}

/// "Tests · n" with the preset menu attached: the button marks, the arrow picks. `NSComboButton` is the
/// native control for exactly this (Finder's and Xcode's split buttons); SwiftUI has no equivalent.
struct TestsComboButton: NSViewRepresentable {
    let session: ReviewSession
    let editRules: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(session: session, editRules: editRules) }

    func makeNSView(context: Context) -> NSComboButton {
        let button = NSComboButton(title: "", menu: NSMenu(), target: context.coordinator, action: #selector(Coordinator.mark))
        button.style = .split
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSComboButton, context: Context) {
        button.title = String(localized: "Mark tests · \(session.matchCount)", bundle: .app)
        button.isEnabled = !session.busy && session.pageCounts != nil && session.matchCount > 0
        button.menu = context.coordinator.menu()
    }

    @MainActor
    final class Coordinator: NSObject {
        let session: ReviewSession
        let editRules: () -> Void

        init(session: ReviewSession, editRules: @escaping () -> Void) {
            self.session = session
            self.editRules = editRules
        }

        @objc func mark() { Task { await session.mark() } }

        @objc func choose(_ item: NSMenuItem) {
            guard let choice = item.representedObject as? Choice else { return }
            session.choose(choice.value)
        }

        @objc func rules() { editRules() }

        /// Boxed so `representedObject` can carry it; `ReviewPresetChoice` is a value type.
        final class Choice: NSObject {
            let value: ReviewPresetChoice
            init(_ value: ReviewPresetChoice) { self.value = value }
        }

        func menu() -> NSMenu {
            let menu = NSMenu()
            let counts = session.pageCounts?.perRule ?? [:]
            func add(_ title: String, _ choice: ReviewPresetChoice) {
                let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = Choice(choice)
                item.state = session.presetChoice == choice ? .on : .off
                menu.addItem(item)
            }
            add(String(localized: "Auto (enabled presets)", bundle: .app), .auto)
            for preset in ReviewPresets.all {
                add("\(preset.group) · \(preset.label) · \(counts[preset.id] ?? 0)", .preset(preset.id))
            }
            add(String(localized: "Custom globs", bundle: .app) + " · \(counts["custom"] ?? 0)", .custom)
            menu.addItem(.separator())
            let edit = NSMenuItem(title: String(localized: "Edit rules…", bundle: .app), action: #selector(rules), keyEquivalent: "")
            edit.target = self
            menu.addItem(edit)
            return menu
        }
    }
}
