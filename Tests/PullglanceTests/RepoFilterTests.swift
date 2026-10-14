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

    /// "What did alice ask me to review": the author lens, next to the repository one, same rules.
    @Test func quickAuthorFilterNarrowsListsAndTabCountsButNotTheBadge() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        let nodes = [
            node(number: 1, ci: "SUCCESS", author: "alice"),
            node(number: 2, ci: "SUCCESS", author: "bob"),
            node(number: 3, ci: "SUCCESS", author: "alice", repo: "acme/api"),
        ]
        await gh.set(.success(envelope(nodes: nodes, issueCount: 3)), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let badge = store.badgeCount
        let authors = store.availableAuthors.filter { $0.login != "octocat" }
        #expect(authors.map(\.login) == ["alice", "bob"], "most requests first, then by name")
        #expect(authors.first?.count == 2)
        #expect(authors.first?.avatarURL?.absoluteString == "https://example.com/alice.png")
        store.quickAuthorFilter = ["alice"]
        #expect(store.directList.map(\.number).sorted() == [1, 3])
        #expect(store.reviewTabCount == 2)
        #expect(store.badgeCount == badge)
        // Each list counts under the other lens: with alice chosen, repositories show her pull requests only.
        #expect(store.availableRepos.map { "\($0.fullName) \($0.openCount)" } == ["acme/api 1", "acme/web 1"])
        store.quickRepoFilter = ["acme/api"]
        #expect(store.availableAuthors.filter { $0.login != "octocat" }.map { "\($0.login) \($0.count)" } == ["alice 1"], "bob has nothing in that repository")
        store.quickRepoFilter = []
        // The two lenses stack.
        store.quickRepoFilter = ["acme/api"]
        #expect(store.directList.map(\.number) == [3])
        store.quickRepoFilter = []
        store.quickAuthorFilter = []
        #expect(store.reviewTabCount == 3)
    }

    /// A click on a row's avatar: that person only; again on the same person: everyone. Another person replaces.
    @Test func avatarClickTogglesASingleAuthor() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        store.toggleQuickAuthor("alice")
        #expect(store.quickAuthorFilter == ["alice"])
        store.toggleQuickAuthor("bob")
        #expect(store.quickAuthorFilter == ["bob"])
        store.quickAuthorFilter = ["alice", "bob"]
        store.toggleQuickAuthor("bob")
        #expect(store.quickAuthorFilter == ["bob"], "from a set, the click narrows to that person")
        store.toggleQuickAuthor("bob")
        #expect(store.quickAuthorFilter.isEmpty)
    }

    /// Same gesture on the repository name in the row.
    @Test func repoNameClickTogglesASingleRepository() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        store.toggleQuickRepo("acme/web")
        #expect(store.quickRepoFilter == ["acme/web"])
        store.toggleQuickRepo("acme/api")
        #expect(store.quickRepoFilter == ["acme/api"])
        store.toggleQuickRepo("acme/api")
        #expect(store.quickRepoFilter.isEmpty)
    }
}

