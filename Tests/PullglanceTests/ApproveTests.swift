import Foundation
import Testing
@testable import Pullglance

@MainActor
@Suite struct ApproveTests {
    @Test func argumentsIncludeTheBodyOnlyWhenGiven() {
        let url = URL(string: "https://github.com/acme/web/pull/7")!
        #expect(GHClient.approveArguments(url: url, body: nil) == ["pr", "review", url.absoluteString, "--approve"])
        #expect(GHClient.approveArguments(url: url, body: "LGTM") == ["pr", "review", url.absoluteString, "--approve", "--body", "LGTM"])
    }

    @Test func approveTrimsTheBodyAndReportsSuccess() async {
        let gh = FakeGH()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        let pr = makePR(repo: "acme/web", number: 7)
        let result = await store.approve(pr, body: "  ship it \n")
        #expect(result == .success())
        #expect(await gh.approvals.map(\.body) == ["ship it"])
        let silent = await store.approve(pr, body: "   ")
        #expect(silent == .success())
        #expect(await gh.approvals.last?.body == nil)
    }

    @Test func approveSurfacesGitHubsRefusal() async {
        let gh = FakeGH()
        await gh.setApproveOutcome(.failure("GraphQL: Can not approve your own pull request (addPullRequestReview)"))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        let result = await store.approve(makePR(repo: "acme/web", number: 7), body: "")
        #expect(result == .failure("GraphQL: Can not approve your own pull request (addPullRequestReview)"))
    }
}
