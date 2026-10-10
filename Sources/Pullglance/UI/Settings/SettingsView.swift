import AppKit
import SwiftUI

enum SettingsTab: String, Hashable, CaseIterable {
    case general
    case filters
}

/// Which tab the Settings window should show; set before calling `openSettings`.
@Observable
@MainActor
final class SettingsSelection {
    static let shared = SettingsSelection()
    var tab: SettingsTab = .general
}

/// Brings the Settings window to the front from a menu bar app, which is otherwise never active.
@MainActor
enum SettingsOpener {
    static func activate() {
        PopoverDismissal.dismiss()
        NSApp.activate(ignoringOtherApps: true)
    }

    static let languagePane = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
}

struct SettingsView: View {
    @Bindable var store: PRStore
    @Bindable private var selection = SettingsSelection.shared

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettingsView(store: store)
                .tabItem { Label { Text("General", bundle: .app) } icon: { Image(systemName: "gearshape") } }
                .tag(SettingsTab.general)
            FiltersSettingsView(store: store)
                .tabItem { Label { Text("Filters", bundle: .app) } icon: { Image(systemName: "line.3.horizontal.decrease.circle") } }
                .tag(SettingsTab.filters)
        }
        .frame(width: 480)
    }
}

struct GeneralSettingsView: View {
    @Bindable var store: PRStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        LaunchAtLogin.set(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                )) {
                    Text("Launch at login", bundle: .app)
                }
                Picker(selection: Binding(
                    get: { Int(store.refreshInterval.components.seconds) },
                    set: { store.refreshInterval = .seconds($0) }
                )) {
                    ForEach([60, 120, 300], id: \.self) { seconds in
                        Text("\(seconds / 60) min", bundle: .app).tag(seconds)
                    }
                } label: {
                    Text("Refresh every", bundle: .app)
                }
            }
            Section {
                LabeledContent {
                    HStack {
                        Text("Follows the system", bundle: .app).foregroundStyle(.secondary)
                        Button { NSWorkspace.shared.open(SettingsOpener.languagePane) } label: {
                            Text("Change…", bundle: .app)
                        }
                        .controlSize(.small)
                    }
                } label: {
                    Text("Language", bundle: .app)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }
}

struct FiltersSettingsView: View {
    @Bindable var store: PRStore

    var body: some View {
        Form {
            Section {
                ForEach(store.knownOwners) { owner in
                    OwnerRow(owner: owner, store: store)
                }
            } header: {
                Text("Show pull requests from", bundle: .app)
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Hidden owners are left out of both tabs and the badge. New owners show up checked.", bundle: .app)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !store.hiddenOwners.isEmpty {
                        Button { store.hiddenOwners = [] } label: { Text("Show all", bundle: .app) }
                            .controlSize(.small)
                    }
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }
}

private struct OwnerRow: View {
    let owner: OwnerInfo
    @Bindable var store: PRStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { !store.hiddenOwners.contains(owner.login) },
                set: { shown in
                    if shown { store.hiddenOwners.remove(owner.login) } else { store.hiddenOwners.insert(owner.login) }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            AuthorInitial(login: owner.login)
            Text(verbatim: owner.login)
            if owner.isViewer {
                Text("(you)", bundle: .app).foregroundStyle(.secondary)
            }
            Spacer()
            if hovering {
                Button {
                    store.hiddenOwners = Set(store.knownOwners.map(\.login)).subtracting([owner.login])
                } label: {
                    Text("Only", bundle: .app)
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }
            if let count = owner.openCount {
                Text("\(count) open", bundle: .app).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(verbatim: "—").foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
