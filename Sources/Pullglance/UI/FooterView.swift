import AppKit
import SwiftUI

struct FooterView: View {
    @Bindable var store: PRStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                status
            }
            .font(.caption)
            .lineLimit(1)
            Spacer(minLength: 0)
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
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help(Text("Refresh", bundle: .app))
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

    @ViewBuilder private var status: some View {
        switch store.phase {
        case .idle:
            Text("Fetching from GitHub…", bundle: .app).foregroundStyle(.secondary)
        case .loading where !store.hasAnyData:
            Text("Fetching from GitHub…", bundle: .app).foregroundStyle(.secondary)
        case .loading:
            Text("Refreshing…", bundle: .app).foregroundStyle(.secondary)
        case .ok(let date):
            Label {
                Text("Updated \(date, format: .relative(presentation: .named))", bundle: .app)
            } icon: {
                Circle().fill(.green).frame(width: 7, height: 7)
            }
            .foregroundStyle(.secondary)
        case .error(_, let date):
            let good = store.lastGoodDate ?? date
            Label {
                Text("Failed to refresh \(date, format: .relative(presentation: .named)) · data from \(good, format: .dateTime.hour().minute())", bundle: .app)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.yellow)
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
