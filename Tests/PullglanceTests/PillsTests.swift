import Testing
@testable import Pullglance

@Suite struct PillsTests {
    @Test func failingCIWithChangesRequestedAndThreads() {
        let pr = makePR(reviewDecision: .changesRequested, ciState: .failure, unresolvedThreads: 5)
        #expect(pills(for: pr) == [.ciFailed, .changesRequested, .openThreads(5)])
    }

    @Test func approvedAndGreenIsReadyToMerge() {
        #expect(pills(for: makePR(reviewDecision: .approved, ciState: .success)) == [.approved, .readyToMerge])
        // A draft cannot be merged, however green: no "Ready to merge" on it.
        #expect(pills(for: makePR(isDraft: true, reviewDecision: .approved, ciState: .success)) == [.approved])
    }

    @Test func aQueuedPullRequestShowsItsPositionInsteadOfReady() {
        #expect(pills(for: makePR(reviewDecision: .approved, ciState: .success, usesMergeQueue: true, mergeQueuePosition: 3)) == [.approved, .inMergeQueue(3)])
        // Queue enabled but not queued yet: still "ready", the modal explains the queue.
        #expect(pills(for: makePR(reviewDecision: .approved, ciState: .success, usesMergeQueue: true)) == [.approved, .readyToMerge])
        #expect(pills(for: makePR(reviewDecision: .approved, ciState: .pending, isBlocked: true, autoMergeMethod: .squash)) == [.ciRunning, .approved, .autoMerge])
        // Queue membership does not depend on a review: repositories without required reviews queue too.
        #expect(pills(for: makePR(reviewDecision: nil, ciState: .success, usesMergeQueue: true, mergeQueuePosition: 2)) == [.awaitingReview, .inMergeQueue(2)])
    }

    @Test func approvedWithPendingCIIsNotReady() {
        #expect(pills(for: makePR(reviewDecision: .approved, ciState: .pending)) == [.ciRunning, .approved])
    }

    @Test func reviewRequiredIsAwaitingReview() {
        #expect(pills(for: makePR(reviewDecision: .reviewRequired, ciState: .success)) == [.awaitingReview])
    }

    @Test func nilDecisionIsAwaitingReview() {
        #expect(pills(for: makePR(reviewDecision: nil, ciState: .none)) == [.awaitingReview])
    }

    @Test func noRequiredReviewAndGreenIsReadyToMerge() {
        #expect(pills(for: makePR(reviewDecision: nil, ciState: .success)) == [.readyToMerge])
        #expect(pills(for: makePR(reviewDecision: nil, ciState: .success, isBlocked: true)) == [.awaitingReview])
        #expect(pills(for: makePR(reviewDecision: nil, ciState: .success, hasMergeState: false)) == [.awaitingReview])
        #expect(pills(for: makePR(isDraft: true, reviewDecision: nil, ciState: .success)) == [.awaitingReview])
    }

    @Test func draftStillShowsAwaitingReview() {
        #expect(pills(for: makePR(isDraft: true, reviewDecision: .reviewRequired)) == [.awaitingReview])
    }

    @Test func conflictsReplaceReadyToMerge() {
        #expect(pills(for: makePR(reviewDecision: .approved, ciState: .success, hasConflicts: true)) == [.approved, .conflicts])
    }

    @Test func behindBaseShowsItsPill() {
        #expect(pills(for: makePR(reviewDecision: .reviewRequired, ciState: .success, isBehindBase: true)) == [.awaitingReview, .behindBase])
    }

    @Test func zeroThreadsHasNoThreadPill() {
        let result = pills(for: makePR(reviewDecision: .approved, ciState: .success, unresolvedThreads: 0))
        #expect(result.contains { if case .openThreads = $0 { true } else { false } } == false)
    }
}
