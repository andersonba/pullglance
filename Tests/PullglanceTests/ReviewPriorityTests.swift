import Foundation
import Testing
@testable import Pullglance

/// "Needs your review" ordered by what asks for you first: tiers, not points, so a pill can say why.
@Suite struct ReviewPriorityTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    @Test func tiersFromStrongestToWeakest() {
        #expect(reviewSignal(for: makePR(viewerReviewedBefore: true, viewerRequested: true), now: now) == .reReview)
        #expect(reviewSignal(for: makePR(isReadByViewer: false), now: now) == .newActivity)
        #expect(reviewSignal(for: makePR(changedFiles: 3, linesChanged: 400), now: now) == .quick(files: 3))
        #expect(reviewSignal(for: makePR(changedFiles: 12, linesChanged: 40), now: now) == .quick(files: 12))
        #expect(reviewSignal(for: makePR(createdAt: days(6)), now: now) == .waiting(days: 6))
        // Fresh, read, large: nothing to say.
        #expect(reviewSignal(for: makePR(createdAt: days(1)), now: now) == nil)
        // Unknown size is not small.
        #expect(reviewSignal(for: makePR(changedFiles: nil, linesChanged: nil), now: now) == nil)
    }

    @Test func aStrongerSignalWinsThePill() {
        let both = makePR(isReadByViewer: false, changedFiles: 1, linesChanged: 2, viewerReviewedBefore: true, viewerRequested: true)
        #expect(reviewSignal(for: both, now: now) == .reReview)
        #expect(reviewSignal(for: makePR(isReadByViewer: false, changedFiles: 1, linesChanged: 2), now: now) == .newActivity)
    }

    /// Within a tier the oldest request comes first; red CI and drafts sink below everything, in the same order.
    @Test func orderIsTierThenAgeWithTheAuthorStillWorkingAtTheBottom() {
        let reReview = makePR(number: 1, createdAt: days(1), viewerReviewedBefore: true, viewerRequested: true)
        let unreadOld = makePR(number: 2, createdAt: days(5), isReadByViewer: false)
        let unreadNew = makePR(number: 3, createdAt: days(1), isReadByViewer: false)
        let quick = makePR(number: 4, createdAt: days(0.5), changedFiles: 2, linesChanged: 10)
        let plainOld = makePR(number: 5, createdAt: days(9))
        let plainNew = makePR(number: 6, createdAt: days(2))
        let failing = makePR(number: 7, ciState: .failure, createdAt: days(20), viewerReviewedBefore: true, viewerRequested: true)
        let draft = makePR(number: 8, isDraft: true, createdAt: days(30))
        let shuffled = [plainNew, draft, quick, failing, unreadNew, plainOld, reReview, unreadOld]
        #expect(sortedByPriority(shuffled, now: now).map(\.number) == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test func sortChoicePersistsPerSectionAndDefaultsToPriorityForReviews() {
        #expect(ListSort.default(for: .needsYourReview) == .priority)
        #expect(ListSort.default(for: .needsTeamsReview) == .priority)
        #expect(ListSort.default(for: .readyToMerge) == .recent)
    }
}
