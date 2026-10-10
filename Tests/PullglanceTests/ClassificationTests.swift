import Foundation
import Testing
@testable import Pullglance

@Suite struct ClassificationTests {
    @Test func ciFailureOnNonDraftNeedsAction() {
        #expect(mineSection(for: makePR(ciState: .failure)) == .needsAction)
    }

    @Test func changesRequestedOnNonDraftNeedsAction() {
        #expect(mineSection(for: makePR(reviewDecision: .changesRequested, ciState: .success)) == .needsAction)
    }

    @Test func mergeConflictNeedsAction() {
        #expect(mineSection(for: makePR(reviewDecision: .approved, ciState: .success, hasConflicts: true)) == .needsAction)
    }

    @Test func behindBaseNeedsAction() {
        #expect(mineSection(for: makePR(reviewDecision: .approved, ciState: .success, isBehindBase: true)) == .needsAction)
    }

    @Test func openThreadsAloneDoNotNeedAction() {
        #expect(mineSection(for: makePR(reviewDecision: .approved, ciState: .success, unresolvedThreads: 3)) == .readyToMerge)
    }

    @Test func approvedWithPendingCIWaitsForChecks() {
        #expect(mineSection(for: makePR(reviewDecision: .approved, ciState: .pending)) == .waitingForReview)
    }

    @Test func approvedWithNoCIIsReadyToMerge() {
        #expect(mineSection(for: makePR(reviewDecision: .approved, ciState: .none)) == .readyToMerge)
    }

    @Test func draftWithFailingCIIsStillDraft() {
        #expect(mineSection(for: makePR(isDraft: true, ciState: .failure)) == .drafts)
    }

    @Test func draftWithChangesRequestedIsStillDraft() {
        #expect(mineSection(for: makePR(isDraft: true, reviewDecision: .changesRequested)) == .drafts)
    }

    @Test func approvedWithGreenCIIsReadyToMerge() {
        #expect(mineSection(for: makePR(reviewDecision: .approved, ciState: .success)) == .readyToMerge)
    }

    @Test func pendingCIWaitsForChecks() {
        #expect(mineSection(for: makePR(ciState: .pending)) == .waitingForReview)
    }

    @Test func reviewRequiredWaitsForReview() {
        #expect(mineSection(for: makePR(reviewDecision: .reviewRequired, ciState: .success)) == .waitingForReview)
    }

    @Test func groupsMineFixtureIntoSectionsSortedByRecency() throws {
        let prs = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let groups = groupMine(prs)
        #expect(groups.needsAction.map(\.number) == [101])
        #expect(groups.readyToMerge.map(\.number) == [102, 103])
        #expect(groups.waitingForReview.isEmpty)
        #expect(groups.drafts.map(\.number) == [104, 105])
        #expect(groups[.needsAction].map(\.number) == [101])
    }

    @Test func sortedByRecencyIsDescending() {
        let old = makePR(number: 1, updatedAt: Date(timeIntervalSince1970: 100))
        let new = makePR(number: 2, updatedAt: Date(timeIntervalSince1970: 200))
        #expect(sortedByRecency([old, new]).map(\.number) == [2, 1])
    }

    @Test func viaTeamDropsDirectDuplicatesAndOwnPRs() throws {
        let team = try parseSearchResponse(fixture("search-team.json")).pullRequests
        let direct = try parseSearchResponse(fixture("search-direct.json")).pullRequests
        let result = filterViaTeam(all: team, direct: direct, viewerLogin: "octocat")
        #expect(result.map(\.number) == [301, 302])
    }

    @Test func viaTeamRespectsLimit() {
        let many = (1...30).map { makePR(number: $0, author: "other", updatedAt: Date(timeIntervalSince1970: Double($0))) }
        let result = filterViaTeam(all: many, direct: [], viewerLogin: "octocat", limit: 20)
        #expect(result.count == 20)
        #expect(result.first?.number == 30)
    }

    @Test func viaTeamWithUnknownViewerKeepsEverything() {
        let prs = [makePR(number: 1, author: "octocat"), makePR(number: 2, author: "other")]
        #expect(filterViaTeam(all: prs, direct: [], viewerLogin: nil).count == 2)
    }

    @Test func defaultBadgeCountsActionReadyAndDirect() throws {
        let mine = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let direct = try parseSearchResponse(fixture("search-direct.json")).pullRequests
        #expect(computeBadgeCount(mine: mine, direct: direct, viaTeam: [], counting: Section.defaultBadge) == 1 + 2 + 3)
    }

    @Test func badgeOnlyCountsSelectedSections() throws {
        let mine = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let direct = try parseSearchResponse(fixture("search-direct.json")).pullRequests
        #expect(computeBadgeCount(mine: mine, direct: direct, viaTeam: [], counting: [.needsYourReview]) == 3)
        #expect(computeBadgeCount(mine: mine, direct: direct, viaTeam: [], counting: [.drafts]) == 2)
        #expect(computeBadgeCount(mine: mine, direct: direct, viaTeam: [makePR(number: 9)], counting: [.needsTeamsReview]) == 1)
        #expect(computeBadgeCount(mine: mine, direct: direct, viaTeam: [], counting: []) == 0)
    }

    @Test func draftsNeverCountUnlessSelected() {
        let mine = [makePR(number: 1, isDraft: true, ciState: .failure, hasConflicts: true)]
        #expect(computeBadgeCount(mine: mine, direct: [], viaTeam: [], counting: [.needsAction, .readyToMerge]) == 0)
    }
}
