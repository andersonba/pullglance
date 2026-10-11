import Foundation
import Testing
@testable import Pullglance

@Suite struct ManualOrderTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func knownIDsFollowTheSavedOrderAndNewcomersComeFirst() {
        let a = makePR(repo: "acme/web", number: 1, updatedAt: t0.addingTimeInterval(10))
        let b = makePR(repo: "acme/web", number: 2, updatedAt: t0.addingTimeInterval(20))
        let c = makePR(repo: "acme/web", number: 3, updatedAt: t0.addingTimeInterval(30))
        // Input is newest first, as the sections are. c is unknown to the saved order.
        let ordered = applyManualOrder([c, b, a], ids: [a.id, "acme/web#99", b.id])
        #expect(ordered.map(\.number) == [3, 1, 2])
    }

    @Test func emptyOrderLeavesTheListAlone() {
        let a = makePR(repo: "acme/web", number: 1, updatedAt: t0)
        let b = makePR(repo: "acme/web", number: 2, updatedAt: t0.addingTimeInterval(5))
        #expect(applyManualOrder([b, a], ids: []).map(\.number) == [2, 1])
    }

    @Test func pruningDropsIDsNoLongerAroundAndEmptySections() {
        let orders = ["needsAction": ["acme/web#1", "acme/web#2"], "drafts": ["acme/web#9"]]
        let pruned = pruneManualOrders(orders, keeping: ["acme/web#2"])
        #expect(pruned == ["needsAction": ["acme/web#2"]])
    }
}

@MainActor
@Suite struct ManualOrderStoreTests {
    private func gh() async throws -> FakeGH {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        return gh
    }

    @Test func aSavedOrderReordersTheSectionAndPersists() async throws {
        let defaults = testDefaults()
        let store = PRStore(client: try await gh(), defaults: defaults, now: { Date() })
        await store.refresh()
        let before = store.mineGroups.readyToMerge
        #expect(before.count >= 2)
        #expect(!store.isManuallyOrdered(.readyToMerge))
        store.setManualOrder(before.reversed().map(\.id), for: .readyToMerge)
        #expect(store.isManuallyOrdered(.readyToMerge))
        #expect(store.mineGroups.readyToMerge.map(\.id) == before.reversed().map(\.id))
        let reloaded = PRStore(client: try await gh(), defaults: defaults, now: { Date() })
        await reloaded.refresh()
        #expect(reloaded.mineGroups.readyToMerge.map(\.id) == before.reversed().map(\.id))
        reloaded.resetManualOrder(for: .readyToMerge)
        #expect(!reloaded.isManuallyOrdered(.readyToMerge))
        #expect(reloaded.mineGroups.readyToMerge.map(\.id) == before.map(\.id))
    }

    @Test func reviewListHonorsItsOwnOrder() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let before = store.directList
        #expect(before.count >= 2)
        store.setManualOrder(before.reversed().map(\.id), for: .needsYourReview)
        #expect(store.directList.map(\.id) == before.reversed().map(\.id))
    }

    @Test func idsThatLeftTheResultsArePrunedAfterARefresh() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let ids = store.mineGroups.readyToMerge.map(\.id)
        store.setManualOrder(["acme/gone#1"] + ids, for: .readyToMerge)
        store.setManualOrder(["acme/gone#2"], for: .drafts)
        await store.refresh()
        #expect(store.manualOrders[Section.readyToMerge.rawValue] == ids)
        #expect(store.manualOrders[Section.drafts.rawValue] == nil)
    }
}
