import Foundation
import Testing
@testable import Pullglance

@Suite struct DecodingTests {
    @Test func decodesMineFixture() throws {
        let page = try parseSearchResponse(fixture("search-mine.json"))
        #expect(page.issueCount == 5)
        #expect(page.pullRequests.count == 5)
        #expect(page.viewerLogin == "octocat")
        #expect(page.errorMessages.isEmpty)

        let pr = try #require(page.pullRequests.first { $0.number == 101 })
        #expect(pr.repo == "acme/web")
        #expect(pr.id == "acme/web#101")
        #expect(pr.url.absoluteString == "https://github.com/acme/web/pull/101")
        #expect(pr.checksURL.absoluteString == "https://github.com/acme/web/pull/101/checks")
        #expect(pr.isDraft == false)
        #expect(pr.author == "octocat")
        #expect(pr.reviewDecision == .changesRequested)
        #expect(pr.ciState == .failure)
        #expect(pr.unresolvedThreads == 2)
        #expect(pr.requestedTeams.isEmpty)
    }

    @Test func parsesISO8601UpdatedAt() throws {
        let page = try parseSearchResponse(fixture("search-mine.json"))
        let pr = try #require(page.pullRequests.first { $0.number == 102 })
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: pr.updatedAt)
        #expect(comps.year == 2026 && comps.month == 10 && comps.day == 10 && comps.hour == 13 && comps.minute == 50)
    }

    @Test func extractsTeamSlugsAndIgnoresUsers() throws {
        let page = try parseSearchResponse(fixture("search-direct.json"))
        let pr = try #require(page.pullRequests.first { $0.number == 203 })
        #expect(pr.requestedTeams == ["platform"])
    }

    @Test(arguments: [
        ("SUCCESS", CIState.success), ("FAILURE", .failure), ("ERROR", .failure),
        ("PENDING", .pending), ("EXPECTED", .pending),
    ])
    func mapsRollupState(raw: String, expected: CIState) throws {
        let page = try parseSearchResponse(envelope(nodes: [node(number: 1, ci: raw)]))
        #expect(page.pullRequests.first?.ciState == expected)
    }

    @Test func decodesConflictsAndBehindBase() throws {
        let page = try parseSearchResponse(envelope(nodes: [
            node(number: 1, ci: "SUCCESS", mergeable: "CONFLICTING", mergeState: "DIRTY"),
            node(number: 2, ci: "SUCCESS", mergeable: "MERGEABLE", mergeState: "BEHIND"),
            node(number: 3, ci: "SUCCESS"),
        ]))
        #expect(page.pullRequests.map(\.hasConflicts) == [true, false, false])
        #expect(page.pullRequests.map(\.isBehindBase) == [false, true, false])
    }

    @Test func missingMergeFieldsDefaultToFalse() throws {
        let raw = node(number: 1, ci: "SUCCESS").replacingOccurrences(of: "\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",", with: "")
        let page = try parseSearchResponse(envelope(nodes: [raw]))
        #expect(page.pullRequests.first?.hasConflicts == false)
        #expect(page.pullRequests.first?.isBehindBase == false)
    }

    @Test func decodesAuthorAvatarAndToleratesItsAbsence() throws {
        let withAvatar = try parseSearchResponse(envelope(nodes: [node(number: 1, ci: nil)]))
        #expect(withAvatar.pullRequests.first?.authorAvatarURL?.absoluteString == "https://example.com/someone.png")
        let raw = node(number: 2, ci: nil).replacingOccurrences(of: ",\"avatarUrl\":\"https://example.com/someone.png\"", with: "")
        let without = try parseSearchResponse(envelope(nodes: [raw]))
        #expect(without.pullRequests.first?.authorAvatarURL == nil)
        #expect(try parseSearchResponse(fixture("search-partial.json")).pullRequests.first?.authorAvatarURL == nil)
    }

    @Test func nullRollupBecomesNone() throws {
        let page = try parseSearchResponse(envelope(nodes: [node(number: 1, ci: nil)]))
        #expect(page.pullRequests.first?.ciState == CIState.none)
    }

    @Test func unknownReviewDecisionBecomesNil() throws {
        let page = try parseSearchResponse(envelope(nodes: [node(number: 1, ci: "SUCCESS", decision: "SOMETHING_NEW")]))
        #expect(page.pullRequests.first?.reviewDecision == nil)
    }

    // Review Focus 1, 2 e 3
    @Test func partialResponseKeepsGoodNodesAndReportsErrors() throws {
        let page = try parseSearchResponse(fixture("search-partial.json"))
        #expect(page.issueCount == 4)
        #expect(page.pullRequests.count == 1)
        #expect(page.pullRequests[0].number == 401)
        #expect(page.pullRequests[0].author == "ghost")
        #expect(page.pullRequests[0].ciState == CIState.none)
        #expect(page.pullRequests[0].reviewDecision == nil)
        #expect(page.errorMessages == ["Resource protected by organization SAML enforcement."])
    }

    /// GitHub answers "Resource limits for this query exceeded" per node, with every node null and
    /// issueCount still set. That is a failed fetch, not an empty list.
    @Test func allNodesFailedWithErrorsIsNoData() throws {
        let body = """
        {"data":{"viewer":{"login":"octocat"},"search":{"issueCount":154,"nodes":[null,null,null]}},"errors":[{"message":"Resource limits for this query exceeded."},{"message":"Resource limits for this query exceeded."}]}
        """
        #expect(throws: DecodingFailure.noData(errors: ["Resource limits for this query exceeded.", "Resource limits for this query exceeded."])) {
            try parseSearchResponse(Data(body.utf8))
        }
    }

    @Test func genuinelyEmptyResultIsNotAnError() throws {
        let page = try parseSearchResponse(envelope(nodes: [], issueCount: 0))
        #expect(page.pullRequests.isEmpty)
    }

    @Test func errorsWithoutDataThrowNoData() throws {
        #expect(throws: DecodingFailure.noData(errors: ["Something went wrong while executing your query."])) {
            try parseSearchResponse(fixture("search-errors-only.json"))
        }
    }

    @Test func garbageThrowsMalformed() {
        #expect(throws: DecodingFailure.self) {
            try parseSearchResponse(Data("not json".utf8))
        }
    }
}
