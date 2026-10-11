import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var store: PRStore
    @State private var tab: Tab = .mine
    @State private var listHeight: CGFloat = 0
    /// Quick filter per tab. Not persisted: the popover always opens on "All".
    @State private var mineFilter: Section? = nil
    @State private var reviewFilter: Section? = nil
    @State private var merging: PullRequest? = nil
    @State private var commenting: PullRequest? = nil
    @State private var toast: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    static let maxListHeight: CGFloat = 480

    enum Tab: Hashable { case mine, review }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TabPicker(selection: $tab, mineCount: store.mineTabCount, reviewCount: store.reviewTabCount)
                if store.hasAnyData, store.blockingError == nil {
                    RepoFilterButton(store: store)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

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

            ZStack(alignment: .top) {
                content
                    .opacity(store.isApplyingSettingsChange || merging != nil || commenting != nil ? 0.45 : 1)
                    .allowsHitTesting(!store.isApplyingSettingsChange && merging == nil && commenting == nil)
                if store.isApplyingSettingsChange {
                    ProgressView().progressViewStyle(.linear).controlSize(.mini).padding(.horizontal, 12)
                }
                if let pr = merging {
                    MergeConfirmView(pr: pr, store: store, previousFailure: previousFailure(of: pr)) { options in
                        merging = nil
                        store.clearActionState(for: pr)
                        guard let options else { return }
                        Task { _ = await store.merge(pr, method: options.method, deleteBranch: options.deleteBranch) }
                    }
                    .padding(.top, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                if let pr = commenting {
                    CommentView(pr: pr, store: store) { result in
                        commenting = nil
                        if result == .success { show(toast: String(localized: "Comment posted on #\(pr.number)", bundle: .app)) }
                    }
                    .padding(.top, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(text: toast).padding(.bottom, 8).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.isApplyingSettingsChange)
            .animation(.easeInOut(duration: 0.18), value: merging?.id)
            .animation(.easeInOut(duration: 0.18), value: commenting?.id)
            .animation(.easeInOut(duration: 0.2), value: toast)

            FooterView(store: store)
        }
        .frame(width: 380)
        .onAppear { SettingsOpener.bringSettingsForwardIfOpen() }
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
            // Only the measured height must not animate (it caused a visible jump); row changes may.
            .animation(nil, value: listHeight)
        }
    }

    private func show(toast text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    private func previousFailure(of pr: PullRequest) -> String? {
        if case .failed(.merge, let message) = store.actionState(for: pr) { return message }
        return nil
    }

    private func handle(_ action: PRAction, for pr: PullRequest) {
        switch action {
        case .merge: merging = pr
        case .comment: commenting = pr
        case .snooze: store.isDormant(pr) ? store.wake(pr) : store.snooze(pr)
        case .open: PopoverDismissal.open(pr.url)
        case .copyLink:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
            show(toast: String(localized: "Link copied", bundle: .app))
        case .refresh:
            store.clearActionState(for: pr)
            Task { await store.refresh() }
        }
    }

    private func row(_ pr: PullRequest, section: Section, showAuthor: Bool = false, teamLabel: String? = nil) -> some View {
        let dormant = store.isDormant(pr)
        return rowView(pr, section: section, showAuthor: showAuthor, teamLabel: teamLabel, dormant: dormant)
            .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .leading))))
    }

    private func rowView(_ pr: PullRequest, section: Section, showAuthor: Bool, teamLabel: String?, dormant: Bool) -> some View {
        PRRow(
            pr: pr,
            section: dormant ? store.originSection(of: pr) : section,
            showAuthor: showAuthor,
            teamLabel: teamLabel,
            isDormant: dormant,
            originSection: dormant ? store.originSection(of: pr) : nil,
            actionState: store.actionState(for: pr),
            onAction: { handle($0, for: pr) }
        )
    }

    /// The tab's snoozed PRs, always last, only when there are any and the section is visible.
    @ViewBuilder private func snoozedSection(_ section: Section, _ prs: [PullRequest], showAuthor: Bool) -> some View {
        if store.visibleSections.contains(section), !prs.isEmpty {
            SectionHeader(title: section.title, count: prs.count)
            ForEach(prs) { pr in
                row(pr, section: section, showAuthor: showAuthor)
                Divider().padding(.leading, 12)
            }
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
        if shown.allSatisfy({ groups[$0].isEmpty }), groups.snoozed.isEmpty {
            EmptyStateView(kind: .allClear)
        } else {
            ForEach(shown) { section in
                mineSection(section, groups[section])
            }
            if mineFilter == nil {
                snoozedSection(.snoozedMine, groups.snoozed, showAuthor: false)
            }
        }
    }

    @ViewBuilder private func mineSection(_ section: Section, _ prs: [PullRequest]) -> some View {
        if !prs.isEmpty {
            SectionHeader(title: section.title, count: prs.count)
            ForEach(prs) { pr in
                row(pr, section: section)
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
        if reviewFilter == nil {
            snoozedSection(.snoozedReview, store.snoozedReviewList, showAuthor: true)
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
            row(pr, section: .needsYourReview, showAuthor: true)
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
                    row(pr, section: .needsTeamsReview, showAuthor: true, teamLabel: pr.requestedTeams.first)
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
