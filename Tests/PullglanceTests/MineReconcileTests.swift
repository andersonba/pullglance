import Foundation
import Testing
@testable import Pullglance

/// One `pull-request` batch response: alias → node from `node(...)` (or nil for a repository that did not
/// resolve), with the pull request state.
func batchEnvelope(_ aliases: [(alias: String, node: String?, state: String)]) -> Data {
    let entries = aliases.map { entry -> String in
        guard let node = entry.node else { return "\"\(entry.alias)\":null" }
        let body = "{\"state\":\"" + entry.state + "\"," + node.dropFirst()
        return "\"\(entry.alias)\":{\"pullRequest\":" + body + "}"
    }
    return Data(("{\"data\":{" + entries.joined(separator: ",") + "}}").utf8)
}

/// GitHub's search index lags the repository by minutes; the user's own pull requests are looked up
/// directly after every search so an approval or a green check shows up at once.
@MainActor
@Suite struct MineReconcileTests {
    private func gh(mine: [String]) async -> FakeGH {
        let gh = FakeGH()
        await gh.set(.success(envelope(nodes: mine)), for: SearchQuery.mine)
        await gh.set(.success(envelope(nodes: [])), for: SearchQuery.direct)
        return gh
    }

    @Test func directLookupOverridesTheSearchIndex() async throws {
        let gh = await gh(mine: [node(number: 7, ci: "SUCCESS", decision: "REVIEW_REQUIRED"), node(number: 8, ci: "PENDING")])
        await gh.setPullRequests(.success(batchEnvelope([
            ("p0", node(number: 7, ci: "SUCCESS", decision: "APPROVED"), "OPEN"),
            ("p1", node(number: 8, ci: "PENDING"), "OPEN"),
        ])))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(store.mineGroups.readyToMerge.map(\.number) == [7])
        #expect(store.mineGroups.waitingForReview.map(\.number) == [8])
        let lookups = await gh.batchLookups
        #expect(lookups == [[PullRequestRef(owner: "acme", name: "web", number: 7), PullRequestRef(owner: "acme", name: "web", number: 8)]])
    }

    @Test func failedLookupKeepsTheSearchResult() async throws {
        let gh = await gh(mine: [node(number: 7, ci: "SUCCESS", decision: "REVIEW_REQUIRED")])
        await gh.setPullRequests(.failure("boom"))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(store.mineGroups.waitingForReview.map(\.number) == [7])
        #expect(store.phase != .idle)
        #expect(store.blockingError == nil)
    }

    @Test func closedOrMissingInTheLookupLeavesTheList() async throws {
        let gh = await gh(mine: [node(number: 7, ci: "SUCCESS"), node(number: 8, ci: "SUCCESS"), node(number: 9, ci: "SUCCESS")])
        await gh.setPullRequests(.success(batchEnvelope([
            ("p0", node(number: 7, ci: "SUCCESS"), "MERGED"),
            ("p1", nil, "OPEN"),
            ("p2", node(number: 9, ci: "SUCCESS"), "OPEN"),
        ])))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(store.mine.value.map(\.number) == [9])
    }

    @Test func nullAliasWithAnUnrelatedErrorKeepsThePullRequest() async throws {
        let gh = await gh(mine: [node(number: 7, ci: "SUCCESS")])
        let body = "{\"data\":{\"p0\":null},\"errors\":[{\"message\":\"Something went wrong while executing your query.\",\"path\":[\"p0\"]}]}"
        await gh.setPullRequests(.success(Data(body.utf8)))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(store.mine.value.map(\.number) == [7])
    }

    @Test func noOwnPullRequestsMeansNoLookup() async throws {
        let gh = await gh(mine: [])
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(await gh.batchLookups.isEmpty)
    }
}

@Suite struct PullRequestsBatchQueryTests {
    @Test func aliasesOnePullRequestPerRepositoryAndNumber() {
        let query = GHClient.pullRequestsQuery([PullRequestRef(owner: "acme", name: "web", number: 7), PullRequestRef(owner: "globex", name: "api.v2", number: 12)])
        #expect(query.contains("p0: repository(owner: \"acme\", name: \"web\") { pullRequest(number: 7) { ...PullRequestFields } }"))
        #expect(query.contains("p1: repository(owner: \"globex\", name: \"api.v2\") { pullRequest(number: 12) { ...PullRequestFields } }"))
        #expect(query.contains("fragment PullRequestFields on PullRequest"))
        #expect(query.contains("$withMerge: Boolean!"))
    }

    @Test func refusesNamesThatCouldBreakOutOfTheQuery() {
        #expect(PullRequestRef(repo: "acme/web", number: 1) == PullRequestRef(owner: "acme", name: "web", number: 1))
        #expect(PullRequestRef(repo: "acme\"/web", number: 1) == nil)
        #expect(PullRequestRef(repo: "noslash", number: 1) == nil)
    }
}
