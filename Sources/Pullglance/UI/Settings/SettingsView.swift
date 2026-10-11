import AppKit
import SwiftUI

enum SettingsTab: String, Hashable, CaseIterable {
    case general
    case sections
    case filters
    case logs
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
            LogsSettingsView(store: store)
                .tabItem { Label { Text("Logs", bundle: .app) } icon: { Image(systemName: "doc.text") } }
                .tag(SettingsTab.logs)
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
    @State private var expanded: Set<String> = []
    @State private var hidingFor: String? = nil

    var body: some View {
        Form {
            SwiftUI.Section {
                ForEach(store.knownOwners) { owner in
                    OwnerRow(owner: owner, store: store, isExpanded: Binding(
                        get: { expanded.contains(owner.login) },
                        set: { on in if on { expanded.insert(owner.login) } else { expanded.remove(owner.login) } }
                    ))
                    if expanded.contains(owner.login) {
                        ownerDetails(owner)
                    }
                }
            } header: {
                Text("Show pull requests from", bundle: .app)
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Hidden owners and repositories are left out of both tabs and the badge. Every repository is shown unless you hide it; the list has the ones seen in your results and the ones you hid.", bundle: .app)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !store.hiddenOwners.isEmpty || !store.hiddenRepos.isEmpty {
                        Button {
                            store.hiddenOwners = []
                            store.hiddenRepos = []
                        } label: { Text("Show all", bundle: .app) }
                            .controlSize(.small)
                    }
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
        .sheet(item: Binding(
            get: { hidingFor.map(OwnerLogin.init) },
            set: { hidingFor = $0?.login }
        )) { owner in
            HideRepositoriesSheet(owner: owner.login, store: store)
        }
    }

    @ViewBuilder private func ownerDetails(_ owner: OwnerInfo) -> some View {
        if owner.repos.isEmpty {
            Text("No repositories seen in your results yet", bundle: .app)
                .font(.caption).foregroundStyle(.tertiary).padding(.leading, 44)
        }
        ForEach(owner.repos) { repo in
            RepoRow(repo: repo, store: store)
        }
        HStack {
            Spacer()
            Button { hidingFor = owner.login } label: { Text("Hide another repository…", bundle: .app) }
                .controlSize(.small)
        }
        .padding(.leading, 34)
    }
}

private struct OwnerLogin: Identifiable {
    let login: String
    var id: String { login }
}

private struct RepoRow: View {
    let repo: RepoInfo
    @Bindable var store: PRStore

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { !store.hiddenRepos.contains(repo.fullName) },
                set: { shown in
                    if shown { store.hiddenRepos.remove(repo.fullName) } else { store.hiddenRepos.insert(repo.fullName) }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            Text(verbatim: repo.name).font(.system(size: 12))
            Spacer()
            if repo.isHidden {
                Text(verbatim: "—").foregroundStyle(.tertiary)
            } else if repo.openCount > 0 {
                Text("\(repo.openCount) open", bundle: .app).foregroundStyle(.secondary).monospacedDigit().font(.caption)
            }
        }
        .padding(.leading, 34)
    }
}

/// Search the owner's repositories on GitHub to hide ones that have not shown up in your results yet.
private struct HideRepositoriesSheet: View {
    let owner: String
    @Bindable var store: PRStore
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var result: RepoSearchResult? = nil
    @State private var searching = false
    @State private var picked: Set<String> = []
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hide repositories from \(owner)", bundle: .app).font(.headline)
            TextField(text: $term, prompt: Text("Search repositories (2+ characters)", bundle: .app)) { EmptyView() }
                .textFieldStyle(.roundedBorder)
                .onChange(of: term) { _, new in schedule(new) }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let result {
                        ForEach(result.repos) { repo in
                            Toggle(isOn: Binding(
                                get: { picked.contains(repo.fullName) },
                                set: { on in if on { picked.insert(repo.fullName) } else { picked.remove(repo.fullName) } }
                            )) {
                                HStack {
                                    Text(verbatim: repo.name)
                                    if repo.isArchived { Text("archived", bundle: .app).font(.caption2).foregroundStyle(.tertiary) }
                                    Spacer()
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                        if result.repos.isEmpty {
                            Text("No match", bundle: .app).foregroundStyle(.secondary)
                        } else if result.total > result.repos.count {
                            Text("Showing \(result.repos.count) of \(result.total); refine the search", bundle: .app)
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    } else if searching {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Type to search the organization's repositories.", bundle: .app).foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("Cancel", bundle: .app) }
                    .keyboardShortcut(.cancelAction)
                Button {
                    store.hide(repos: picked)
                    dismiss()
                } label: {
                    Text("Hide \(picked.count)", bundle: .app)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(picked.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func schedule(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { result = nil; searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = await store.searchRepos(owner: owner, term: trimmed)
            guard !Task.isCancelled else { return }
            result = found ?? RepoSearchResult(total: 0, repos: [])
            searching = false
        }
    }
}

private struct OwnerRow: View {
    let owner: OwnerInfo
    @Bindable var store: PRStore
    @Binding var isExpanded: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button { isExpanded.toggle() } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
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
            AuthorAvatar(login: owner.login, url: URL(string: "https://github.com/\(owner.login).png"))
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
            if owner.hiddenRepoCount > 0 {
                Text("\(owner.hiddenRepoCount) of \(owner.repos.count) hidden", bundle: .app)
                    .font(.caption).foregroundStyle(.secondary)
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

    var body: some View {
        Form {
            SwiftUI.Section {
                ReorderSectionGroup(store: store, tab: .mine)
            } header: {
                ReorderSectionGroup.header(Text("My PRs", bundle: .app))
            }
            SwiftUI.Section {
                ReorderSectionGroup(store: store, tab: .review)
            } header: {
                ReorderSectionGroup.header(Text("To review", bundle: .app))
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Drag to reorder. Hidden sections stay out of the list; the badge adds up the checked sections, after the owner filter.", bundle: .app)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { store.resetSectionsToDefault() } label: { Text("Reset to default", bundle: .app) }
                        .controlSize(.small)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }
}

/// One tab's sections, reorderable by dragging the handle strip on the left.
///
/// Why not `List` + `onDrag`/`onDrop`: live reordering moved the very rows that acted as drop targets,
/// the drag state had no owner when a drag was cancelled, and the system drag competed with the checkboxes.
/// Here the `ForEach` keeps a fixed structural order and only the vertical offsets change; a local
/// `DragGesture` on an immobile strip drives a `@GestureState` session that SwiftUI resets when the gesture
/// ends or is cancelled; the store is written once, on release.
private struct ReorderSectionGroup: View {
    @Bindable var store: PRStore
    let tab: Section.Tab

    @GestureState private var session: ReorderSession<Section>? = nil

    static let rowHeight: CGFloat = 44
    static let handleWidth: CGFloat = 26
    static let columnWidth: CGFloat = 56

    private var stableItems: [Section] { Section.allCases.filter { $0.tab == tab } }
    private var currentOrder: [Section] { store.orderedSections(tab) }
    private var displayedOrder: [Section] {
        guard let session, session.original == currentOrder else { return currentOrder }
        return session.order
    }
    private var groupHeight: CGFloat { CGFloat(stableItems.count) * Self.rowHeight }

    static func header(_ title: Text) -> some View {
        HStack {
            title
            Spacer()
            Text("Show", bundle: .app).frame(width: columnWidth)
            Text("Badge", bundle: .app).frame(width: columnWidth)
        }
        .font(.caption)
        .textCase(nil)
    }

    var body: some View {
        let order = displayedOrder
        ZStack(alignment: .topLeading) {
            ForEach(stableItems) { section in
                let index = order.firstIndex(of: section) ?? 0
                row(section)
                    .frame(height: Self.rowHeight)
                    .overlay(alignment: .bottom) {
                        if index < order.count - 1 {
                            Divider().padding(.leading, Self.handleWidth)
                        }
                    }
                    .offset(y: CGFloat(index) * Self.rowHeight)
                    .zIndex(session?.original[session?.source ?? 0] == section ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: groupHeight, alignment: .topLeading)
        .overlay(alignment: .leading) {
            // The gesture receptor never moves with a row and ends before the texts and checkboxes.
            Color.clear
                .frame(width: Self.handleWidth, height: groupHeight)
                .contentShape(Rectangle())
                .highPriorityGesture(reorderGesture)
                .help(Text("Drag to reorder", bundle: .app))
                .accessibilityHidden(true)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
    }

    private func row(_ section: Section) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .frame(width: Self.handleWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: section.title).lineLimit(1)
                Text(verbatim: section.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle(isOn: membership(section, \.visibleSections)) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden().frame(width: Self.columnWidth)
            Toggle(isOn: membership(section, \.badgeSections)) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden().frame(width: Self.columnWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAction(named: Text("Move up")) { moveAccessibly(section, by: -1) }
        .accessibilityAction(named: Text("Move down")) { moveAccessibly(section, by: 1) }
    }

    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .updating($session) { value, state, transaction in
                transaction.animation = nil
                if state == nil {
                    let original = currentOrder
                    guard !original.isEmpty, value.startLocation.y >= 0, value.startLocation.y < groupHeight else { return }
                    let source = ReorderSession<Section>.slot(at: value.startLocation.y, rowHeight: Self.rowHeight, count: original.count)
                    state = ReorderSession(original: original, source: source, destination: source)
                }
                guard var active = state, active.original == currentOrder else { return }
                active.destination = ReorderSession<Section>.slot(at: value.location.y, rowHeight: Self.rowHeight, count: active.original.count)
                state = active
            }
            .onEnded { value in
                // `session` is already reset here, so recompute the pending move from the gesture value.
                let original = currentOrder
                guard !original.isEmpty, value.startLocation.y >= 0, value.startLocation.y < groupHeight else { return }
                let source = ReorderSession<Section>.slot(at: value.startLocation.y, rowHeight: Self.rowHeight, count: original.count)
                let destination = ReorderSession<Section>.slot(at: value.location.y, rowHeight: Self.rowHeight, count: original.count)
                let pending = ReorderSession(original: original, source: source, destination: destination)
                guard destination != source else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    store.moveSections(in: tab, from: IndexSet(integer: source), to: pending.insertionOffset)
                }
            }
    }

    private func moveAccessibly(_ section: Section, by delta: Int) {
        let order = currentOrder
        guard let source = order.firstIndex(of: section), order.indices.contains(source + delta) else { return }
        let pending = ReorderSession(original: order, source: source, destination: source + delta)
        store.moveSections(in: tab, from: IndexSet(integer: source), to: pending.insertionOffset)
    }

    private func membership(_ section: Section, _ keyPath: ReferenceWritableKeyPath<PRStore, Set<Section>>) -> Binding<Bool> {
        Binding(
            get: { store[keyPath: keyPath].contains(section) },
            set: { on in
                if on { store[keyPath: keyPath].insert(section) } else { store[keyPath: keyPath].remove(section) }
            }
        )
    }
}

struct LogsSettingsView: View {
    @Bindable var store: PRStore

    private static let timestamp: Date.FormatStyle = .dateTime.year().month(.twoDigits).day().hour().minute().second()

    var body: some View {
        VStack(spacing: 0) {
            if store.failureLog.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.system(size: 26)).foregroundStyle(.green)
                    Text("No failures so far", bundle: .app).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(store.failureLog) {
                    TableColumn(Text("Time", bundle: .app)) { entry in
                        Text(entry.date, format: .dateTime.hour().minute().second()).monospacedDigit()
                    }
                    .width(70)
                    TableColumn(Text("Type", bundle: .app)) { entry in Text(verbatim: entry.category) }
                        .width(90)
                    TableColumn(Text("Search", bundle: .app)) { entry in Text(verbatim: entry.search.rawValue) }
                        .width(50)
                    TableColumn(Text("Message", bundle: .app)) { entry in
                        Text(verbatim: entry.message).help(Text(verbatim: entry.message))
                    }
                }
                .font(.caption)
            }
            HStack {
                Text(verbatim: "\(store.failureLog.count) / \(PRStore.failureLogLimit)")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button { copyAll() } label: { Text("Copy all", bundle: .app) }
                    .disabled(store.failureLog.isEmpty)
                Button { store.clearFailureLog() } label: { Text("Clear", bundle: .app) }
                    .disabled(store.failureLog.isEmpty)
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(height: 360)
    }

    private func copyAll() {
        let lines = store.failureLog.map { entry in
            "\(entry.date.formatted(Self.timestamp))\t\(entry.search.rawValue)\t\(entry.category)\t\(entry.message)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
