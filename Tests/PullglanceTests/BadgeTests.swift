import Foundation
import Testing
@testable import Pullglance

@Suite struct BadgeTests {
    @Test func singleModeShowsTheTotalOrNothing() {
        #expect(badgeText(first: 5, second: nil, mode: .single) == "5")
        #expect(badgeText(first: 0, second: nil, mode: .single) == nil)
        // A second count is ignored in single mode.
        #expect(badgeText(first: 3, second: 9, mode: .single) == "3")
    }

    @Test func dualModeKeepsBothPositionsEvenWhenOneIsZero() {
        #expect(badgeText(first: 2, second: 26, mode: .dual) == "2 · 26")
        #expect(badgeText(first: 2, second: 0, mode: .dual) == "2 · 0")
        #expect(badgeText(first: 0, second: 26, mode: .dual) == "0 · 26")
        #expect(badgeText(first: 0, second: 0, mode: .dual) == nil)
    }
}

@MainActor
@Suite struct BadgeStoreTests {
    private func gh() async throws -> FakeGH {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        await gh.set(.success(try fixture("search-team.json")), for: SearchQuery.viaTeam)
        return gh
    }

    @Test func defaultsToOneNumberAndEachModeHasItsOwnDefaults() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        #expect(store.badgeMode == .single)
        #expect(store.badgeSections == Section.defaultBadge)
        #expect(store.dualBadgeFirst == [.needsAction, .readyToMerge])
        #expect(store.dualBadgeSecond == [.needsYourReview])
        await store.refresh()
        #expect(store.badgeSecondCount == nil)
        #expect(store.badgeText == "\(store.badgeCount!)")
    }

    @Test func aSectionCountsTowardOneNumberAtMostAndPersists() async throws {
        let defaults = testDefaults()
        let store = PRStore(client: try await gh(), defaults: defaults, now: { Date() })
        #expect(store.badgeSlot(for: .needsYourReview) == .second)
        store.setBadgeSlot(.first, for: .needsYourReview)
        #expect(store.badgeSlot(for: .needsYourReview) == .first)
        #expect(!store.dualBadgeSecond.contains(.needsYourReview))
        store.setBadgeSlot(nil, for: .needsYourReview)
        #expect(store.badgeSlot(for: .needsYourReview) == nil)
        store.setBadgeSlot(.second, for: .drafts)
        store.badgeMode = .dual
        let reloaded = PRStore(client: try await gh(), defaults: defaults, now: { Date() })
        #expect(reloaded.badgeMode == .dual)
        #expect(reloaded.dualBadgeFirst == [.needsAction, .readyToMerge])
        #expect(reloaded.dualBadgeSecond == [.drafts])
    }

    /// Switching modes must bring back what was configured for that mode; the two never share a set.
    @Test func eachModeKeepsItsOwnConfiguration() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        store.badgeSections = [.drafts]
        store.setBadgeSlot(.second, for: .needsAction)
        #expect(store.badgeSections == [.drafts])
        #expect(store.dualBadgeFirst == [.readyToMerge])
        #expect(store.dualBadgeSecond == [.needsYourReview, .needsAction])
        store.badgeMode = .dual
        store.badgeMode = .single
        #expect(store.badgeSections == [.drafts])
        #expect(store.dualBadgeSecond == [.needsYourReview, .needsAction])
    }

    @Test func dualModeCountsEachSetSeparately() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        store.badgeMode = .dual
        store.setBadgeSlot(nil, for: .needsAction)
        await store.refresh()
        let ready = store.mineGroups.readyToMerge.count
        let direct = store.directList.count
        #expect(ready > 0 && direct > 0)
        #expect(store.badgeCount == ready)
        #expect(store.badgeSecondCount == direct)
        #expect(store.badgeText == "\(ready) · \(direct)")
        store.badgeMode = .single
        #expect(store.badgeSecondCount == nil)
        #expect(store.badgeCount == computeBadgeCount(mine: store.mine.value, direct: store.direct.value, viaTeam: [], counting: Section.defaultBadge))
    }

    @Test func resetToDefaultGoesBackToOneNumber() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        store.badgeMode = .dual
        store.setBadgeSlot(.second, for: .drafts)
        store.badgeSections = [.drafts]
        store.resetSectionsToDefault()
        #expect(store.badgeMode == .single)
        #expect(store.badgeSections == Section.defaultBadge)
        #expect(store.dualBadgeFirst == [.needsAction, .readyToMerge])
        #expect(store.dualBadgeSecond == [.needsYourReview])
    }
}
