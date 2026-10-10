import Foundation
import Testing
@testable import Pullglance

@Suite struct OwnerFilterTests {
    @Test func noHiddenOwnersLeavesQueryUntouched() {
        #expect(SearchQuery.mine(hiding: []) == SearchQuery.mine)
        #expect(SearchQuery.direct(hiding: []) == SearchQuery.direct)
        #expect(SearchQuery.viaTeam(hiding: []) == SearchQuery.viaTeam)
    }

    @Test func hiddenOwnersBecomeNegatedUserQualifiersInStableOrder() {
        let q = SearchQuery.mine(hiding: ["globex", "acme"])
        #expect(q == SearchQuery.mine + " -user:acme -user:globex")
    }

    @Test func ownerLoginIsTheRepoPrefix() {
        #expect(makePR(repo: "acme/web").ownerLogin == "acme")
    }

    @Test func decodesViewerOrganizations() throws {
        let page = try parseSearchResponse(fixture("search-mine.json"))
        #expect(page.viewerOrganizations == ["acme", "globex"])
    }

    @Test func missingOrganizationsDecodeAsEmpty() throws {
        let page = try parseSearchResponse(envelope(nodes: [node(number: 1, ci: nil)]))
        #expect(page.viewerOrganizations.isEmpty)
    }
}

@MainActor
@Suite struct OwnerFilterStoreTests {
    private func gh() async throws -> FakeGH {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        return gh
    }

    @Test func knownOwnersUnionsViewerOrgsResultsAndHidden() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        await store.refresh()
        // viewer "octocat" + orgs acme, globex + owners seen in results (acme only in fixtures)
        #expect(store.knownOwners.map(\.login) == ["acme", "globex", "octocat"])
        #expect(store.knownOwners.first { $0.login == "acme" }?.openCount == 8)
        #expect(store.knownOwners.first { $0.login == "octocat" }?.isViewer == true)
    }

    @Test func hidingAnOwnerRefreshesWithFilteredQueriesAndBadgeFollows() async throws {
        let gh = try await gh()
        // The filtered search returns nothing, as GitHub would for a hidden org.
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.mine(hiding: ["acme"]))
        await gh.set(.success(envelope(nodes: [], issueCount: 0)), for: SearchQuery.direct(hiding: ["acme"]))
        let defaults = testDefaults()
        let store = PRStore(client: gh, defaults: defaults, now: { Date() })
        await store.refresh()
        #expect(store.badgeCount == 6)

        store.hiddenOwners = ["acme"]
        try await Task.sleep(for: .milliseconds(150))
        #expect(await gh.callCount(for: SearchQuery.mine(hiding: ["acme"])) == 1)
        #expect(store.badgeCount == 0)
        #expect(store.mine.total == 0)
        #expect(defaults.stringArray(forKey: PRStore.hiddenOwnersKey) == ["acme"])
        // Hidden owners stay listed so they can be re-enabled, even with no results.
        #expect(store.knownOwners.contains { $0.login == "acme" })
    }

    @Test func hiddenOwnersAreRestoredFromDefaults() async throws {
        let defaults = testDefaults()
        defaults.set(["acme"], forKey: PRStore.hiddenOwnersKey)
        let store = PRStore(client: try await gh(), defaults: defaults, now: { Date() })
        #expect(store.hiddenOwners == ["acme"])
    }
}
