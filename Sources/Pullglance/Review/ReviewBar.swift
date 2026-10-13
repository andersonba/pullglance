import AppKit
import SwiftUI

/// What the bar asks the window to do; everything that needs the window (modals, the web view, the
/// pasteboard) lives there, the rest goes straight to the session.
struct ReviewBarActions {
    var approve: () -> Void = {}
    var comment: () -> Void = {}
    var merge: () -> Void = {}
    var snooze: () -> Void = {}
    var openInBrowser: () -> Void = {}
    var copyLink: () -> Void = {}
    var hide: () -> Void = {}
    var reviewFiles: () -> Void = {}
}

/// One line under the address bar: context on the left, progress and actions on the right.
struct ReviewBar: View {
    let session: ReviewSession
    let actions: ReviewBarActions
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private var leading: some View {
        switch session.page {
        case .pullRequest(let repo, let number, _):
            Text(verbatim: "#\(number) \(session.pullRequest?.title ?? "")").font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            if let pr = session.pullRequest {
                Text(verbatim: pr.author).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) { ForEach(pills(for: pr).prefix(3), id: \.self) { PillView(pill: $0) } }
            } else {
                Text(verbatim: repo).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        case .compare:
            Text(verbatim: session.page.compareTitle ?? "").font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
            if let c = session.pageCounts { Text("\(c.total) files", bundle: .app).font(.system(size: 11.5)).foregroundStyle(.secondary) }
        case .other:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        progress
        if case .pullRequest(_, _, let tab) = session.page, tab != .files {
            Button { actions.reviewFiles() } label: { Text("Review files →", bundle: .app) }.buttonStyle(.borderedProminent).controlSize(.small)
        } else {
            markButton
        }
        Button { Task { await session.scroll(.next) } } label: { Text("Next ↓", bundle: .app) }.controlSize(.small).disabled(session.busy)
        moreMenu
    }

    @ViewBuilder private var progress: some View {
        switch session.notice {
        case .loading:
            ProgressView().controlSize(.small)
        case .marked(let count, let failed, let canUndo):
            HStack(spacing: 6) {
                Text(failed == 0 ? String(localized: "\(count) marked", bundle: .app) : String(localized: "\(count) marked · \(failed) failed", bundle: .app))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if canUndo { Button { Task { await session.undo() } } label: { Text("Undo", bundle: .app) }.controlSize(.small) }
            }
        case .undone(let count):
            Text("\(count) unmarked", bundle: .app).font(.system(size: 11)).foregroundStyle(.secondary)
        case .error(let message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.triangle.fill") }.font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
        case nil:
            if let counts = session.fileCounts {
                counter(viewed: counts.viewed, total: counts.total)
            } else if case .compare = session.page, let c = session.pageCounts {
                counter(viewed: c.viewed, total: c.total)
            } else if session.page.showsBar {
                Text("Loading files…", bundle: .app).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private func counter(viewed: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(viewed)/\(total)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            ProgressView(value: total == 0 ? 0 : Double(viewed) / Double(total)).progressViewStyle(.linear).frame(width: 70).controlSize(.mini)
        }
    }

    private var markButton: some View {
        HStack(spacing: 0) {
            Button { Task { await session.mark() } } label: { Text("Mark tests · \(session.matchCount)", bundle: .app) }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(session.busy || session.pageCounts == nil)
            Menu {
                presetItems
            } label: { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18)
                .disabled(session.busy)
        }
    }

    @ViewBuilder private var presetItems: some View {
        let counts = session.pageCounts?.perRule ?? [:]
        Picker(selection: Binding(get: { session.presetChoice }, set: { session.choose($0) })) {
            Text("Auto (enabled presets)", bundle: .app).tag(ReviewPresetChoice.auto)
            ForEach(ReviewPresets.all) { preset in
                Text(verbatim: "\(preset.group) · \(preset.label) · \(counts[preset.id] ?? 0)").tag(ReviewPresetChoice.preset(preset.id))
            }
            Text(verbatim: String(localized: "Custom globs", bundle: .app) + " · \(counts["custom"] ?? 0)").tag(ReviewPresetChoice.custom)
        } label: { Text("Preset", bundle: .app) }
        .pickerStyle(.inline)
        Divider()
        Button { editRules() } label: { Text("Edit rules…", bundle: .app) }
    }

    /// Settings › Review. The scene's own `openSettings` first; a hosted view outside a SwiftUI scene may not
    /// reach it, so if no Settings window shows up the legacy responder action is the fallback.
    private func editRules() {
        SettingsSelection.shared.tab = .review
        SettingsOpener.activate()
        openSettings()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if SettingsOpener.settingsWindow?.isVisible == true {
                AppLog.shared.info("review bar: Settings opened via openSettings")
            } else {
                AppLog.shared.info("review bar: openSettings showed no window; falling back to showSettingsWindow:")
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    private var canUndo: Bool {
        if case .marked(_, _, true) = session.notice { return true }
        return false
    }

    private var isDormant: Bool {
        guard let pr = session.pullRequest else { return false }
        return session.store.isDormant(pr)
    }

    private var moreMenu: some View {
        Menu {
            Button { Task { await session.undo() } } label: { Text("Undo last marking", bundle: .app) }.disabled(!canUndo)
            Button { Task { await session.unmarkAll() } } label: { Text("Unmark all", bundle: .app) }
            if case .pullRequest = session.page {
                Divider()
                Button { actions.approve() } label: { Text("Approve…", bundle: .app) }.keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(session.pullRequest == nil)
                Button { actions.comment() } label: { Text("Comment…", bundle: .app) }.keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(session.pullRequest == nil)
                Button { actions.merge() } label: { Text("Merge…", bundle: .app) }.keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(session.pullRequest == nil)
                Button { actions.snooze() } label: { Text(isDormant ? "Wake" : "Snooze", bundle: .app) }
                    .disabled(session.pullRequest == nil)
            }
            Divider()
            Button { Task { await session.refresh() } } label: { Text("Refresh review state", bundle: .app) }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button { actions.openInBrowser() } label: { Text("Open in Browser", bundle: .app) }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button { actions.copyLink() } label: { Text("Copy link", bundle: .app) }
            Divider()
            Button { actions.hide() } label: { Text("Hide review bar", bundle: .app) }.keyboardShortcut("b", modifiers: [.command, .option])
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
    }
}
