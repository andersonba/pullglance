import AppKit
import SwiftUI

/// Floating card over the page on Files and compare pages: where the reader is, and the file work.
/// Header: the current path, fixed width and truncated from the start so the end stays visible, plus the
/// position. Row: ▲▼ as a segmented group, "Mark viewed" (marks and moves to the next unviewed), and the
/// tests combo button. Every control is the small native size; the row's width never follows the file.
struct ReviewFilePill: View {
    let session: ReviewSession
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let file = session.currentFile {
            VStack(alignment: .leading, spacing: 6) {
                // Fixed card width: only the path flexes (and truncates); the status and position columns keep
                // their room whether or not the file is viewed, so nothing below ever moves.
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(verbatim: file.path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        if file.viewed {
                            // The way back, away from the primary button: pressing "Mark viewed" again never unmarks.
                            Label { Text("Viewed", bundle: .app) } icon: { Image(systemName: "checkmark") }
                                .font(.system(size: 10.5)).foregroundStyle(.green).lineLimit(1).fixedSize()
                            Button { Task { await session.unmarkCurrent() } } label: { Text("Unmark", bundle: .app) }
                                .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.secondary).underline()
                                .lineLimit(1).fixedSize()
                                .disabled(session.busy)
                        }
                    }
                    .frame(width: 118, alignment: .trailing)
                    Text("\(file.index + 1) of \(file.total)", bundle: .app)
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1).frame(width: 56, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    ControlGroup {
                        Button { Task { await session.stepFile(-1) } } label: { Image(systemName: "chevron.up") }
                            .help(Text("Previous file", bundle: .app))
                        Button { Task { await session.stepFile(1) } } label: { Image(systemName: "chevron.down") }
                            .help(Text("Next file", bundle: .app))
                    }
                    .controlGroupStyle(.navigation)
                    .fixedSize()
                    .disabled(session.busy)
                    Button { Task { await session.markCurrentAndNext() } } label: {
                        Label { Text("Mark viewed", bundle: .app) } icon: { Image(systemName: "checkmark") }
                    }
                    .buttonStyle(.borderedProminent)
                    .help(Text("Mark this file as viewed and go to the next unviewed one (⌘↩)", bundle: .app))
                    .disabled(session.busy)
                    TestsComboButton(session: session) {
                        SettingsSelection.shared.tab = .review
                        SettingsOpener.activate()
                        openSettings()
                    }
                    .fixedSize()
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 440)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("File controls", bundle: .app))
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
