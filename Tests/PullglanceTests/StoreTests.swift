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
        #expect(store.badgeCount == 4)
        #expect(store.viewerLogin == "octocat")
        #expect(store.mineGroups.needsYou.map(\.number) == [101])
        #expect(store.directList.map(\.number) == [201, 202, 203])
        #expect(await gh.callCount(for: SearchQuery.viaTeam) == 0)
    }

    @Test func failureKeepsPreviousSnapshotAndBadge() async throws {
        let gh = try await happyGH()
        let store = makeStore(gh)
        await store.refresh()
        await gh.set(.failure("network down"), for: SearchQuery.direct)
        await store.refresh()
        #expect(store.phase == .error(.other("network down"), Date(timeIntervalSince1970: 1_000)))
        #expect(store.direct.value.count == 3)
        #expect(store.badgeCount == 4)
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
        #expect(store.badgeCount == 4)
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
        #expect(store.isRefreshing)
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
        try await Task.sleep(for: .milliseconds(50))
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

    @Test func viaTeamExpansionPersistsInDefaults() async throws {
        let defaults = testDefaults()
        let store = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        store.isViaTeamExpanded = true
        #expect(defaults.bool(forKey: PRStore.expandedKey) == true)
    }

    @Test func refreshIntervalDefaultsTo120sAndPersists() async throws {
        let defaults = testDefaults()
        let store = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(store.refreshInterval == .seconds(120))
        store.refreshInterval = .seconds(300)
        #expect(defaults.integer(forKey: PRStore.intervalKey) == 300)
        let reloaded = PRStore(client: try await happyGH(), defaults: defaults, now: { Date() })
        #expect(reloaded.refreshInterval == .seconds(300))
        store.stop()
        reloaded.stop()
    }
}
