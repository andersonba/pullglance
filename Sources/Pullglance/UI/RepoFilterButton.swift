import SwiftUI

/// Quiet icon next to the tabs that opens a small popover to narrow both tabs to a few repositories.
/// Session-only: see `PRStore.quickRepoFilter`.
struct RepoFilterButton: View {
    @Bindable var store: PRStore
    @State private var isPresented = false
    @State private var search = ""

    private var isActive: Bool { !store.quickRepoFilter.isEmpty }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: isActive ? "folder.fill" : "folder")
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Filter by repository", bundle: .app))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            panel
        }
    }

    private var filtered: [RepoInfo] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.availableRepos.filter { term.isEmpty || $0.fullName.lowercased().contains(term) }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(text: $search, prompt: Text("Search repositories", bundle: .app)) { EmptyView() }
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { repo in
                        Toggle(isOn: Binding(
                            get: { store.quickRepoFilter.contains(repo.fullName) },
                            set: { on in
                                if on { store.quickRepoFilter.insert(repo.fullName) } else { store.quickRepoFilter.remove(repo.fullName) }
                            }
                        )) {
                            HStack {
                                Text(verbatim: repo.fullName).lineLimit(1)
                                Spacer()
                                Text(verbatim: "\(repo.openCount)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    if filtered.isEmpty {
                        Text("No repositories match", bundle: .app).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                }
                .font(.system(size: 12))
            }
            .frame(maxHeight: 220)
            HStack {
                Text("Applies to both tabs. Not saved.", bundle: .app).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button { store.quickRepoFilter = [] } label: { Text("Clear", bundle: .app) }
                    .controlSize(.small)
                    .disabled(!isActive)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
