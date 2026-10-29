import Foundation
import Testing
@testable import Pullglance

/// The stack lens: next to the repository and author ones, same rules, plus an order by position.
@MainActor @Suite struct StackFilterTests {
    /// Two stacks in acme/web (#7: 431 ready, 432 needs action, 433 draft; #8: 440 waiting) and a loose 412.
    private func gh() async throws -> FakeGH {
        let seven = { (pos: Int) in stackEntryJSON(number: 7, size: 3, position: pos, members: [(1, 431, "Auth", "OPEN", false), (2, 432, "API", "OPEN", false), (3, 433, "Account", "OPEN", true)]) }
        let eight = stackEntryJSON(number: 8, size: 1, position: 1, members: [(1, 440, "Other", "OPEN", false)])
        let gh = FakeGH()
        await gh.set(.success(envelope(nodes: [
            node(number: 432, ci: "FAILURE", decision: "CHANGES_REQUESTED", updatedAt: "2026-10-10T12:00:00Z", prExtra: seven(2)),
            node(number: 433, ci: nil, draft: true, updatedAt: "2026-10-10T13:00:00Z", prExtra: seven(3)),
            node(number: 431, ci: "SUCCESS", decision: "APPROVED", updatedAt: "2026-10-10T11:00:00Z", prExtra: seven(1)),
            node(number: 440, ci: "SUCCESS", decision: "REVIEW_REQUIRED", updatedAt: "2026-10-10T14:00:00Z", prExtra: eight),
            node(number: 412, ci: "FAILURE", updatedAt: "2026-10-10T15:00:00Z"),
        ])), for: SearchQuery.mine)
        await gh.set(.success(envelope(nodes: [])), for: SearchQuery.direct)
        return gh
    }

    private func store() async throws -> PRStore {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        await store.refresh()
        return store
    }

    private func pr(_ store: PRStore, _ n: Int) throws -> PullRequest { try #require(store.mine.value.first { $0.number == n }) }

    @Test func togglingAStackNarrowsTheListsAndKeepsTheSections() async throws {
        let store = try await store()
        let badge = store.badgeCount
        store.toggleQuickStack(try pr(store, 432))
        #expect(store.quickStackFilter == StackKey(repo: "acme/web", number: 7))
        #expect(store.hasQuickFilter)
        #expect(store.mineGroups.readyToMerge.map(\.number) == [431])
        #expect(store.mineGroups.needsAction.map(\.number) == [432])
        #expect(store.mineGroups.drafts.map(\.number) == [433])
        #expect(store.mineGroups.waitingForReview.isEmpty)
        #expect(store.badgeCount == badge, "the badge ignores lenses")
        store.toggleQuickStack(try pr(store, 433))
        #expect(store.quickStackFilter == nil, "the same stack again clears it")
        store.toggleQuickStack(try pr(store, 412))
        #expect(store.quickStackFilter == nil, "a row without a stack toggles nothing")
    }

    @Test func anotherStackReplacesTheFilter() async throws {
        let store = try await store()
        store.toggleQuickStack(try pr(store, 431))
        store.toggleQuickStack(try pr(store, 440))
        #expect(store.quickStackFilter == StackKey(repo: "acme/web", number: 8))
        #expect(store.mineGroups.waitingForReview.map(\.number) == [440])
        #expect(store.mineGroups.readyToMerge.isEmpty)
    }

    /// Under the lens a section lists the stack by position; recency (the Mine default) steps aside, a
    /// hand order does not.
    @Test func underTheLensASectionIsOrderedByPosition() async throws {
        // Two members of one stack in one section, both red CI: Needs your action.
        let gh = FakeGH()
        let seven = { (pos: Int) in stackEntryJSON(number: 7, size: 2, position: pos, members: [(1, 431, "Auth", "OPEN", false), (2, 432, "API", "OPEN", false)]) }
        await gh.set(.success(envelope(nodes: [
            node(number: 432, ci: "FAILURE", updatedAt: "2026-10-10T12:00:00Z", prExtra: seven(2)),
            node(number: 431, ci: "FAILURE", updatedAt: "2026-10-10T11:00:00Z", prExtra: seven(1)),
        ])), for: SearchQuery.mine)
        await gh.set(.success(envelope(nodes: [])), for: SearchQuery.direct)
        let s = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await s.refresh()
        #expect(s.mineGroups.needsAction.map(\.number) == [432, 431], "newest first without the lens")
        s.toggleQuickStack(try #require(s.mine.value.first { $0.number == 431 }))
        #expect(s.mineGroups.needsAction.map(\.number) == [431, 432], "by position with it")
        s.setManualOrder(["acme/web#432", "acme/web#431"], for: .needsAction)
        #expect(s.mineGroups.needsAction.map(\.number) == [432, 431], "a hand order is left alone")
    }

    @Test func stackFilterSurvivesARefreshThatEmptiesIt() async throws {
        let gh = try await gh()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        store.toggleQuickStack(try pr(store, 431))
        await gh.set(.success(envelope(nodes: [node(number: 412, ci: "FAILURE")])), for: SearchQuery.mine)
        await store.refresh()
        #expect(store.quickStackFilter != nil)
        #expect(store.mineTabCount == 0)
        store.quickStackFilter = nil
        #expect(store.mineTabCount == 1)
    }

    @Test func stackFilterComposesWithTheRepositoryLens() async throws {
        let store = try await store()
        store.toggleQuickStack(try pr(store, 431))
        store.quickRepoFilter = ["acme/api"]
        #expect(store.mineTabCount == 0)
        #expect(store.hasQuickFilter)
        store.quickRepoFilter = []
        #expect(store.mineTabCount == 3)
    }
}
