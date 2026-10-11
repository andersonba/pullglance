import Foundation
import Testing
@testable import Pullglance

@Suite struct RepoFilterQueryTests {
    @Test func hiddenReposBecomeNegatedRepoQualifiers() {
        let q = SearchQuery.mine(hiding: ["acme"], repos: ["globex/site", "acme/docs"])
        #expect(q == SearchQuery.mine + " -user:acme -repo:acme/docs -repo:globex/site")
        #expect(SearchQuery.direct(hiding: [], repos: []) == SearchQuery.direct)
    }
}

@MainActor
@Suite struct RepoFilterStoreTests {
    private func gh() async throws -> FakeGH {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        return gh
    }





    @Test func quickRepoFilterNarrowsListsAndTabCountsButNotTheBadge() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(store.badgeCount == 6)
        #expect(store.availableRepos.map(\.fullName) == ["acme/api", "acme/cli", "acme/mobile", "acme/web"])
        store.quickRepoFilter = ["acme/web"]
        #expect(store.mineGroups.needsAction.map(\.number) == [101])
        #expect(store.mineGroups.drafts.map(\.number) == [104])
        #expect(store.mineGroups.readyToMerge.isEmpty)
        #expect(store.directList.isEmpty)
        #expect(store.mineTabCount == 2)
        #expect(store.reviewTabCount == 0)
        #expect(store.badgeCount == 6)
        store.quickRepoFilter = []
        #expect(store.mineTabCount == 5)
        #expect(store.reviewTabCount == 27)
    }
}

