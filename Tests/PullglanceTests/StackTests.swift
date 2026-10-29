import Foundation
import Testing
@testable import Pullglance

@Suite struct StackDecodingTests {
    @Test func decodesAStackEntry() throws {
        let entry = stackEntryJSON(size: 4, position: 2, members: [(1, 430, "Base", "MERGED", false), (2, 431, "Auth", "OPEN", false), (3, 432, "API", "OPEN", false), (4, 433, "Account", "OPEN", true)])
        let page = try parseSearchResponse(envelope(nodes: [node(number: 431, ci: "SUCCESS", prExtra: entry)]))
        let stack = try #require(page.pullRequests[0].stack)
        #expect(stack == PullRequestStack(number: 7, size: 4, baseRefName: "main", position: 2, members: [
            StackMember(position: 1, number: 430, title: "Base", state: .merged),
            StackMember(position: 2, number: 431, title: "Auth", state: .open),
            StackMember(position: 3, number: 432, title: "API", state: .open),
            StackMember(position: 4, number: 433, title: "Account", state: .draft),
        ]))
        #expect(page.pullRequests[0].stackKey == StackKey(repo: "acme/web", number: 7))
    }

    @Test func membersComeInPositionOrderWhateverGitHubSends() throws {
        let entry = stackEntryJSON(size: 2, position: 1, members: [(2, 432, "API", "OPEN", false), (1, 431, "Auth", "OPEN", false)])
        let page = try parseSearchResponse(envelope(nodes: [node(number: 431, ci: nil, prExtra: entry)]))
        #expect(page.pullRequests[0].stack?.members.map(\.position) == [1, 2])
    }

    @Test func noStackEntryIsNoStack() throws {
        #expect(try parseSearchResponse(envelope(nodes: [node(number: 1, ci: nil)])).pullRequests[0].stack == nil)
        #expect(try parseSearchResponse(envelope(nodes: [node(number: 1, ci: nil, prExtra: "\"stackEntry\":null")])).pullRequests[0].stack == nil)
    }

    /// A `stackEntry` without its stack, or without a position: GitHub's inconsistency, not a failed page.
    @Test func stackEntryWithoutAStackDecodesAsNoStack() throws {
        let page = try parseSearchResponse(envelope(nodes: [node(number: 1, ci: nil, prExtra: "\"stackEntry\":{\"position\":1,\"stack\":null}")]))
        #expect(page.pullRequests.count == 1)
        #expect(page.pullRequests[0].stack == nil)
    }

    @Test func theSinglePullRequestQueryCarriesTheStackToo() throws {
        let entry = stackEntryJSON(size: 1, position: 1, members: [(1, 9, "Only", "OPEN", false)])
        guard case .open(let pr) = try parsePullRequestResponse(pullRequestEnvelope(node(number: 9, ci: nil, prExtra: entry))) else { Issue.record("expected open"); return }
        #expect(pr.stack?.size == 1)
    }

    @Test func bothQueriesAskForTheStack() {
        for text in [GHClient.searchQuery, GHClient.pullRequestQuery] {
            #expect(text.contains("stackEntry { position stack { number size baseRefName entries(first: 30)"))
        }
    }
}
