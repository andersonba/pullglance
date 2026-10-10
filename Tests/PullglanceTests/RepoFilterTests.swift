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

    @Test func knownReposAreGroupedUnderTheirOwnerWithCounts() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let acme = try #require(store.knownOwners.first { $0.login == "acme" })
        #expect(acme.repos.map(\.fullName) == ["acme/api", "acme/cli", "acme/mobile", "acme/web"])
        #expect(acme.repos.first { $0.fullName == "acme/web" }?.openCount == 2)
        #expect(acme.hiddenRepoCount == 0)
    }

    @Test func hidingARepoRefreshesWithTheRepoExcludedAndPersists() async throws {
        let gh = try await gh()
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.mine(hiding: [], repos: ["acme/web"]))
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.direct(hiding: [], repos: ["acme/web"]))
        let defaults = testDefaults()
        let store = PRStore(client: gh, defaults: defaults, now: { Date() })
        await store.refresh()
        store.hiddenRepos = ["acme/web"]
        try await Task.sleep(for: .milliseconds(150))
        #expect(await gh.callCount(for: SearchQuery.mine(hiding: [], repos: ["acme/web"])) == 1)
        #expect(defaults.stringArray(forKey: PRStore.hiddenReposKey) == ["acme/web"])
        // Still listed under its owner so it can be shown again, flagged hidden.
        let acme = try #require(store.knownOwners.first { $0.login == "acme" })
        #expect(acme.repos.contains { $0.fullName == "acme/web" && $0.isHidden })
        #expect(acme.hiddenRepoCount == 1)
        let reloaded = PRStore(client: gh, defaults: defaults, now: { Date() })
        #expect(reloaded.hiddenRepos == ["acme/web"])
    }

    @Test func teamOnlyReposAreListedOnlyWhileTheTeamSectionIsInUse() async throws {
        let gh = try await gh()
        await gh.set(.success(try fixture("search-team.json")), for: SearchQuery.viaTeam)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        store.isViaTeamExpanded = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.availableRepos.contains { $0.fullName == "acme/tools" })
        store.isViaTeamExpanded = false
        #expect(store.availableRepos.contains { $0.fullName == "acme/tools" } == false)
        #expect(store.knownOwners.first { $0.login == "acme" }?.repos.contains { $0.fullName == "acme/tools" } == false)
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
