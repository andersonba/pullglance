import Testing
@testable import Pullglance

@Suite struct QuickFilterTests {
    @Test func mineChipsFollowVisibleSectionsWithCounts() throws {
        let prs = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let items = quickFilterItems(sections: [Section.needsAction, .readyToMerge, .waitingForReview, .drafts], visible: Set(Section.allCases), mine: groupMine(prs), directTotal: 3, teamTotal: nil)
        #expect(items.map(\.section) == [nil, .needsAction, .readyToMerge, .waitingForReview, .drafts])
        #expect(items.map(\.count) == [5, 1, 2, 0, 2])
    }

    @Test func hiddenSectionsHaveNoChip() throws {
        let prs = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let items = quickFilterItems(sections: [Section.needsAction, .readyToMerge, .waitingForReview, .drafts], visible: [.needsAction, .drafts], mine: groupMine(prs), directTotal: 3, teamTotal: nil)
        #expect(items.map(\.section) == [nil, .needsAction, .drafts])
        #expect(items.first?.count == 3)
    }

    @Test func reviewChipsUseTotalsAndHideUnknownTeamCount() {
        let items = quickFilterItems(sections: Section.reviewSections, visible: Set(Section.allCases), mine: MineGroups(), directTotal: 26, teamTotal: nil)
        #expect(items.map(\.section) == [nil, .needsYourReview, .needsTeamsReview])
        #expect(items.map(\.count) == [nil, 26, nil])
        let fetched = quickFilterItems(sections: Section.reviewSections, visible: Set(Section.allCases), mine: MineGroups(), directTotal: 26, teamTotal: 127)
        #expect(fetched.last?.count == 127)
    }

    @Test func chipsFollowCustomOrder() throws {
        let prs = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let items = quickFilterItems(sections: [.drafts, .needsAction, .readyToMerge, .waitingForReview], visible: Set(Section.allCases), mine: groupMine(prs), directTotal: 0, teamTotal: nil)
        #expect(items.map(\.section) == [nil, .drafts, .needsAction, .readyToMerge, .waitingForReview])
    }

    @Test func singleVisibleSectionNeedsNoChips() {
        let items = quickFilterItems(sections: Section.reviewSections, visible: [.needsYourReview], mine: MineGroups(), directTotal: 26, teamTotal: nil)
        #expect(items.isEmpty)
    }
}
