import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var store: PRStore
    @State private var tab: Tab = .mine
    @State private var listHeight: CGFloat = 0
    /// Quick filter per tab. Not persisted: the popover always opens on "All".
    @State private var mineFilter: Section? = nil
    @State private var reviewFilter: Section? = nil

    static let maxListHeight: CGFloat = 480

    enum Tab: Hashable { case mine, review }

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                (Text("My PRs", bundle: .app) + Text(verbatim: "  \(store.mineTabCount)")).tag(Tab.mine)
                (Text("To review", bundle: .app) + Text(verbatim: "  \(store.reviewTabCount)")).tag(Tab.review)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            if store.hasAnyData, store.blockingError == nil {
                let items = quickFilterItems(
                    sections: store.orderedSections(tab == .mine ? .mine : .review),
                    visible: store.visibleSections,
                    mine: store.mineGroups,
                    directTotal: store.direct.total,
                    teamTotal: store.viaTeamTotal
                )
                if !items.isEmpty {
                    QuickFilterBar(items: items, selection: tab == .mine ? $mineFilter : $reviewFilter)
                        .onChange(of: reviewFilter) { _, new in
                            if new == .needsTeamsReview { store.isViaTeamExpanded = true }
                        }
                }
            }

            content

            FooterView(store: store)
        }
        .frame(width: 380)
        .onDisappear {
            mineFilter = nil
            reviewFilter = nil
        }
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
            .transaction { $0.animation = nil }
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
        let groups = store.mineGroups
        let shown = store.orderedSections(.mine).filter { store.visibleSections.contains($0) && (mineFilter == nil || mineFilter == $0) }
        if shown.allSatisfy({ groups[$0].isEmpty }) {
            EmptyStateView(kind: .allClear)
        } else {
            ForEach(shown) { section in
                mineSection(section, groups[section])
            }
        }
    }

    @ViewBuilder private func mineSection(_ section: Section, _ prs: [PullRequest]) -> some View {
        if !prs.isEmpty {
            SectionHeader(title: section.title, count: prs.count)
            ForEach(prs) { pr in
                PRRow(pr: pr, leading: .ci)
                Divider().padding(.leading, 12)
            }
        }
    }

    @ViewBuilder private var reviewList: some View {
        ForEach(store.orderedSections(.review)) { section in
            if store.visibleSections.contains(section), reviewFilter == nil || reviewFilter == section {
                switch section {
                case .needsYourReview: directSection
                case .needsTeamsReview: teamSection
                default: EmptyView()
                }
            }
        }
        if store.visibleSections.isDisjoint(with: Section.reviewSections) {
            EmptyStateView(kind: .allClear)
        }
    }

    @ViewBuilder private var directSection: some View {
        SectionHeader(title: Section.needsYourReview.title, count: store.direct.total)
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
    }

    @ViewBuilder private var teamSection: some View {
        SectionHeader(
            title: Section.needsTeamsReview.title,
            count: store.viaTeamTotal,
            expanded: $store.isViaTeamExpanded,
            detail: store.isViaTeamExpanded ? String(localized: "\(20) most recent", bundle: .app) : nil
        )
        if store.isViaTeamExpanded || reviewFilter == .needsTeamsReview {
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
