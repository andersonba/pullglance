import AppKit
import SwiftUI

struct FooterView: View {
    @Bindable var store: PRStore
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
                    open(tab: .logs)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text("Open log", bundle: .app))
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
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
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
        Button { PopoverDismissal.open(URL(string: "https://github.com/pulls")!) } label: {
            Text("Open my PRs on GitHub", bundle: .app)
        }
        Button { PopoverDismissal.open(URL(string: "https://github.com/pulls/review-requested")!) } label: {
            Text("Open review requests on GitHub", bundle: .app)
        }
        Divider()
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
        case .failed(let date):
            Text("Failed to refresh · data from \(lastGoodDate ?? date, format: .dateTime.hour().minute())", bundle: .app)
                .foregroundStyle(.yellow)
        }
    }

    private var helpText: Text {
        switch status {
        case .failed: Text(verbatim: reason ?? "")
        case .countdown: Text("Refresh now", bundle: .app)
        case .fetching, .refreshing, .updatedNow: Text(verbatim: "")
        }
    }
}
