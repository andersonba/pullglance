import Foundation
import Testing
@testable import Pullglance

@Suite struct ClassificationTests {
    @Test func ciFailureOnNonDraftNeedsYou() {
        #expect(mineSection(for: makePR(ciState: .failure)) == .needsYou)
    }

    @Test func changesRequestedOnNonDraftNeedsYou() {
        #expect(mineSection(for: makePR(reviewDecision: .changesRequested, ciState: .success)) == .needsYou)
    }

    @Test func openThreadsAloneDoNotNeedYou() {
        #expect(mineSection(for: makePR(reviewDecision: .approved, ciState: .success, unresolvedThreads: 3)) == .waitingOnOthers)
    }

    @Test func draftWithFailingCIIsStillDraft() {
        #expect(mineSection(for: makePR(isDraft: true, ciState: .failure)) == .drafts)
    }

    @Test func draftWithChangesRequestedIsStillDraft() {
        #expect(mineSection(for: makePR(isDraft: true, reviewDecision: .changesRequested)) == .drafts)
    }

    @Test func approvedWithGreenCIWaitsOnOthers() {
        #expect(mineSection(for: makePR(reviewDecision: .approved, ciState: .success)) == .waitingOnOthers)
    }

    @Test func pendingCIWaitsOnOthers() {
        #expect(mineSection(for: makePR(ciState: .pending)) == .waitingOnOthers)
    }

    @Test func groupsMineFixtureIntoSectionsSortedByRecency() throws {
        let prs = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let groups = groupMine(prs)
        #expect(groups.needsYou.map(\.number) == [101])
        #expect(groups.waitingOnOthers.map(\.number) == [102, 103])
        #expect(groups.drafts.map(\.number) == [104, 105])
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

    @Test func badgeCountsNeedsYouPlusDirect() throws {
        let mine = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let direct = try parseSearchResponse(fixture("search-direct.json")).pullRequests
        #expect(computeBadgeCount(mine: mine, direct: direct) == 1 + 3)
    }

    @Test func badgeIgnoresDraftsAndThreads() {
        let mine = [
            makePR(number: 1, isDraft: true, ciState: .failure),
            makePR(number: 2, reviewDecision: .approved, ciState: .success, unresolvedThreads: 9),
        ]
        #expect(computeBadgeCount(mine: mine, direct: []) == 0)
    }
}
