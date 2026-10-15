import AppKit
import SwiftUI

/// What the bar asks the window to do; everything that needs the window (modals, the web view, the
/// pasteboard) lives there, the rest goes straight to the session.
struct ReviewBarActions {
    var approve: () -> Void = {}
    var comment: () -> Void = {}
    var merge: () -> Void = {}
    var markReady: () -> Void = {}
    var snooze: () -> Void = {}
    var openInBrowser: () -> Void = {}
    var copyLink: () -> Void = {}
    var hide: () -> Void = {}
    var reviewFiles: () -> Void = {}
}

/// One line under the address bar: context on the left, progress and actions on the right.
struct ReviewBar: View {
    @Environment(\.openSettings) private var openSettings
    let session: ReviewSession
    let actions: ReviewBarActions

    var body: some View {
        // Left: the pull request and its progress, read as one line. Right: its actions. A centered middle
        // zone left a small element floating in wide windows.
        HStack(spacing: 12) {
            HStack(spacing: 8) { leading; progress }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { trailing }.fixedSize()
        }
        .controlSize(.small)
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

    /// Right zone: on pages with files, the tests combo (marking in bulk is decided here, next to the
    /// progress); then one primary action for the pull request's state, with the rest in its attached
    /// menu. Navigating and marking one file live in the small pill over the page.
    @ViewBuilder private var trailing: some View {
        if session.currentFile != nil {
            TestsComboButton(session: session) {
                SettingsSelection.shared.tab = .review
                SettingsOpener.activate()
                openSettings()
            }
            .fixedSize()
        }
        if case .pullRequest(_, _, let tab) = session.page {
            if tab != .files {
                Button { actions.reviewFiles() } label: {
                    Label { Text("Review files", bundle: .app) } icon: { Image(systemName: "arrow.right") }.labelStyle(.titleAndIcon)
                }
            }
            PRActionsComboButton(session: session, actions: actions, primary: showsMerge ? .merge : isOwn ? .comment : .approve, canReview: !isOwn, offersMarkReady: isOwn && session.pullRequest?.isDraft == true).fixedSize()
        } else {
            moreMenu
        }
    }

    /// Same rule as the popover: Merge is offered where merging is the point.
    private var showsMerge: Bool {
        guard let pr = session.pullRequest else { return false }
        return mineSection(for: pr) == .readyToMerge
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
        case .info(let message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "text.bubble") }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
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
        HStack(spacing: 8) {
            ProgressView(value: total == 0 ? 0 : Double(viewed) / Double(total)).progressViewStyle(.linear).frame(width: 64).controlSize(.mini)
            Text("\(viewed) of \(total) viewed", bundle: .app).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
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

    /// The viewer's own pull request: GitHub refuses an approval or a change request from its author.
    private var isOwn: Bool {
        guard let pr = session.pullRequest, let viewer = session.store.viewerLogin else { return false }
        return pr.author == viewer
    }

    private var moreMenu: some View {
        Menu {
            Button { Task { await session.undo() } } label: { Text("Undo last marking", bundle: .app) }.disabled(!canUndo)
            Button { Task { await session.unmarkAll() } } label: { Text("Unmark all", bundle: .app) }
            if case .pullRequest = session.page {
                Divider()
                if !showsMerge {
                    Button { actions.merge() } label: { Text("Merge…", bundle: .app) }.keyboardShortcut("m", modifiers: [.command, .shift])
                        .disabled(session.pullRequest == nil)
                }
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
