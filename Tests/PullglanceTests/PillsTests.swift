import Testing
@testable import Pullglance

@Suite struct PillsTests {
    @Test func failingCIWithChangesRequestedAndThreads() {
        let pr = makePR(reviewDecision: .changesRequested, ciState: .failure, unresolvedThreads: 5)
        #expect(pills(for: pr) == [.ciFailed, .changesRequested, .openThreads(5)])
    }

    @Test func approvedAndGreenIsReadyToMerge() {
        #expect(pills(for: makePR(reviewDecision: .approved, ciState: .success)) == [.approved, .readyToMerge])
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
