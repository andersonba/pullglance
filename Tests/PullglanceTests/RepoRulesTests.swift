import Foundation
import Testing
@testable import Pullglance

@MainActor
@Suite struct RepoRulesTests {
    private func gh() async throws -> FakeGH {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        return gh
    }

    @Test func ownersDefaultToAllExceptNothing() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(store.repoRule(for: "acme") == RepoRule(mode: .allExcept, repos: []))
        #expect(store.knownOwners.first { $0.login == "acme" }?.rule == RepoRule(mode: .allExcept, repos: []))
    }

    @Test func exceptModeExcludesInTheSearchAndPersists() async throws {
        let gh = try await gh()
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.mine(hiding: [], repos: ["acme/web"]))
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.direct(hiding: [], repos: ["acme/web"]))
        let defaults = testDefaults()
        let store = PRStore(client: gh, defaults: defaults, now: { Date() })
        await store.refresh()
        store.setRule(RepoRule(mode: .allExcept, repos: ["acme/web"]), for: "acme")
        try await Task.sleep(for: .milliseconds(150))
        #expect(await gh.callCount(for: SearchQuery.mine(hiding: [], repos: ["acme/web"])) == 1)
        let reloaded = PRStore(client: gh, defaults: defaults, now: { Date() })
        #expect(reloaded.repoRule(for: "acme") == RepoRule(mode: .allExcept, repos: ["acme/web"]))
    }

    @Test func onlyModeFiltersInTheAppAndTheBadgeFollows() async throws {
        let gh = try await gh()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(store.badgeCount == 6)
        store.setRule(RepoRule(mode: .only, repos: ["acme/web"]), for: "acme")
        #expect(store.mineGroups.needsAction.map(\.number) == [101])
        #expect(store.mineGroups.drafts.map(\.number) == [104])
        #expect(store.directList.isEmpty)
        #expect(store.mineTabCount == 2)
        #expect(store.reviewTabCount == 0)
        #expect(store.badgeCount == 1)
        #expect(store.availableRepos.map(\.fullName) == ["acme/web"])
        // Only mode never touches the searches.
        await store.refresh()
        #expect(await gh.calls.allSatisfy { $0 == SearchQuery.mine || $0 == SearchQuery.direct })
    }

    @Test func aRuleWithoutReposFallsBackToAllRepositories() async throws {
        let gh = try await gh()
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.mine(hiding: [], repos: ["acme/web"]))
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.direct(hiding: [], repos: ["acme/web"]))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        store.setRule(RepoRule(mode: .only, repos: []), for: "acme")
        #expect(store.repoRule(for: "acme") == .none)
        #expect(store.mineTabCount == 5)
        store.setRule(RepoRule(mode: .only, repos: ["acme/web"]), for: "acme")
        store.removeRepo("acme/web", from: "acme")
        #expect(store.repoRule(for: "acme") == .none, "removing the last repo of an Only rule goes back to all")
        store.setRule(RepoRule(mode: .allExcept, repos: ["acme/web"]), for: "acme")
        store.removeRepo("acme/web", from: "acme")
        #expect(store.repoRule(for: "acme") == .none)
    }

    @Test func recentReposComeFromLoadedResultsWithCounts() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(store.recentRepos(for: "acme").map { "\($0.fullName):\($0.openCount)" } == ["acme/api:3", "acme/cli:1", "acme/mobile:2", "acme/web:2"])
        #expect(store.recentRepos(for: "globex").isEmpty)
    }

    @Test func legacyHiddenReposMigrateIntoExceptRules() async throws {
        let defaults = testDefaults()
        defaults.set(["acme/bots", "globex/old"], forKey: "hiddenRepos")
        let store = PRStore(client: try await gh(), defaults: defaults, now: { Date() })
        #expect(store.repoRule(for: "acme") == RepoRule(mode: .allExcept, repos: ["acme/bots"]))
        #expect(store.repoRule(for: "globex") == RepoRule(mode: .allExcept, repos: ["globex/old"]))
        #expect(defaults.object(forKey: "hiddenRepos") == nil)
    }
}
