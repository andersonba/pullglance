import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var store: PRStore
    @State private var tab: Tab = .mine
    @State private var pull = PullToRefreshState()
    @State private var listAtTop = true
    @State private var wheelSettle: Task<Void, Never>?
    @State private var lastWheelAt = Date.distantPast
    @State private var wheelProbeStart: Date?
    @State private var topGlow = false
    @State private var glowFade: Task<Void, Never>?
    @State private var listHeight: CGFloat = 0
    /// Quick filter per tab. Not persisted: the popover always opens on "All".
    @State private var mineFilter: Section? = nil
    @State private var reviewFilter: Section? = nil
    @State private var merging: PullRequest? = nil
    @State private var commenting: PullRequest? = nil
    @State private var toast: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil
    /// The row whose swipe actions are showing, if any. One at a time, like Mail.
    @State private var openRow: PullRequest.ID? = nil
    /// Reorder mode: rows only drag within their section; no swipe, no click. See `ReorderRow`.
    @State private var reordering = false
    /// The drag in flight inside reorder mode.
    @State private var rowDrag: RowDrag? = nil
    /// Row frames in the list's coordinate space, refreshed only while nothing is being dragged.
    @State private var rowFrames: [PullRequest.ID: CGRect] = [:]
    private static let listSpace = "list"
    static let holdToReorder: Double = 0.5

    static let maxListHeight: CGFloat = 480

    enum Tab: Hashable { case mine, review }

    init(store: PRStore, tab: Tab = .mine) {
        self.store = store
        _tab = State(initialValue: tab)
    }

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
                    teamTotal: store.viaTeamTotal,
                    snoozedReview: store.snoozedReviewList.count
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
                        Task {
                            if case .success(let note?) = await store.merge(pr, method: options.method, deleteBranch: options.deleteBranch) {
                                show(toast: note)
                            }
                        }
                    }
                    .padding(.top, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                if let pr = commenting {
                    CommentView(pr: pr, store: store) { result in
                        commenting = nil
                        if case .success = result { show(toast: String(localized: "Comment posted on #\(pr.number)", bundle: .app)) }
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

            if reordering {
                ReorderFooter { setReordering(false) }
            } else {
                FooterView(store: store)
            }
        }
        .frame(width: 380)
        .onAppear {
            SettingsOpener.bringSettingsForwardIfOpen()
            store.startCIPolling()
        }
        .onDisappear {
            store.stopCIPolling()
            mineFilter = nil
            reviewFilter = nil
            openRow = nil
            setReordering(false)
        }
        .onChange(of: tab) { _, _ in
            openRow = nil
            setReordering(false)
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
                // Lazy: only the rows on screen are built. With 50+ rows, building them all on a tab switch
                // (and walking them all for accessibility focus) blocked the main thread for ~400 ms.
                LazyVStack(spacing: 0) {
                    switch tab {
                    case .mine: mineList
                    case .review: reviewList
                    }
                }
                .padding(.bottom, 6)
                .offset(y: pull.stretch)
                .animation(pull.dragging ? nil : .spring(duration: 0.3), value: pull.stretch)
                .coordinateSpace(name: Self.listSpace)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top <= 0.5 } action: { _, top in listAtTop = top }
            // The pull is measured from the trackpad itself (no rubber band when the list fits); the list
            // slides down with it and the ring sits in the gap it opens.
            .background(ScrollWheelMonitor { event in handlePull(event) })
            .overlay(alignment: .top) {
                PullRing(state: pull, refreshing: store.phase == .loading && pull.stretch > 0)
                    .frame(height: max(pull.stretch, 1))
                    .opacity(pull.stretch > 4 ? 1 : 0)
            }
            .overlay(alignment: .top) { TopEdgeGlow(visible: topGlow) }
            // Scrolling the list puts a revealed row away.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating { openRow = nil }
            }
            .background(OverlayScrollerStyle())
            .frame(height: min(max(listHeight, 1), Self.maxListHeight))
            // Only the measured height must not animate (it caused a visible jump); row changes may.
            .animation(nil, value: listHeight)
        }
    }

    /// Trackpad phases: `began` opens a gesture, `changed` steps feed the pull while the list is at its top
    /// (those steps are swallowed so the list does not scroll under the pull), `ended` lifts. Momentum
    /// events are never a pull.
    private func handlePull(_ event: NSEvent) -> Bool {
        guard event.momentumPhase.isEmpty, !reordering else { return false }
        // A mouse wheel has no phases: each notch at the top is a step of the pull, and half a second of
        // silence after the last notch is the lift.
        if event.phase.isEmpty {
            let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.5 : event.scrollingDeltaY * 10
            let now = Date()
            defer { lastWheelAt = now }
            if !pull.dragging {
                // A fresh movement at the top, not the tail of a spin that just arrived there.
                guard listAtTop, step > 0, now.timeIntervalSince(lastWheelAt) > 0.3 || wheelProbeStart != nil else { return false }
                // The first stretch of notches only answers "you are at the top" with a glow; a flick ends
                // inside it. Keeping the wheel going past the probe starts the pull.
                let start = wheelProbeStart ?? now
                wheelProbeStart = start
                topGlow = true
                glowFade?.cancel()
                glowFade = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    topGlow = false
                    wheelProbeStart = nil
                }
                guard now.timeIntervalSince(start) >= PullToRefreshState.wheelProbeDuration else { return false }
                wheelProbeStart = nil
                topGlow = false
                pull.began(atTop: true)
            }
            let took = pull.drag(by: step, atTop: listAtTop)
            wheelSettle?.cancel()
            wheelSettle = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                if pull.ended(), manualRefreshAllowed { await store.refresh() }
            }
            return took
        }
        switch event.phase {
        case .began:
            pull.began(atTop: listAtTop)
            return false
        case .changed:
            return pull.drag(by: event.scrollingDeltaY, atTop: listAtTop)
        case .ended, .cancelled:
            if pull.ended(), manualRefreshAllowed { Task { await store.refresh() } }
            return false
        default:
            return false
        }
    }

    /// Same rule as the footer's status button: not while refreshing, not right after "Updated now".
    private var manualRefreshAllowed: Bool {
        footerStatus(phase: store.phase, hasData: store.hasAnyData, nextRefresh: store.nextRefreshAt, now: Date()).allowsManualRefresh
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
        // Any action, from a tile, the "more" tile or the context menu, puts a revealed row away.
        openRow = nil
        switch action {
        case .merge: merging = pr
        case .comment: commenting = pr
        case .approve: break // The review window owns approving; rows never offer it.
        case .snooze:
            // The row travels between its section and Snoozed; let it fade and slide rather than jump.
            withAnimation(.easeInOut(duration: 0.3)) { store.isDormant(pr) ? store.wake(pr) : store.snooze(pr) }
        case .open: PopoverDismissal.open(pr.url)
        case .copyLink:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
            show(toast: String(localized: "Link copied", bundle: .app))
        case .refresh:
            Task { _ = await store.refreshOne(pr) }
        case .disableAutoMerge:
            Task { _ = await store.disableAutoMerge(pr) }
        }
    }

    /// Sections whose rows the user can order by hand. Snoozed and the team sample are read-only.
    private static func isReorderable(_ section: Section) -> Bool {
        !section.isSnoozed && section != .needsTeamsReview
    }

    private func setReordering(_ on: Bool) {
        guard reordering != on else { return }
        openRow = nil
        rowDrag = nil
        withAnimation(.easeInOut(duration: 0.18)) { reordering = on }
        store.holdsAutoRefresh = on
    }

    /// The same row in both modes, so entering reorder mode changes nothing but the grip and the footer.
    /// In reorder mode the layout keeps the original order during a drag: the lifted row follows the
    /// pointer, rows it has passed shift by its height, release saves. Frames are read only between
    /// drags, so a moving row never feeds back into its own position.
    private func row(_ pr: PullRequest, section: Section, showAuthor: Bool = false, teamLabel: String? = nil, among: [PullRequest] = []) -> some View {
        let dormant = store.isDormant(pr)
        let reorderable = Self.isReorderable(section) && !dormant
        let lifted = rowDrag?.id == pr.id
        return rowView(pr, section: section, showAuthor: showAuthor, teamLabel: teamLabel, dormant: dormant, reorderable: reorderable, among: among)
            .opacity(reordering && !reorderable ? 0.4 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.listSpace)) } action: { if rowDrag == nil { rowFrames[pr.id] = $0 } }
            .background(lifted ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8))
            .offset(y: dragOffset(for: pr.id))
            .shadow(color: .black.opacity(lifted ? 0.25 : 0), radius: 10, y: 4)
            .zIndex(lifted ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: rowDrag?.order)
            .transition(.asymmetric(insertion: .opacity, removal: .collapse))
            // The lazy stack identifies children by id across the sections' ForEach blocks: a PR that moves
            // section would keep its old view (stale pills). Scope the identity to the section.
            .id("\(section.rawValue)/\(pr.id)")
    }

    private func dragOffset(for id: PullRequest.ID) -> CGFloat {
        guard let rowDrag else { return 0 }
        if rowDrag.id == id { return rowDrag.translation }
        guard let mine = rowDrag.original.firstIndex(of: id),
              let from = rowDrag.original.firstIndex(of: rowDrag.id),
              let to = rowDrag.order.firstIndex(of: rowDrag.id)
        else { return 0 }
        if from < to, mine > from, mine <= to { return -rowDrag.liftedHeight }
        if from > to, mine >= to, mine < from { return rowDrag.liftedHeight }
        return 0
    }

    private func reorderDrag(for pr: PullRequest, in section: Section, among prs: [PullRequest]) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if rowDrag == nil {
                    rowDrag = RowDrag(id: pr.id, section: section, original: prs.map(\.id), frames: rowFrames)
                }
                guard var session = rowDrag, session.id == pr.id else { return }
                session.translation = value.translation.height
                let center = session.startMinY + session.translation + session.liftedHeight / 2
                let others = session.original.filter { $0 != pr.id }
                let slot = others.filter { (session.frames[$0]?.midY ?? .infinity) < center }.count
                var order = others
                order.insert(pr.id, at: min(slot, others.count))
                session.order = order
                rowDrag = session
            }
            .onEnded { _ in
                guard let session = rowDrag else { return }
                if session.order != session.original {
                    store.setManualOrder(session.order, for: session.section)
                }
                withAnimation(.easeOut(duration: 0.15)) { rowDrag = nil }
            }
    }

    /// Header action: "Reorder" to enter the mode; inside it, "Sort by update" on hand-ordered sections.
    private func headerAction(for section: Section) -> SectionHeader.HoverAction? {
        guard Self.isReorderable(section) else { return nil }
        if reordering {
            guard store.isManuallyOrdered(section) else { return nil }
            return .init(title: String(localized: "Sort by update", bundle: .app), alwaysVisible: true) {
                withAnimation(.easeInOut(duration: 0.25)) { store.resetManualOrder(for: section) }
            }
        }
        return .init(title: String(localized: "Reorder", bundle: .app)) { setReordering(true) }
    }

    private func rowView(_ pr: PullRequest, section: Section, showAuthor: Bool, teamLabel: String?, dormant: Bool, reorderable: Bool, among: [PullRequest]) -> some View {
        let actionSection = dormant ? store.originSection(of: pr) : section
        let actionState = store.actionState(for: pr)
        let running: Bool = { if case .running = actionState { return true }; return false }()
        return SwipeActionsRow(
            id: pr.id,
            actions: quickActions(for: actionSection, dormant: dormant),
            openRow: $openRow,
            isDormant: dormant,
            isRunning: running,
            isLocked: reordering,
            onAction: { handle($0, for: pr) },
            menu: { PRRowMenu(section: actionSection, isDormant: dormant, offersMerge: pr.offersAutoMerge, autoMergeOn: pr.autoMergeMethod != nil, actionState: actionState, onAction: { handle($0, for: pr) }) }
        ) {
            PRRow(
                pr: pr,
                section: actionSection,
                showAuthor: showAuthor,
                teamLabel: teamLabel,
                isDormant: dormant,
                originSection: dormant ? store.originSection(of: pr) : nil,
                actionState: actionState,
                onAction: { handle($0, for: pr) },
                handlesTap: !reordering,
                showsGrip: reordering && reorderable
            )
            // In reorder mode nothing inside the row is clickable; the whole row is the drag handle.
            .allowsHitTesting(!reordering)
            .contentShape(Rectangle())
            .gesture(reorderDrag(for: pr, in: section, among: among), including: reordering && reorderable ? .all : .none)
            // Hold a moment to enter reorder mode. Simultaneous, so a quick click still opens the PR; once
            // the mode is on the tap is off, so the release does not open anything.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Self.holdToReorder, maximumDistance: 6).onEnded { _ in setReordering(true) },
                including: reorderable && !reordering ? .all : .none
            )
        }
    }

    /// The tab's snoozed PRs, always last, only when there are any and the section is visible.
    @ViewBuilder private func snoozedSection(_ section: Section, _ prs: [PullRequest], showAuthor: Bool) -> some View {
        if store.visibleSections.contains(section), !prs.isEmpty {
            SectionHeader(title: section.title, count: prs.count)
            ForEach(prs) { pr in
                row(pr, section: section, showAuthor: showAuthor)
                Divider()
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
            if mineFilter == nil || mineFilter == .snoozedMine {
                snoozedSection(.snoozedMine, groups.snoozed, showAuthor: false)
            }
        }
    }

    @ViewBuilder private func mineSection(_ section: Section, _ prs: [PullRequest]) -> some View {
        if !prs.isEmpty {
            SectionHeader(title: section.title, count: prs.count, hoverAction: headerAction(for: section))
            ForEach(prs) { pr in
                row(pr, section: section, among: prs)
                Divider()
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
        if reviewFilter == nil || reviewFilter == .snoozedReview {
            snoozedSection(.snoozedReview, store.snoozedReviewList, showAuthor: true)
        }
    }

    @ViewBuilder private var directSection: some View {
        let direct = store.directList
        SectionHeader(title: Section.needsYourReview.title, count: store.direct.total, hoverAction: headerAction(for: .needsYourReview))
        if direct.isEmpty {
            Text("Nothing pending in reviews.", bundle: .app)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        ForEach(direct) { pr in
            row(pr, section: .needsYourReview, showAuthor: true, among: direct)
            Divider()
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
                    Divider()
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

/// A leaving row folds up toward its top edge while the rows below slide over it, so it reads as the
/// list closing the gap rather than a card vanishing in place.
private struct CollapseModifier: ViewModifier, @preconcurrency Animatable {
    var progress: CGFloat
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: max(progress, 0.001), anchor: .top)
            .opacity(progress)
    }
}

extension AnyTransition {
    static var collapse: AnyTransition { .modifier(active: CollapseModifier(progress: 0), identity: CollapseModifier(progress: 1)) }
}

/// One drag inside reorder mode. `frames` is the layout at lift time; it holds because rows only move by
/// transforms until release.
private struct RowDrag: Equatable {
    let id: PullRequest.ID
    let section: Section
    let original: [PullRequest.ID]
    var order: [PullRequest.ID]
    let frames: [PullRequest.ID: CGRect]
    var translation: CGFloat = 0

    var startMinY: CGFloat { frames[id]?.minY ?? 0 }
    var liftedHeight: CGFloat { frames[id]?.height ?? 0 }

    init(id: PullRequest.ID, section: Section, original: [PullRequest.ID], frames: [PullRequest.ID: CGRect]) {
        self.id = id
        self.section = section
        self.original = original
        self.order = original
        self.frames = frames
    }
}
