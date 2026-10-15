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
    /// Keyboard triage: the focused row, if any. See `TriageFocus`.
    @State private var focus = TriageFocus()
    /// The row under the pointer: ↩ and ⌘C act on it without a focus, and space adopts it as the focus.
    @State private var hoveredRow: PullRequest.ID? = nil
    /// A row that just answered a key (copied its link, opened): a brief glow says which one.
    @State private var glowingRow: PullRequest.ID? = nil
    /// The row whose snooze length the ⇧S card is asking about, and the highlighted choice.
    @State private var snoozing: PullRequest? = nil
    @State private var snoozeChoice = 0
    @State private var glowTask: Task<Void, Never>? = nil
    /// The shortcuts card (⌘/ or the ⋯ menu).
    @State private var showingShortcuts = false
    private static let listSpace = "list"
    static let holdToReorder: Double = 0.5

    static let maxListHeight: CGFloat = 480

    enum Tab: Hashable { case mine, review }

    /// `openRow` starts with that row's swipe tiles revealed (the demo snapshot); nil in the app.
    init(store: PRStore, tab: Tab = .mine, openRow: PullRequest.ID? = nil) {
        self.store = store
        _tab = State(initialValue: tab)
        _openRow = State(initialValue: openRow)
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
                    .opacity(store.isApplyingSettingsChange || merging != nil || commenting != nil || showingShortcuts || snoozing != nil ? 0.45 : 1)
                    .allowsHitTesting(!store.isApplyingSettingsChange && merging == nil && commenting == nil && !showingShortcuts && snoozing == nil)
                if store.isApplyingSettingsChange {
                    ProgressView().progressViewStyle(.linear).controlSize(.mini).padding(.horizontal, 12)
                }
                if showingShortcuts {
                    // A click anywhere outside the card closes it.
                    Color.clear.contentShape(Rectangle()).onTapGesture { showingShortcuts = false }
                    ShortcutsCard { showingShortcuts = false }
                        .padding(.top, 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                if let pr = snoozing {
                    Color.clear.contentShape(Rectangle()).onTapGesture { snoozing = nil }
                    SnoozeCard(pr: pr, choice: $snoozeChoice, pick: { duration in
                        snoozing = nil
                        snooze(pr, for: duration)
                    }, close: { snoozing = nil })
                    .padding(.top, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
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
            .animation(.easeInOut(duration: 0.18), value: showingShortcuts)
            .animation(.easeInOut(duration: 0.18), value: snoozing?.id)
            .animation(.easeInOut(duration: 0.2), value: toast)

            if reordering {
                ReorderFooter { setReordering(false) }
            } else {
                // The regular footer always sets the height; the triage keys draw over it while a row is focused.
                ZStack {
                    FooterView(store: store, showShortcuts: { showingShortcuts = true }).opacity(focusedPR == nil ? 1 : 0)
                    if let focusedPR {
                        TriageFooter(isPinned: store.isPinned(focusedPR), isDormant: store.isDormant(focusedPR))
                    }
                }
            }
        }
        .frame(width: 380)
        .animation(.easeInOut(duration: 0.15), value: focus.id != nil)
        .onAppear {
            SettingsOpener.bringSettingsForwardIfOpen()
            store.startCIPolling()
            store.popoverDidOpen()
        }
        .onDisappear {
            store.stopCIPolling()
            store.popoverDidClose()
            mineFilter = nil
            reviewFilter = nil
            openRow = nil
            focus.clear()
            showingShortcuts = false
            setReordering(false)
        }
        .onChange(of: tab) { _, _ in
            openRow = nil
            focus.clear()
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
            ScrollViewReader { proxy in
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
                // The focused row stays in view as the keyboard walks the list.
                .onChange(of: focus.id) { _, id in
                    guard let id, let row = triageRows.first(where: { $0.pr.id == id }) else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("\(row.section.rawValue)/\(id)") }
                }
            }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top <= 0.5 } action: { _, top in listAtTop = top }
            // The pull is measured from the trackpad itself (no rubber band when the list fits); the list
            // slides down with it and the ring sits in the gap it opens.
            // The pull is measured from the trackpad itself (no rubber band when the list fits); the same AppKit
            // view takes the triage keys. It stays here, inside the list: at the popover's root it costs the glass.
            .background(ScrollWheelMonitor(handler: { event in handlePull(event) }, keyHandler: { event in handleKey(event) }))
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

    // MARK: keyboard triage

    private var triageRows: [(section: Section, pr: PullRequest)] {
        store.triageRows(for: tab == .mine ? .mine : .review, filter: tab == .mine ? mineFilter : reviewFilter)
    }

    private var focusedPR: PullRequest? {
        guard let id = focus.id else { return nil }
        return triageRows.first { $0.pr.id == id }?.pr
    }

    /// Plain keys while the popover is up and nothing else wants them: no field being edited, no modal,
    /// no reorder mode. ↓ starts; from then on the letters act on the focused row and Esc ends it.
    private func handleKey(_ event: NSEvent) -> Bool {
        // The Esc that closes the popover (see `PopoverDismissal`) is for the extra, not for the triage.
        if PopoverDismissal.isDismissal(event) { return false }
        guard !reordering, merging == nil, commenting == nil else { return false }
        if event.window?.firstResponder is NSTextView { return false }
        guard let key = TriageKey(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode, modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)) else { return false }
        // The card answers to its own two keys and swallows the rest while it is up.
        if key == .shortcuts { showingShortcuts.toggle(); return true }
        if showingShortcuts { if key == .escape { showingShortcuts = false }; return true }
        if let pr = snoozing {
            switch key {
            case .escape: snoozing = nil
            case .up: snoozeChoice = max(0, snoozeChoice - 1)
            case .down: snoozeChoice = min(SnoozeCard.choices.count - 1, snoozeChoice + 1)
            case .review, .space:
                snoozing = nil
                snooze(pr, for: SnoozeCard.choices[snoozeChoice])
            default: break
            }
            return true
        }
        guard store.hasAnyData, store.blockingError == nil else { return false }
        let rows = triageRows
        let ids = rows.map(\.pr.id)
        // Without a focus, ↩ and ⌘C act on the row under the pointer; space makes that row the focus.
        let hovered = focus.id == nil ? rows.first { $0.pr.id == hoveredRow } : nil
        switch key {
        case .down:
            openRow = nil
            focus.move(1, in: ids)
            return true
        case .space:
            openRow = nil
            if let hovered { focus.set(hovered.pr.id) } else if focus.id == nil { focus.move(1, in: ids) }
            return true
        case .up:
            guard focus.id != nil else { return false }
            focus.move(-1, in: ids)
            return true
        case .left, .right:
            // The other tab; a focus in flight lands on its first row.
            let other: Tab = tab == .mine ? .review : .mine
            let hadFocus = focus.id != nil
            withAnimation(.easeInOut(duration: 0.15)) { tab = other }
            if hadFocus {
                let first = store.triageRows(for: other == .mine ? .mine : .review, filter: other == .mine ? mineFilter : reviewFilter).first?.pr.id
                focus.set(first)
            }
            return true
        case .escape:
            guard focus.id != nil else { return false }
            focus.clear()
            return true
        case .shortcuts:
            return true   // handled above
        case .snoozeFor:
            // The row under the pointer, else the focused one; the card keeps the row's current length highlighted.
            guard let pr = hovered?.pr ?? focusedPR else { return false }
            openRow = nil
            // On a timed row, the shortest length that still covers what is left.
            let current = store.dormantMark(for: pr)?.nearestLength().flatMap { SnoozeDuration.allCases.firstIndex(of: $0) }
            snoozeChoice = current.map { $0 + 1 } ?? 0
            snoozing = pr
            return true
        case .pin, .snooze, .open, .review, .refresh, .comment, .merge, .copyLink:
            // The focused row, else the one under the pointer: the same keys, every one of them. Nothing here
            // is destructive without its own confirmation (Comment and Merge open cards; Pin and Snooze undo
            // with the same key). The focus bookkeeping only applies when a focus exists.
            let viaFocus = focus.id != nil
            guard let row = viaFocus ? rows.first(where: { $0.pr.id == focus.id }) : hovered else { return false }
            if !viaFocus { glow(row.pr.id) }
            switch key {
            case .pin, .snooze:
                // The row leaves its place: the one that slides in is next, so a run of P and S needs no arrows.
                let next = viaFocus ? TriageFocus.successor(of: row.pr.id, in: ids) : nil
                handle(key == .pin ? .pin : .snooze, for: row.pr)
                if viaFocus { focus.set(next) }
            case .open:
                focus.clear()
                handle(.open, for: row.pr)
            case .refresh:
                handle(.refresh, for: row.pr)
            case .comment:
                handle(.comment, for: row.pr)
            case .merge:
                // Only where the row's menu offers it; elsewhere the key does nothing, as the menu would.
                let origin = row.section.isFixed ? store.originSection(of: row.pr) : row.section
                let offered = allActions(for: origin, dormant: store.isDormant(row.pr), offersMerge: row.pr.offersAutoMerge, autoMergeOn: row.pr.autoMergeMethod != nil)
                if offered.contains(.merge) { handle(.merge, for: row.pr) }
            case .copyLink:
                if viaFocus { glow(row.pr.id) }
                handle(.copyLink, for: row.pr)
            default:
                focus.clear()
                openReview(row.pr, section: row.section)
            }
            return true
        }
    }

    /// A short accent glow on a row that just answered a key: on quickly, off slowly.
    private func glow(_ id: PullRequest.ID) {
        glowTask?.cancel()
        withAnimation(.easeOut(duration: 0.08)) { glowingRow = id }
        glowTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) { glowingRow = nil }
        }
    }

    /// Same destination as a click on the row.
    private func openReview(_ pr: PullRequest, section: Section) {
        if ReviewSettingsStore.shared.settings.windowEnabled, let review = ReviewWindowController.shared {
            // A review request: straight to the first file that still needs eyes.
            review.open(pr, landing: section.tab == .review ? .files : .conversation, firstUnviewed: section.tab == .review)
        } else {
            PopoverDismissal.open(pr.url)
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
            let wasArmed = pull.armed
            let took = pull.drag(by: event.scrollingDeltaY, horizontal: event.scrollingDeltaX, atTop: listAtTop)
            // The moment it arms, a tick under the fingers: from here, letting go refreshes.
            if pull.armed, !wasArmed { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
            return took
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

    /// A snooze with a length from the menu or the ⇧S card; nil is the plain one, until activity.
    private func snooze(_ pr: PullRequest, for duration: SnoozeDuration?) {
        openRow = nil
        let next = focus.id == pr.id ? TriageFocus.successor(of: pr.id, in: triageRows.map(\.pr.id)) : focus.id
        withAnimation(.easeInOut(duration: 0.3)) { store.snooze(pr, for: duration) }
        if focus.id != nil { focus.set(next) }
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
        case .pin:
            withAnimation(.easeInOut(duration: 0.3)) { store.isPinned(pr) ? store.unpin(pr) : store.pin(pr) }
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
        let pinnedRow = store.isPinned(pr)
        let reorderable = Self.isReorderable(section) && !dormant
        let lifted = rowDrag?.id == pr.id
        let focused = focus.id == pr.id
        let glowing = glowingRow == pr.id
        let woke = store.woke.contains(pr.id)
        return rowView(pr, section: section, showAuthor: showAuthor, teamLabel: teamLabel, dormant: dormant, pinned: pinnedRow, reorderable: reorderable, among: among)
            .onHover { inside in
                if inside { hoveredRow = pr.id } else if hoveredRow == pr.id { hoveredRow = nil }
            }
            // Back from a timed snooze: the whole row is tinted until the popover has been opened and closed.
            .background(glowing ? Color.accentColor.opacity(0.22) : focused ? Color.accentColor.opacity(0.08) : woke ? Color.orange.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2).padding(1.5).allowsHitTesting(false)
                }
            }
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

    /// The review sections' header menu: order and reordering in one place. In reorder mode the footer and
    /// the hover action take over, as in every other section.
    private func sortMenu(for section: Section) -> SectionHeader.SortMenu? {
        guard !reordering else { return nil }
        return .init(
            sort: store.sort(for: section),
            isManual: store.isManuallyOrdered(section),
            setSort: { sort in
                withAnimation(.easeInOut(duration: 0.25)) {
                    store.resetManualOrder(for: section)
                    store.setSort(sort, for: section)
                }
            },
            reorder: { setReordering(true) },
            clearManual: { withAnimation(.easeInOut(duration: 0.25)) { store.resetManualOrder(for: section) } }
        )
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

    private func rowView(_ pr: PullRequest, section: Section, showAuthor: Bool, teamLabel: String?, dormant: Bool, pinned: Bool, reorderable: Bool, among: [PullRequest]) -> some View {
        // Snoozed and pinned rows act as the row they would be in their own section.
        let actionSection = dormant || pinned ? store.originSection(of: pr) : section
        let actionState = store.actionState(for: pr)
        let running: Bool = { if case .running = actionState { return true }; return false }()
        let snoozeLength = dormant ? store.dormantMark(for: pr)?.nearestLength() : nil
        let isWoke = store.woke.contains(pr.id)
        return SwipeActionsRow(
            id: pr.id,
            actions: quickActions(for: actionSection, dormant: dormant),
            openRow: $openRow,
            isDormant: dormant,
            isPinned: pinned,
            isRunning: running,
            isLocked: reordering,
            onAction: { handle($0, for: pr) },
            menu: { PRRowMenu(section: actionSection, isDormant: dormant, isPinned: pinned, offersMerge: pr.offersAutoMerge, autoMergeOn: pr.autoMergeMethod != nil, actionState: actionState, snoozeLength: snoozeLength, onAction: { handle($0, for: pr) }, onSnoozeFor: { snooze(pr, for: $0) }) }
        ) {
            PRRow(
                pr: pr,
                section: actionSection,
                showAuthor: showAuthor,
                teamLabel: teamLabel,
                isDormant: dormant,
                snoozedUntil: dormant ? store.dormantMark(for: pr)?.until : nil,
                isWoke: isWoke,
                snoozeLength: snoozeLength,
                isPinned: pinned,
                actionState: actionState,
                onAction: { handle($0, for: pr) },
                onSnoozeFor: { snooze(pr, for: $0) },
                handlesTap: !reordering,
                showsGrip: reordering && reorderable,
                onAuthorTap: reordering ? nil : { withAnimation(.easeInOut(duration: 0.2)) { store.toggleQuickAuthor(pr.author) } },
                isAuthorFiltered: store.quickAuthorFilter == [pr.author],
                onRepoTap: reordering ? nil : { withAnimation(.easeInOut(duration: 0.2)) { store.toggleQuickRepo(pr.repo) } },
                isRepoFiltered: store.quickRepoFilter == [pr.repo]
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

    /// The tab's pinned PRs, always first, only when there are any. A quick filter keeps the rows whose
    /// origin matches: pinning never hides a row from its filter.
    @ViewBuilder private func pinnedSection(_ section: Section, _ prs: [PullRequest], filter: Section?, showAuthor: Bool) -> some View {
        let shown = prs.filter { filter == nil || store.originSection(of: $0) == filter }
        if !shown.isEmpty {
            SectionHeader(title: section.title, count: shown.count, hoverAction: headerAction(for: section))
            ForEach(shown) { pr in
                row(pr, section: section, showAuthor: showAuthor, among: shown)
                Divider()
            }
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
        if shown.allSatisfy({ groups[$0].isEmpty }), groups.snoozed.isEmpty, groups.pinned.isEmpty {
            EmptyStateView(kind: .allClear)
        } else {
            pinnedSection(.pinnedMine, groups.pinned, filter: mineFilter, showAuthor: false)
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
        pinnedSection(.pinnedReview, store.pinnedReviewList, filter: reviewFilter, showAuthor: true)
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
        SectionHeader(title: Section.needsYourReview.title, count: store.direct.total, hoverAction: reordering ? headerAction(for: .needsYourReview) : nil, sortMenu: sortMenu(for: .needsYourReview))
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
            detail: store.isViaTeamExpanded ? String(localized: "\(20) most recent", bundle: .app) : nil,
            sortMenu: store.isViaTeamExpanded ? sortMenu(for: .needsTeamsReview) : nil
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
