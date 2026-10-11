import Foundation
import Testing
@testable import Pullglance

/// A clock the tests can move.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

@MainActor
@Suite struct CIPollTests {
    /// Fixtures: #104 (mine, draft) and #203 (direct) have CI pending; the others are settled.
    private func make(clock: Clock = Clock(), interval: Duration = .seconds(20)) async throws -> (PRStore, FakeGH) {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { clock.now }, ciPollInterval: interval)
        await store.refresh()
        return (store, gh)
    }

    @Test func looksUpOnlyRowsWithCIStillRunningAndMovesThem() async throws {
        let (store, gh) = try await make()
        let pending = (store.mine.value + store.direct.value).filter { $0.ciState == .pending }
        #expect(pending.map(\.number) == [104, 203])
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 104, ci: "SUCCESS", decision: "APPROVED"))), number: 104)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 203, ci: "SUCCESS", repo: "acme/cli"))), number: 203)
        #expect(await store.pollPendingCI() == 2)
        #expect(await gh.lookups.map(\.number) == [104, 203])
        #expect(store.mineGroups.readyToMerge.contains { $0.number == 104 })
        #expect(store.actionState(for: pending[0]) == nil, "quiet: no spinner, no state")
        #expect(await gh.callCount(for: SearchQuery.mine) == 1, "no full refresh")
        // Settled now: the next round has nothing to do.
        #expect(await store.pollPendingCI() == 0)
    }

    @Test func aQuietFailureLeavesNoMarkOnTheRow() async throws {
        let (store, gh) = try await make()
        let pr = try #require(store.mine.value.first { $0.number == 104 })
        await gh.setPullRequest(.failure("boom"), number: 104)
        await gh.setPullRequest(.failure("boom"), number: 203)
        #expect(await store.pollPendingCI() == 2)
        #expect(store.actionState(for: pr) == nil)
        #expect(store.actionStates.isEmpty)
        #expect(store.mine.value.contains { $0.id == pr.id })
    }

    @Test func yieldsToAnImminentOrRunningFullCycleAndToReorderMode() async throws {
        let clock = Clock()
        let (store, gh) = try await make(clock: clock)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 104, ci: "SUCCESS"))), number: 104)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 203, ci: "SUCCESS", repo: "acme/cli"))), number: 203)
        // The next cycle is 120 s away: fine. Move to 3 s before it: skip.
        clock.advance(118)
        #expect(await store.pollPendingCI() == 0)
        clock.advance(-60)
        store.holdsAutoRefresh = true
        #expect(await store.pollPendingCI() == 0)
        store.holdsAutoRefresh = false
        await gh.setDelay(.milliseconds(200))
        let cycle = Task { await store.refresh() }
        for _ in 0..<100 where await gh.calls.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await store.pollPendingCI() == 0, "a cycle is in flight")
        await cycle.value
        await gh.setDelay(.zero)
        #expect(await store.pollPendingCI() == 2)
    }

    @Test func skipsSnoozedRowsAndRowsWithAnActionInProgress() async throws {
        let (store, gh) = try await make()
        let pr = try #require(store.mine.value.first { $0.number == 104 })
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 104, ci: "PENDING"))), number: 104)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 203, ci: "PENDING", repo: "acme/cli"))), number: 203)
        store.snooze(pr)
        #expect(await store.pollPendingCI() == 1)
        #expect(await gh.lookups.map(\.number) == [203], "snoozed rows are left alone")
        store.wake(pr)
        await gh.setDelay(.milliseconds(200))
        let manual = Task { await store.refreshOne(pr) }
        for _ in 0..<100 where await gh.lookups.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await store.pollPendingCI() == 1, "the user's own refresh is running on #104; only #203 is checked")
        #expect(await gh.lookups.map(\.number) == [203, 104, 203])
        _ = await manual.value
    }

    @Test func pollingRunsWhileStartedAndStopsWhenStopped() async throws {
        let (store, gh) = try await make(interval: .milliseconds(30))
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 104, ci: "PENDING"))), number: 104)
        store.startCIPolling()
        try await Task.sleep(for: .milliseconds(200))
        let during = await gh.lookups.count
        #expect(during >= 2)
        store.stopCIPolling()
        try await Task.sleep(for: .milliseconds(120))
        #expect(await gh.lookups.count == during)
    }
}
