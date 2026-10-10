import AppKit
import SwiftUI

enum SettingsTab: String, Hashable, CaseIterable {
    case general
    case sections
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
            SectionsSettingsView(store: store)
                .tabItem { Label { Text("Sections", bundle: .app) } icon: { Image(systemName: "list.bullet.rectangle") } }
                .tag(SettingsTab.sections)
            FiltersSettingsView(store: store)
                .tabItem { Label { Text("Filters", bundle: .app) } icon: { Image(systemName: "line.3.horizontal.decrease.circle") } }
                .tag(SettingsTab.filters)
        }
        .frame(width: 520)
    }
}

struct GeneralSettingsView: View {
    @Bindable var store: PRStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            SwiftUI.Section {
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
            SwiftUI.Section {
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
            SwiftUI.Section {
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

struct SectionsSettingsView: View {
    @Bindable var store: PRStore
    private let columnWidth: CGFloat = 56

    var body: some View {
        Form {
            SwiftUI.Section {
                ForEach(Section.mineSections) { section in
                    SectionRow(section: section, store: store, columnWidth: columnWidth)
                }
            } header: {
                header(Text("My PRs", bundle: .app))
            }
            SwiftUI.Section {
                ForEach(Section.reviewSections) { section in
                    SectionRow(section: section, store: store, columnWidth: columnWidth)
                }
            } header: {
                header(Text("To review", bundle: .app))
            } footer: {
                Text("Sections you hide stay out of the list. The badge adds up the checked sections, after the owner filter.", bundle: .app)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }

    private func header(_ title: Text) -> some View {
        HStack {
            title
            Spacer()
            Text("Show", bundle: .app).frame(width: columnWidth)
            Text("Badge", bundle: .app).frame(width: columnWidth)
        }
        .font(.caption)
        .textCase(nil)
    }
}

private struct SectionRow: View {
    let section: Section
    @Bindable var store: PRStore
    let columnWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: section.title)
                Text(verbatim: section.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: membership(\.visibleSections)) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden().frame(width: columnWidth)
            Toggle(isOn: membership(\.badgeSections)) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden().frame(width: columnWidth)
        }
    }

    private func membership(_ keyPath: ReferenceWritableKeyPath<PRStore, Set<Section>>) -> Binding<Bool> {
        Binding(
            get: { store[keyPath: keyPath].contains(section) },
            set: { on in
                if on { store[keyPath: keyPath].insert(section) } else { store[keyPath: keyPath].remove(section) }
            }
        )
    }
}
