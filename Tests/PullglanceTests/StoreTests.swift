import Foundation
import Testing
@testable import Pullglance

@MainActor
@Suite struct StoreTests {
    private func makeStore(_ gh: FakeGH, now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) }) -> PRStore {
        PRStore(client: gh, defaults: testDefaults(), now: now)
    }

    private func happyGH() async throws -> FakeGH {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        await gh.set(.success(try fixture("search-team.json")), for: SearchQuery.viaTeam)
        return gh
    }

    @Test func startsIdleWithNoBadge() async throws {
        let store = makeStore(try await happyGH())
        #expect(store.phase == .idle)
        #expect(store.badgeCount == nil)
        #expect(store.hasAnyData == false)
    }

    @Test func successfulRefreshFillsSnapshotsAndBadge() async throws {
        let gh = try await happyGH()
        let store = makeStore(gh)
        await store.refresh()
        #expect(store.phase == .ok(Date(timeIntervalSince1970: 1_000)))
        #expect(store.mine.value.count == 5)
        #expect(store.direct.value.count == 3)
        #expect(store.direct.total == 27)          // Review Focus 4
        #expect(store.badgeCount == 6)
        #expect(store.viewerLogin == "octocat")
        #expect(store.mineGroups.needsAction.map(\.number) == [101])
        #expect(store.directList.map(\.number) == [201, 202, 203])
        #expect(await gh.callCount(for: SearchQuery.viaTeam) == 0)
    }

    /// Merge state is expensive for GitHub to compute; only your own PRs need it (Needs action, Ready to merge).
    @Test func onlyTheMineSearchAsksForMergeState() async throws {
        let gh = try await happyGH()
        let store = makeStore(gh)
        store.isViaTeamExpanded = true
        await store.refresh()
        #expect(await gh.mergeFlags[SearchQuery.mine] == true)
        #expect(await gh.mergeFlags[SearchQuery.direct] == false)
        #expect(await gh.mergeFlags[SearchQuery.viaTeam] == false)
    }

    @Test func failureKeepsPreviousSnapshotAndBadge() async throws {
        let gh = try await happyGH()
        let store = makeStore(gh)
        await store.refresh()
        await gh.set(.failure("network down"), for: SearchQuery.direct)
        await store.refresh()
        #expect(store.phase == .error(.other("network down"), Date(timeIntervalSince1970: 1_000)))
        #expect(store.direct.value.count == 3)
        #expect(store.badgeCount == 6)
        #expect(store.blockingError == nil)
    }

    @Test func authErrorIsBlockingEvenWithOldData() async throws {
        let gh = try await happyGH()
        let store = makeStore(gh)
        await store.refresh()
        await gh.set(.notAuthenticated, for: SearchQuery.mine)
        await store.refresh()
        #expect(store.blockingError == .notAuthenticated)
    }

    @Test func ghNotFoundOutranksOtherErrors() async throws {
        let gh = FakeGH()
        await gh.set(.failure("boom"), for: SearchQuery.mine)
        await gh.set(.ghNotFound, for: SearchQuery.direct)
        let store = makeStore(gh)
        await store.refresh()
        #expect(store.phase == .error(.ghNotFound, Date(timeIntervalSince1970: 1_000)))
        #expect(store.badgeCount == nil)
    }

    // Review Focus 5
    @Test func recoversAfterGhBecomesAvailable() async throws {
        let gh = FakeGH()
        await gh.set(.ghNotFound, for: SearchQuery.mine)
        await gh.set(.ghNotFound, for: SearchQuery.direct)
        let store = makeStore(gh)
        await store.refresh()
        #expect(store.blockingError == .ghNotFound)
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        await store.refresh()
        #expect(store.blockingError == nil)
        #expect(store.lastError == nil)
        #expect(store.badgeCount == 6)
    }

    @Test func blockingErrorPersistsWhileRefreshing() async throws {
        let gh = FakeGH()
        await gh.set(.ghNotFound, for: SearchQuery.mine)
        await gh.set(.ghNotFound, for: SearchQuery.direct)
        let store = makeStore(gh)
        await store.refresh()
        #expect(store.blockingError == .ghNotFound)
        await gh.setDelay(.milliseconds(300))
        let task = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.phase == .loading)
        #expect(store.blockingError == .ghNotFound)
        #expect(store.lastError == .ghNotFound)
        await task.value
    }

    /// A request that arrives mid-cycle is coalesced into exactly one follow-up cycle, never dropped.
    @Test func concurrentRefreshIsCoalescedIntoOneFollowUp() async throws {
        let gh = try await happyGH()
        await gh.setDelay(.milliseconds(300))
        let store = makeStore(gh)
        let first = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        await store.refresh()
        await store.refresh()
        await first.value
        try await Task.sleep(for: .milliseconds(700))
        #expect(await gh.calls.count == 4)
    }

    @Test func filterChangeDuringACycleIsAppliedAfterwards() async throws {
        let gh = try await happyGH()
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.mine(hiding: ["acme"]))
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.direct(hiding: ["acme"]))
        await gh.setDelay(.milliseconds(300))
        let store = makeStore(gh)
        let first = Task { await store.refresh() }
        // Wait for the first cycle to be in flight, not for a fixed time: under load 50 ms was not enough,
        // and the filter change then started its own cycle before this one, making two filtered searches.
        for _ in 0..<100 where await gh.calls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        store.hiddenOwners = ["acme"]
        await first.value
        try await Task.sleep(for: .milliseconds(700))
        #expect(await gh.callCount(for: SearchQuery.mine(hiding: ["acme"])) == 1)
        #expect(store.mine.total == 0)
        #expect(store.badgeCount == 0)
    }

    @Test func noDataResponseIsAnError() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-errors-only.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let store = makeStore(gh)
        await store.refresh()
        guard case .error(.other, _) = store.phase else { Issue.record("expected .error(.other), got \(store.phase)"); return }
        #expect(store.direct.value.count == 3)
    }

    @Test func expandingViaTeamFetchesItLazily() async throws {
        let gh = try await happyGH()
        let store = makeStore(gh)
        await store.refresh()
        #expect(store.viaTeam == nil)
        store.isViaTeamExpanded = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.viaTeam?.total == 154)
        #expect(store.viaTeamList.map(\.number) == [301, 302])
        await store.refresh()
        #expect(await gh.callCount(for: SearchQuery.viaTeam) == 2)
    }

    @Test func viaTeamFailureIsReportedInsteadOfSpinningForever() async throws {
        let gh = try await happyGH()
        await gh.set(.failure("boom"), for: SearchQuery.viaTeam)
        let store = makeStore(gh)
        await store.refresh()
        store.isViaTeamExpanded = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.isLoadingViaTeam == false)
        #expect(store.viaTeam == nil)
        #expect(store.viaTeamError == .other("boom"))
        await gh.set(.success(try fixture("search-team.json")), for: SearchQuery.viaTeam)
        await store.refreshViaTeam()
        #expect(store.viaTeamError == nil)
        #expect(store.viaTeam?.total == 154)
    }

    @Test func sectionPreferencesDefaultAndPersist() async throws {
        let defaults = testDefaults()
        let store = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(store.visibleSections == Set(Section.allCases))
        #expect(store.badgeSections == Section.defaultBadge)
        store.badgeSections = [.needsYourReview]
        store.visibleSections = [.needsAction, .needsYourReview]
        #expect(Set(defaults.stringArray(forKey: PRStore.badgeSectionsKey) ?? []) == ["needsYourReview"])
        let reloaded = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(reloaded.badgeSections == [.needsYourReview])
        #expect(reloaded.visibleSections == [.needsAction, .needsYourReview])
    }

    /// Visibility used to be stored as the visible set, so a section added later (Snoozed) came up hidden
    /// for anyone with a saved preference. It is stored as the hidden set now, and the old key migrates.
    @Test func sectionsAddedAfterTheSavedPreferenceStayVisible() async throws {
        let defaults = testDefaults()
        defaults.set(["needsAction", "needsYourReview"], forKey: "visibleSections")
        let store = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(store.visibleSections == [.needsAction, .needsYourReview, .snoozedMine, .snoozedReview])
        #expect(defaults.object(forKey: "visibleSections") == nil)
        #expect(Set(defaults.stringArray(forKey: PRStore.hiddenSectionsKey) ?? []) == ["drafts", "needsTeamsReview", "readyToMerge", "waitingForReview"])
        store.visibleSections.remove(.snoozedMine)
        let reloaded = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(!reloaded.visibleSections.contains(.snoozedMine))
        #expect(reloaded.visibleSections.contains(.snoozedReview))
    }

    @Test func changingBadgeSectionsRecomputesWithoutAFetch() async throws {
        let gh = try await happyGH()
        let store = makeStore(gh)
        await store.refresh()
        #expect(store.badgeCount == 6)
        store.badgeSections = [.needsYourReview]
        #expect(store.badgeCount == 3)
        #expect(await gh.calls.count == 2)
    }

    @Test func countingTeamsInBadgeFetchesTeamEveryCycle() async throws {
        let gh = try await happyGH()
        let store = makeStore(gh)
        await store.refresh()
        store.badgeSections = [.needsTeamsReview]
        try await Task.sleep(for: .milliseconds(150))
        #expect(await gh.callCount(for: SearchQuery.viaTeam) == 1)
        #expect(store.viaTeamList.count == 2)
        #expect(store.badgeCount == 2)
        await store.refresh()
        #expect(await gh.callCount(for: SearchQuery.viaTeam) == 2)
    }

    @Test func tabCountsFollowVisibleSections() async throws {
        let store = makeStore(try await happyGH())
        await store.refresh()
        #expect(store.mineTabCount == 5)
        #expect(store.reviewTabCount == 27)
        store.visibleSections = [.needsAction, .needsTeamsReview]
        #expect(store.mineTabCount == 1)
        #expect(store.reviewTabCount == 0)
        store.visibleSections = [.drafts]
        #expect(store.mineTabCount == 2)
    }

    @Test func sectionOrderDefaultsToGitHubOrderAndPersists() async throws {
        let defaults = testDefaults()
        let store = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(store.orderedSections(.mine) == [Section.needsAction, .readyToMerge, .waitingForReview, .drafts])
        #expect(store.orderedSections(.review) == Section.reviewSections)
        store.moveSections(in: .mine, from: IndexSet(integer: 3), to: 2)
        #expect(store.orderedSections(.mine) == [.needsAction, .readyToMerge, .drafts, .waitingForReview])
        store.moveSections(in: .mine, from: IndexSet(integer: 2), to: 0)
        #expect(store.orderedSections(.mine) == [.drafts, .needsAction, .readyToMerge, .waitingForReview])
        let reloaded = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(reloaded.orderedSections(.mine) == [.drafts, .needsAction, .readyToMerge, .waitingForReview])
        #expect(reloaded.orderedSections(.review) == Section.reviewSections)
    }

    @Test func dragMoveReordersWithinATab() async throws {
        let store = makeStore(try await happyGH())
        store.moveSections(in: .mine, from: IndexSet(integer: 0), to: 3)
        #expect(store.orderedSections(.mine) == [.readyToMerge, .waitingForReview, .needsAction, .drafts])
        store.moveSections(in: .review, from: IndexSet(integer: 1), to: 0)
        #expect(store.orderedSections(.review) == [.needsTeamsReview, .needsYourReview])
    }


    @Test func unknownStoredSectionsAreIgnoredAndMissingOnesAppended() async throws {
        let defaults = testDefaults()
        defaults.set(["drafts", "bogus", "needsAction"], forKey: PRStore.sectionOrderKey)
        let store = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(store.orderedSections(.mine) == [.drafts, .needsAction, .readyToMerge, .waitingForReview])
        #expect(store.orderedSections(.review) == Section.reviewSections)
    }

    @Test func resetSectionsRestoresOrderVisibilityAndBadge() async throws {
        let store = makeStore(try await happyGH())
        store.moveSections(in: .mine, from: IndexSet(integer: 3), to: 0)
        store.visibleSections = [.drafts]
        store.badgeSections = []
        store.resetSectionsToDefault()
        #expect(store.orderedSections(.mine) == [Section.needsAction, .readyToMerge, .waitingForReview, .drafts])
        #expect(store.visibleSections == Set(Section.allCases))
        #expect(store.badgeSections == Section.defaultBadge)
    }

    /// A settings change that needs a new search is flagged until that cycle ends, so the UI can say "applying".
    @Test func settingsChangesAreFlaggedUntilTheirCycleCompletes() async throws {
        let gh = try await happyGH()
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.mine(hiding: ["acme"]))
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.direct(hiding: ["acme"]))
        await gh.setDelay(.milliseconds(300))
        let store = makeStore(gh)
        await store.refresh()
        #expect(store.isApplyingSettingsChange == false)
        store.hiddenOwners = ["acme"]
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.isApplyingSettingsChange == true)
        try await Task.sleep(for: .milliseconds(700))
        #expect(store.isApplyingSettingsChange == false)
        // A plain timer/manual refresh is not a settings change.
        let plain = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.isApplyingSettingsChange == false)
        await plain.value
    }

    @Test func viaTeamExpansionPersistsInDefaults() async throws {
        let defaults = testDefaults()
        let store = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        store.isViaTeamExpanded = true
        #expect(defaults.bool(forKey: PRStore.expandedKey) == true)
    }

    @Test func holdingAutoRefreshSkipsTimerCyclesUntilReleased() async throws {
        let gh = try await happyGH()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        store.refreshInterval = .milliseconds(30)
        store.holdsAutoRefresh = true
        store.start()
        try await Task.sleep(for: .milliseconds(150))
        #expect(await gh.callCount(for: SearchQuery.mine) == 0)
        store.holdsAutoRefresh = false
        try await Task.sleep(for: .milliseconds(150))
        #expect(await gh.callCount(for: SearchQuery.mine) > 0)
    }

    @Test func refreshIntervalDefaultsTo120sAndPersists() async throws {
        let defaults = testDefaults()
        let store = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(store.refreshInterval == .seconds(120))
        store.refreshInterval = .seconds(300)
        #expect(defaults.integer(forKey: PRStore.intervalKey) == 300)
        let reloaded = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(reloaded.refreshInterval == .seconds(300))
    }
}
