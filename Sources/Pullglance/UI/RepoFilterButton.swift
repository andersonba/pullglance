import SwiftUI

/// Quiet icon next to the tabs that opens a small popover to narrow both tabs to a few repositories or a
/// few authors ("what did alice ask me to review"). Session-only: see `PRStore.quickRepoFilter` and
/// `quickAuthorFilter`; the two stack.
struct RepoFilterButton: View {
    @Bindable var store: PRStore
    @State private var isPresented = false
    @State private var search = ""
    @State private var kind: Kind = .repositories

    enum Kind: Hashable { case repositories, authors }

    private var isActive: Bool { store.hasQuickFilter }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Filter by repository or author", bundle: .app))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            panel
        }
    }

    private var term: String { search.trimmingCharacters(in: .whitespaces).lowercased() }
    private var filteredRepos: [RepoInfo] { store.availableRepos.filter { term.isEmpty || $0.fullName.lowercased().contains(term) } }
    private var filteredAuthors: [AuthorInfo] { store.availableAuthors.filter { term.isEmpty || $0.login.lowercased().contains(term) } }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The app's own segmented control (the merge modal's): it fills the width, which the system picker will not.
            SegmentedControl(
                selection: $kind,
                segments: [
                    .init(value: .repositories, title: Text("Repositories", bundle: .app), enabled: true),
                    .init(value: .authors, title: Text("Authors", bundle: .app), enabled: true),
                ],
                fontSize: 12
            )
            .onChange(of: kind) { _, _ in search = "" }
            TextField(text: $search, prompt: Text(kind == .repositories ? "Search repositories" : "Search authors", bundle: .app)) { EmptyView() }
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    switch kind {
                    case .repositories:
                        ForEach(filteredRepos) { repo in
                            row(on: Binding(
                                get: { store.quickRepoFilter.contains(repo.fullName) },
                                set: { on in if on { store.quickRepoFilter.insert(repo.fullName) } else { store.quickRepoFilter.remove(repo.fullName) } }
                            ), count: repo.openCount) {
                                Text(verbatim: repo.fullName).lineLimit(1)
                            }
                        }
                        if filteredRepos.isEmpty {
                            Text("No repositories match", bundle: .app).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                    case .authors:
                        ForEach(filteredAuthors) { author in
                            row(on: Binding(
                                get: { store.quickAuthorFilter.contains(author.login) },
                                set: { on in if on { store.quickAuthorFilter.insert(author.login) } else { store.quickAuthorFilter.remove(author.login) } }
                            ), count: author.count) {
                                HStack(spacing: 6) {
                                    AuthorAvatar(login: author.login, url: author.avatarURL).frame(width: 14, height: 14)
                                    Text(verbatim: author.login).lineLimit(1)
                                }
                            }
                        }
                        if filteredAuthors.isEmpty {
                            Text("No authors match", bundle: .app).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                    }
                }
                .font(.system(size: 12))
            }
            .frame(maxHeight: 220)
            HStack {
                Text("Applies to both tabs. Not saved.", bundle: .app).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button { store.quickRepoFilter = []; store.quickAuthorFilter = [] } label: { Text("Clear", bundle: .app) }
                    .controlSize(.small)
                    .disabled(!isActive)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func row(on: Binding<Bool>, count: Int, @ViewBuilder label: () -> some View) -> some View {
        Toggle(isOn: on) {
            HStack {
                label()
                Spacer()
                Text(verbatim: "\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
    }
}
