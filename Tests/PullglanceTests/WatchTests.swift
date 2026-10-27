import Foundation
import Testing
@testable import Pullglance

@Suite struct WatchMarkTests {
    private let base = makePR(number: 7, reviewDecision: .reviewRequired, ciState: .pending)

    @Test func checksFinishingIsMovement() {
        let mark = WatchMark(base)
        #expect(mark.movement(for: makePR(number: 7, reviewDecision: .reviewRequired, ciState: .success)) == .checksPassed)
        #expect(mark.movement(for: makePR(number: 7, reviewDecision: .reviewRequired, ciState: .failure)) == .checksFailed)
    }

    @Test func aReviewDecisionIsMovement() {
        let mark = WatchMark(base)
        #expect(mark.movement(for: makePR(number: 7, reviewDecision: .approved, ciState: .pending)) == .approved)
        #expect(mark.movement(for: makePR(number: 7, reviewDecision: .changesRequested, ciState: .pending)) == .changesRequested)
    }

    @Test func conflictsBehindBaseAndTheQueueAreMovement() {
        let mark = WatchMark(base)
        #expect(mark.movement(for: makePR(number: 7, reviewDecision: .reviewRequired, ciState: .pending, hasConflicts: true)) == .conflicts)
        #expect(mark.movement(for: makePR(number: 7, reviewDecision: .reviewRequired, ciState: .pending, isBehindBase: true)) == .behindBase)
        let queued = WatchMark(makePR(number: 7, ciState: .success, mergeQueuePosition: 3))
        #expect(queued.movement(for: makePR(number: 7, ciState: .success, mergeQueuePosition: 1)) == .queuePosition(1))
        #expect(queued.movement(for: makePR(number: 7, ciState: .success, mergeQueuePosition: 3)) == nil)
        // Entering the queue is the user's own doing (the app watches right after enqueueing): a re-mark, not news.
        let entering = makePR(number: 7, ciState: .success, mergeQueuePosition: 2)
        #expect(mark.movement(for: entering) == nil)
        #expect(mark.needsRebase(for: entering))
    }

    @Test func theWorstNewsWinsWhenSeveralThingsChanged() {
        let mark = WatchMark(base)
        #expect(mark.movement(for: makePR(number: 7, reviewDecision: .approved, ciState: .failure)) == .checksFailed)
        #expect(mark.movement(for: makePR(number: 7, reviewDecision: .approved, ciState: .success)) == .approved)
    }

    @Test func aCommentAloneIsNotMovement() {
        let mark = WatchMark(base)
        #expect(mark.movement(for: makePR(number: 7, updatedAt: Date(), reviewDecision: .reviewRequired, ciState: .pending, unresolvedThreads: 2)) == nil)
    }

    @Test func aNewCommitAloneRebasesTheMarkInsteadOfNotifying() {
        let mark = WatchMark(base)
        let pushed = makePR(number: 7, reviewDecision: .reviewRequired, ciState: .pending, headRefOid: "def5678")
        #expect(mark.movement(for: pushed) == nil)
        #expect(mark.needsRebase(for: pushed))
        let rebased = WatchMark(pushed)
        #expect(rebased.headRefOid == "def5678")
        // The checks on the new head count from there.
        #expect(rebased.movement(for: makePR(number: 7, reviewDecision: .reviewRequired, ciState: .success, headRefOid: "def5678")) == .checksPassed)
        // CI already green on the old head, pending again on the new one: not "checks failed", just a new run.
        let green = WatchMark(makePR(number: 7, ciState: .success))
        #expect(green.movement(for: pushed) == nil)
    }

    @Test func marksSurviveDefaults() throws {
        let mark = WatchMark(makePR(repo: "acme/api", number: 9, reviewDecision: .approved, ciState: .pending, mergeQueuePosition: 2))
        let back = try JSONDecoder().decode(WatchMark.self, from: JSONEncoder().encode(mark))
        #expect(back == mark)
        #expect(back.repo == "acme/api" && back.number == 9)
    }
}

@MainActor
@Suite struct WatchStoreTests {
    /// #7 of mine with CI pending, #8 of mine settled; nothing to review.
    private func make(clock: Clock = Clock()) async -> (PRStore, FakeGH, FakeSnoozeNotifier, UserDefaults) {
        let gh = FakeGH()
        let defaults = testDefaults()
        await gh.set(.success(envelope(nodes: [node(number: 7, ci: "PENDING", decision: "REVIEW_REQUIRED"), node(number: 8, ci: "SUCCESS", decision: "APPROVED")])), for: SearchQuery.mine)
        await gh.set(.success(envelope(nodes: [])), for: SearchQuery.direct)
        let notifier = FakeSnoozeNotifier()
        let store = PRStore(client: gh, defaults: defaults, now: { clock.now }, notifier: notifier)
        await store.refresh()
        return (store, gh, notifier, defaults)
    }

    private func pr(_ store: PRStore, _ number: Int) throws -> PullRequest { try #require(store.mine.value.first { $0.number == number }) }

    @Test func watchingIsAMarkThatSurvivesARelaunch() async throws {
        let (store, gh, _, defaults) = await make()
        let seven = try pr(store, 7)
        #expect(!store.isWatched(seven))
        #expect(store.watch(seven))
        #expect(store.isWatched(seven))
        #expect(store.watched[seven.id]?.headRefOid == "abc1234")
        let again = PRStore(client: gh, defaults: defaults)
        #expect(again.watched[seven.id] == store.watched[seven.id])
        store.unwatch(seven)
        #expect(!store.isWatched(seven))
        #expect(PRStore(client: gh, defaults: defaults).watched.isEmpty)
    }

    @Test func atMostTenAreWatched() async throws {
        let (store, _, _, _) = await make()
        for n in 1...10 { #expect(store.watch(makePR(number: 100 + n))) }
        #expect(!store.watch(makePR(number: 111)))
        #expect(store.watched.count == 10)
    }

    @Test func aPollNotifiesTheMovementEndsTheWatchAndMarksTheRow() async throws {
        let (store, gh, notifier, _) = await make()
        let seven = try pr(store, 7)
        _ = store.watch(seven)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 7, ci: "SUCCESS", decision: "APPROVED"))), number: 7)
        #expect(await store.pollWatched() == 1)
        #expect(await gh.lookups.map(\.number) == [7])
        #expect(notifier.moves.map(\.movement) == [.approved])
        #expect(notifier.moves.first?.mark.number == 7)
        #expect(!store.isWatched(seven), "the watch ends with the notification")
        #expect(store.moved[seven.id] == .approved)
        #expect(store.hasUnseenWoke, "the icon's dot")
        #expect(store.mineGroups.readyToMerge.contains { $0.number == 7 }, "the fresh state is in place")
        #expect(store.actionState(for: seven) == nil, "quiet: no spinner")
        // The pill lives through one opening of the popover, like Woke.
        store.popoverDidOpen()
        #expect(store.moved[seven.id] == .approved)
        store.popoverDidClose()
        store.popoverDidOpen()
        #expect(store.moved[seven.id] == nil)
    }

    @Test func aNewCommitRebasesTheMarkQuietly() async throws {
        let (store, gh, notifier, _) = await make()
        let seven = try pr(store, 7)
        _ = store.watch(seven)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 7, ci: "PENDING", decision: "REVIEW_REQUIRED", headRefOid: "def5678"))), number: 7)
        #expect(await store.pollWatched() == 1)
        #expect(notifier.moves.isEmpty)
        #expect(store.watched[seven.id]?.headRefOid == "def5678")
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 7, ci: "SUCCESS", decision: "REVIEW_REQUIRED", headRefOid: "def5678"))), number: 7)
        #expect(await store.pollWatched() == 1)
        #expect(notifier.moves.map(\.movement) == [.checksPassed])
    }

    @Test func aMergedOneSaysSoAndLeavesTheList() async throws {
        let (store, gh, notifier, _) = await make()
        let seven = try pr(store, 7)
        _ = store.watch(seven)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 7, ci: "SUCCESS"), state: "MERGED")), number: 7)
        #expect(await store.pollWatched() == 1)
        #expect(notifier.moves.map(\.movement) == [.merged])
        #expect(!store.mine.value.contains { $0.number == 7 })
        #expect(!store.isWatched(seven))
        // Closed without a merge is its own word.
        let eight = try pr(store, 8)
        _ = store.watch(eight)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 8, ci: "SUCCESS"), state: "CLOSED")), number: 8)
        #expect(await store.pollWatched() == 1)
        #expect(notifier.moves.map(\.movement) == [.merged, .closed])
    }

    @Test func aWatchedOneGoneFromTheListsIsStillLookedUp() async throws {
        let (store, gh, notifier, _) = await make()
        let seven = try pr(store, 7)
        _ = store.watch(seven)
        // The next search no longer lists it (merged meanwhile); the watch still asks GitHub.
        await gh.set(.success(envelope(nodes: [node(number: 8, ci: "SUCCESS", decision: "APPROVED")])), for: SearchQuery.mine)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 7, ci: "SUCCESS"), state: "MERGED")), number: 7)
        await store.refresh()
        #expect(await store.pollWatched() == 1)
        #expect(notifier.moves.map(\.movement) == [.merged])
        #expect(store.watched.isEmpty)
    }

    @Test func aFullCycleChecksWatchedRowsToo() async throws {
        let (store, gh, notifier, _) = await make()
        _ = store.watch(try pr(store, 7))
        await gh.set(.success(envelope(nodes: [node(number: 7, ci: "FAILURE", decision: "REVIEW_REQUIRED"), node(number: 8, ci: "SUCCESS", decision: "APPROVED")])), for: SearchQuery.mine)
        await store.refresh()
        #expect(notifier.moves.map(\.movement) == [.checksFailed])
        #expect(store.watched.isEmpty)
    }

    @Test func thePollYieldsLikeTheCIPoll() async throws {
        let clock = Clock()
        let (store, gh, _, _) = await make(clock: clock)
        let seven = try pr(store, 7)
        _ = store.watch(seven)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 7, ci: "SUCCESS", decision: "APPROVED"))), number: 7)
        clock.advance(118)
        #expect(await store.pollWatched() == 0, "a full cycle is 2 s away")
        clock.advance(-60)
        store.holdsAutoRefresh = true
        #expect(await store.pollWatched() == 0, "reorder mode")
        store.holdsAutoRefresh = false
        store.setActionState(.running(.comment), for: seven)
        #expect(await store.pollWatched() == 0, "an action is in flight on the row")
        store.clearActionState(for: seven)
        #expect(await store.pollWatched() == 1)
    }

    @Test func aFailedLookupKeepsTheWatch() async throws {
        let (store, gh, notifier, _) = await make()
        let seven = try pr(store, 7)
        _ = store.watch(seven)
        await gh.setPullRequest(.failure("boom"), number: 7)
        #expect(await store.pollWatched() == 1)
        #expect(store.isWatched(seven))
        #expect(notifier.moves.isEmpty)
        #expect(store.actionStates.isEmpty)
    }
}

@Suite struct RateLimitTests {
    @Test func theLookupAsksForTheRateLimit() {
        // So the log can say what the watch poll costs; the search query stays as it is.
        #expect(GHClient.pullRequestQuery.contains("rateLimit { remaining resetAt }"))
        #expect(!GHClient.pullRequestFragment.contains("rateLimit"))
    }

    @Test func theRateLimitIsReadNextToTheData() throws {
        let data = Data(#"{"data":{"rateLimit":{"remaining":4987,"resetAt":"2026-10-27T15:00:00Z"},"repository":{"pullRequest":null}}}"#.utf8)
        let status = try #require(parseRateLimit(data))
        #expect(status.remaining == 4987)
        #expect(status.resetAt == ISO8601DateFormatter().date(from: "2026-10-27T15:00:00Z"))
    }

    @Test func aResponseWithoutItIsNotAnError() {
        #expect(parseRateLimit(pullRequestEnvelope(nil)) == nil)
        #expect(parseRateLimit(Data("not json".utf8)) == nil)
    }
}
