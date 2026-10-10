import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var store: PRStore
    @State private var tab: Tab = .mine
    @State private var listHeight: CGFloat = 0

    static let maxListHeight: CGFloat = 480

    enum Tab: Hashable { case mine, review }

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                (Text("My PRs", bundle: .app) + Text(verbatim: "  \(store.mine.total)")).tag(Tab.mine)
                (Text("To review", bundle: .app) + Text(verbatim: "  \(store.direct.total)")).tag(Tab.review)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            content

            FooterView(store: store)
        }
        .frame(width: 380)
    }

    @ViewBuilder private var content: some View {
        if let kind = store.blockingError {
            EmptyStateView(kind: emptyKind(for: kind), retry: { Task { await store.refresh() } })
        } else if !store.hasAnyData {
            SkeletonView()
        } else {
            // MenuBarExtra's window sizes itself to the content's ideal size, and a ScrollView has none
            // of its own. Measure the list and give the ScrollView that height, capped.
            ScrollView {
                VStack(spacing: 0) {
                    switch tab {
                    case .mine: mineList
                    case .review: reviewList
                    }
                }
                .padding(.bottom, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollIndicators(.never)
            .background(OverlayScrollerStyle())
            .frame(height: min(max(listHeight, 1), Self.maxListHeight))
        }
    }

    private func emptyKind(for error: ErrorKind) -> EmptyStateView.Kind {
        switch error {
        case .ghNotFound: .ghNotFound
        case .notAuthenticated: .notAuthenticated
        case .other(let message): .network(message)
        }
    }

    @ViewBuilder private var mineList: some View {
        if store.mine.value.isEmpty {
            EmptyStateView(kind: .allClear)
        } else {
            let groups = store.mineGroups
            section(String(localized: "Needs you", bundle: .app), groups.needsYou)
            section(String(localized: "Waiting on others", bundle: .app), groups.waitingOnOthers)
            section(String(localized: "Drafts", bundle: .app), groups.drafts)
        }
    }

    @ViewBuilder private func section(_ title: String, _ prs: [PullRequest]) -> some View {
        if !prs.isEmpty {
            SectionHeader(title: title, count: prs.count)
            ForEach(prs) { pr in
                PRRow(pr: pr, leading: .ci)
                Divider().padding(.leading, 12)
            }
        }
    }

    @ViewBuilder private var reviewList: some View {
        SectionHeader(title: String(localized: "Requested from you", bundle: .app), count: store.direct.total)
        if store.directList.isEmpty {
            Text("Nothing pending in reviews.", bundle: .app)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        ForEach(store.directList) { pr in
            PRRow(pr: pr, leading: .author, showAuthor: true)
            Divider().padding(.leading, 12)
        }

        SectionHeader(
            title: String(localized: "Via team", bundle: .app),
            count: store.viaTeamTotal,
            expanded: $store.isViaTeamExpanded,
            detail: store.isViaTeamExpanded ? String(localized: "\(20) most recent", bundle: .app) : nil
        )
        if store.isViaTeamExpanded {
            if store.viaTeam == nil, store.viaTeamError != nil {
                HStack(spacing: 8) {
                    Text("Couldn't reach GitHub", bundle: .app).foregroundStyle(.secondary)
                    Button { Task { await store.refreshViaTeam() } } label: { Text("Try again", bundle: .app) }
                        .controlSize(.small)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else if store.viaTeam == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding()
            } else {
                ForEach(store.viaTeamList) { pr in
                    PRRow(pr: pr, leading: .author, showAuthor: true, teamLabel: pr.requestedTeams.first)
                    Divider().padding(.leading, 12)
                }
                Button {
                    PopoverDismissal.open(URL(string: "https://github.com/pulls/review-requested")!)
                } label: {
                    Text("Open all on GitHub", bundle: .app).font(.caption)
                }
                .buttonStyle(.link)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}
