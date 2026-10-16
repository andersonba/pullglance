import AppKit
import SwiftUI

struct FooterView: View {
    @Bindable var store: PRStore
    /// Opens the shortcuts card over the popover (the card is the popover's; the menu only asks for it).
    var showShortcuts: () -> Void = {}
    /// A newer release, when there is one: first item of the menu, and a dot on its button.
    var updates: UpdateChecker? = nil
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatusButton(
                    status: footerStatus(phase: store.phase, hasData: store.hasAnyData, nextRefresh: store.nextRefreshAt, now: context.date),
                    lastGoodDate: store.lastGoodDate,
                    reason: store.lastError.map(reasonText),
                    refresh: { Task { await store.refresh() } }
                )
            }
            Spacer(minLength: 0)
            if store.lastError != nil {
                Button {
                    open(tab: .advanced)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text("Open diagnostics", bundle: .app))
            }
            if !store.quickRepoFilter.isEmpty {
                Button {
                    store.quickRepoFilter = []
                } label: {
                    Label {
                        Text(verbatim: quickFilterLabel)
                    } icon: {
                        Image(systemName: "folder.fill")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(Text("Clear repository filter", bundle: .app))
            }
            if !store.quickAuthorFilter.isEmpty {
                Button {
                    store.quickAuthorFilter = []
                } label: {
                    HStack(spacing: 4) {
                        if let first = store.availableAuthors.first(where: { store.quickAuthorFilter.contains($0.login) }) {
                            AuthorAvatar(login: first.login, url: first.avatarURL).frame(width: 12, height: 12)
                        }
                        Text(verbatim: authorFilterLabel)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(Text("Clear author filter", bundle: .app))
            }
            if !store.hiddenOwners.isEmpty {
                Button {
                    open(tab: .filters)
                } label: {
                    Label {
                        Text("\(store.hiddenOwners.count) hidden", bundle: .app)
                    } icon: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(Text("Filters", bundle: .app))
            }
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .overlay(alignment: .topTrailing) {
                        if updates?.available != nil {
                            Circle().fill(.orange).frame(width: 6, height: 6).offset(x: 2, y: -2)
                                .accessibilityLabel(Text("Update available", bundle: .app))
                        }
                    }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    /// One author: the login; several: the first and how many more.
    private var authorFilterLabel: String {
        let logins = store.quickAuthorFilter.sorted()
        guard let first = logins.first else { return "" }
        return logins.count == 1 ? first : "\(first) +\(logins.count - 1)"
    }

    /// One repo: its short name; several: a count.
    private var quickFilterLabel: String {
        if store.quickRepoFilter.count == 1, let only = store.quickRepoFilter.first {
            return only.split(separator: "/").last.map(String.init) ?? only
        }
        return String(localized: "\(store.quickRepoFilter.count) repos", bundle: .app)
    }

    private func reasonText(_ kind: ErrorKind) -> String {
        switch kind {
        case .ghNotFound: String(localized: "gh CLI not found", bundle: .app)
        case .notAuthenticated: String(localized: "gh is not logged in to github.com", bundle: .app)
        case .other(let message): message
        }
    }

    private func open(tab: SettingsTab) {
        SettingsSelection.shared.tab = tab
        SettingsOpener.activate()
        openSettings()
    }

    @ViewBuilder private var menuItems: some View {
        if let updates, let release = updates.available {
            Button { PopoverDismissal.open(release.url) } label: {
                Text("Update to \(release.version)…", bundle: .app)
            }
            Button { updates.skip() } label: { Text("Skip this version", bundle: .app) }
            Divider()
        }
        Button { PopoverDismissal.open(URL(string: "https://github.com/pulls")!) } label: {
            Text("Open my PRs on GitHub", bundle: .app)
        }
        Button { PopoverDismissal.open(URL(string: "https://github.com/pulls/review-requested")!) } label: {
            Text("Open review requests on GitHub", bundle: .app)
        }
        Divider()
        Button(action: showShortcuts) {
            Text("Keyboard Shortcuts…", bundle: .app)
        }
        .keyboardShortcut("/", modifiers: .command)
        Button { open(tab: .general) } label: {
            Text("Settings…", bundle: .app)
        }
        .keyboardShortcut(",", modifiers: .command)
        Divider()
        Text("Version \(AppInfo.version)", bundle: .app)
        Button { NSApplication.shared.terminate(nil) } label: {
            Text("Quit", bundle: .app)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

/// The status text doubles as the refresh control: a quiet pill appears on hover when a refresh is allowed.
private struct StatusButton: View {
    let status: FooterStatus
    let lastGoodDate: Date?
    let reason: String?
    let refresh: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: refresh) {
            HStack(spacing: 5) {
                indicator
                label
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(hovering && status.allowsManualRefresh ? 0.08 : 0), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!status.allowsManualRefresh)
        .keyboardShortcut("r", modifiers: .command)
        .onHover { over in
            hovering = over
            if over, status.allowsManualRefresh { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(helpText)
    }

    @ViewBuilder private var indicator: some View {
        switch status {
        case .fetching, .refreshing:
            ProgressView().controlSize(.mini).frame(width: 7, height: 7)
        case .updatedNow, .countdown:
            Circle().fill(.green).frame(width: 7, height: 7)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
    }

    @ViewBuilder private var label: some View {
        switch status {
        case .fetching:
            Text("Fetching from GitHub…", bundle: .app).foregroundStyle(.secondary)
        case .refreshing:
            Text("Refreshing…", bundle: .app).foregroundStyle(.secondary)
        case .updatedNow:
            Text("Updated now", bundle: .app).foregroundStyle(.secondary)
        case .countdown:
            Text("Refresh in \(status.countdownText)", bundle: .app).foregroundStyle(.secondary).monospacedDigit()
        case .failed:
            Text("Failed to refresh", bundle: .app).foregroundStyle(.yellow)
        }
    }

    /// On failure: how old the data on screen is, then the reason.
    private var helpText: Text {
        switch status {
        case .failed(let date):
            let age = Text("Showing data from \(lastGoodDate ?? date, format: .relative(presentation: .named))", bundle: .app)
            return reason.map { age + Text(verbatim: "\n") + Text(verbatim: $0) } ?? age
        case .countdown: return Text("Refresh now", bundle: .app)
        case .fetching, .refreshing, .updatedNow: return Text(verbatim: "")
        }
    }
}
