import Foundation
import Testing
@testable import Pullglance

@Suite struct RepoSearchDecodingTests {
    @Test func decodesRepositorySearch() throws {
        let body = """
        {"data":{"search":{"repositoryCount":2,"nodes":[
          {"nameWithOwner":"acme/payments-api","isArchived":false},
          {"nameWithOwner":"acme/paypal-sandbox","isArchived":true}
        ]}}}
        """
        let result = try parseRepoSearch(Data(body.utf8))
        #expect(result.total == 2)
        #expect(result.repos.map(\.fullName) == ["acme/payments-api", "acme/paypal-sandbox"])
        #expect(result.repos.last?.isArchived == true)
    }

    @Test func repoSearchQueryScopesToTheOwner() {
        #expect(RepoSearchQuery.string(owner: "acme", term: "pay") == "org:acme pay sort:updated")
        #expect(RepoSearchQuery.string(owner: "acme", term: "  Pay API ") == "org:acme Pay API sort:updated")
    }
}

@MainActor
@Suite struct RepoSearchStoreTests {
    private func gh() async throws -> FakeGH {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        return gh
    }

    @Test func remoteSearchGoesThroughTheClient() async throws {
        let gh = try await gh()
        await gh.setRepoSearch(.success(Data("""
        {"data":{"search":{"repositoryCount":1,"nodes":[{"nameWithOwner":"acme/payments-api","isArchived":false}]}}}
        """.utf8)), for: "org:acme pay sort:updated")
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        let result = await store.searchRepos(owner: "acme", term: "pay")
        #expect(result?.repos.map(\.fullName) == ["acme/payments-api"])
    }

}
