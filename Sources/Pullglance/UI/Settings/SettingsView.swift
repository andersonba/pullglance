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

    /// The SwiftUI Settings scene's window, if it exists.
    static var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.frameAutosaveName == "com_apple_SwiftUI_Settings_window" }
    }

    /// Clicking the menu bar icon while Settings is open (likely buried) brings the window back.
    static func bringSettingsForwardIfOpen() {
        guard let window = settingsWindow, window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
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
    @State private var picking: RepoPick? = nil

    var body: some View {
        Form {
            SwiftUI.Section {
                ForEach(store.knownOwners) { owner in
                    OwnerRow(owner: owner, store: store) { mode in picking = RepoPick(owner: owner.login, mode: mode) }
                }
            } header: {
                Text("Show pull requests from", bundle: .app)
            } footer: {
                if store.isApplyingSettingsChange {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Applying… the lists and the badge update when the search returns.", bundle: .app)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.bottom, 6)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Unchecked owners are left out entirely. Per owner, \"All except…\" hides the listed repositories and new ones show up; \"Only…\" shows just the listed repositories and new ones stay out.", bundle: .app)
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
        .sheet(item: $picking) { pick in
            RepoPickerSheet(owner: pick.owner, mode: pick.mode, store: store)
        }
    }
}

private struct RepoPick: Identifiable {
    let owner: String
    let mode: RepoMode
    var id: String { owner }
}

private struct OwnerRow: View {
    let owner: OwnerInfo
    @Bindable var store: PRStore
    let pick: (RepoMode) -> Void

    private var shown: Bool { !store.hiddenOwners.contains(owner.login) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { shown },
                    set: { on in if on { store.hiddenOwners.remove(owner.login) } else { store.hiddenOwners.insert(owner.login) } }
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
                if let count = owner.openCount {
                    Text("\(count) open", bundle: .app)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                } else {
                    Text("hidden", bundle: .app).foregroundStyle(.tertiary).font(.caption)
                }
                if shown {
                    ruleMenu
                }
            }
            if shown, !owner.rule.repos.isEmpty {
                chips
            }
        }
    }

    /// Quiet by default ("All repositories"); only a configured rule stands out.
    private var ruleMenu: some View {
        let configured = !owner.rule.repos.isEmpty
        return Menu {
            Button {
                store.setRule(.none, for: owner.login)
            } label: { Text("All repositories", bundle: .app) }
            Button { pick(.allExcept) } label: { Text("All except…", bundle: .app) }
            Button { pick(.only) } label: { Text("Only…", bundle: .app) }
        } label: {
            HStack(spacing: 3) {
                Text(verbatim: ruleSummary)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(configured ? Color.primary : Color.secondary.opacity(0.7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(minWidth: 110, alignment: .trailing)
    }

    private var ruleSummary: String {
        switch (owner.rule.mode, owner.rule.repos.count) {
        case (.allExcept, 0): String(localized: "All repositories", bundle: .app)
        case (.allExcept, let n): String(localized: "All except \(n)", bundle: .app)
        case (.only, let n): String(localized: "Only \(n)", bundle: .app)
        }
    }

    /// The chosen repositories as removable chips, plus the add button. Shown only when there is something to show.
    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(owner.rule.repos.sorted(), id: \.self) { repo in
                HStack(spacing: 4) {
                    Text(verbatim: repo.split(separator: "/").last.map(String.init) ?? repo)
                        .strikethrough(owner.rule.mode == .allExcept, color: .red)
                    Button { store.removeRepo(repo, from: owner.login) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    (owner.rule.mode == .only ? Color.accentColor : Color.red).opacity(0.12),
                    in: Capsule()
                )
            }
            Button { pick(owner.rule.mode) } label: {
                Image(systemName: "plus.circle").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text(owner.rule.mode == .only ? "Choose repositories to show" : "Choose repositories to hide", bundle: .app))
        }
        .padding(.leading, 28)
    }
}

/// Choose repositories for an owner's rule: the ones in your results first, then a search of the organization.
private struct RepoPickerSheet: View {
    let owner: String
    let mode: RepoMode
    @Bindable var store: PRStore
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var term = ""
    @State private var remote: RepoSearchResult? = nil
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>? = nil

    private var recent: [RepoInfo] { store.recentRepos(for: owner) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .only ? "Only these repositories of \(owner)" : "Hide these repositories of \(owner)", bundle: .app)
                .font(.headline)
            TextField(text: $term, prompt: Text("Search \(owner) repositories…", bundle: .app)) { EmptyView() }
                .textFieldStyle(.roundedBorder)
                .onChange(of: term) { _, new in schedule(new) }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if term.trimmingCharacters(in: .whitespaces).count < 2 {
                        if recent.isEmpty {
                            Text("No repositories of this owner in your results yet. Search to find one.", bundle: .app)
                                .foregroundStyle(.tertiary)
                        } else {
                            header(Text("Recent in your results", bundle: .app))
                            ForEach(recent) { repo in
                                row(repo.fullName, detail: String(localized: "\(repo.openCount) open", bundle: .app))
                            }
                        }
                        let chosenElsewhere = picked.subtracting(recent.map(\.fullName)).sorted()
                        if !chosenElsewhere.isEmpty {
                            header(Text("Chosen", bundle: .app))
                            ForEach(chosenElsewhere, id: \.self) { row($0, detail: nil) }
                        }
                    } else if let remote {
                        header(Text("From GitHub · \(remote.repos.count) of \(remote.total)", bundle: .app))
                        ForEach(remote.repos) { repo in
                            row(repo.fullName, detail: repo.isArchived ? String(localized: "archived", bundle: .app) : nil)
                        }
                        if remote.repos.isEmpty { Text("No match", bundle: .app).foregroundStyle(.secondary) }
                    } else if searching {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 240)
            HStack {
                Text("\(picked.count) chosen", bundle: .app).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { dismiss() } label: { Text("Cancel", bundle: .app) }
                    .keyboardShortcut(.cancelAction)
                Button {
                    store.setRule(RepoRule(mode: mode, repos: picked), for: owner)
                    dismiss()
                } label: { Text("Done", bundle: .app) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            // Keep the current choice when re-opening in the same mode; start fresh when switching modes.
            let current = store.repoRule(for: owner)
            picked = current.mode == mode ? current.repos : []
        }
    }

    private func header(_ text: Text) -> some View {
        text.font(.caption).textCase(.uppercase).foregroundStyle(.tertiary).padding(.top, 4)
    }

    private func row(_ fullName: String, detail: String?) -> some View {
        Toggle(isOn: Binding(
            get: { picked.contains(fullName) },
            set: { on in if on { picked.insert(fullName) } else { picked.remove(fullName) } }
        )) {
            HStack {
                Text(verbatim: fullName.split(separator: "/").last.map(String.init) ?? fullName)
                Spacer()
                if let detail { Text(verbatim: detail).foregroundStyle(.secondary).font(.caption) }
            }
        }
        .toggleStyle(.checkbox)
    }

    private func schedule(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { remote = nil; searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = await store.searchRepos(owner: owner, term: trimmed)
            guard !Task.isCancelled else { return }
            remote = found ?? RepoSearchResult(total: 0, repos: [])
            searching = false
        }
    }
}

struct SectionsSettingsView: View {
    @Bindable var store: PRStore

    var body: some View {
        Form {
            SwiftUI.Section {
                ReorderSectionGroup(store: store, tab: .mine)
                SnoozedSectionRow(section: .snoozedMine, store: store)
            } header: {
                ReorderSectionGroup.header(Text("My PRs", bundle: .app))
            }
            SwiftUI.Section {
                ReorderSectionGroup(store: store, tab: .review)
                SnoozedSectionRow(section: .snoozedReview, store: store)
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

/// The tab's "Snoozed" section: always last, can be hidden, never counted.
private struct SnoozedSectionRow: View {
    let section: Section
    @Bindable var store: PRStore

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "moon.zzz").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: ReorderSectionGroup.handleWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: section.title).lineLimit(1)
                Text(verbatim: section.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(
                get: { store.visibleSections.contains(section) },
                set: { on in if on { store.visibleSections.insert(section) } else { store.visibleSections.remove(section) } }
            )) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden().frame(width: ReorderSectionGroup.columnWidth)
            Text(verbatim: "—").foregroundStyle(.tertiary).frame(width: ReorderSectionGroup.columnWidth)
        }
        .frame(height: ReorderSectionGroup.rowHeight)
        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
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
