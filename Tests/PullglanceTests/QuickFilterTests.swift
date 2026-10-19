import Testing
@testable import Pullglance

@Suite struct QuickFilterTests {
    @Test func mineChipsFollowVisibleSectionsWithCounts() throws {
        let prs = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let items = quickFilterItems(sections: [Section.needsAction, .readyToMerge, .waitingForReview, .drafts], visible: Set(Section.allCases), mine: groupMine(prs), directTotal: 3, teamTotal: nil, snoozedReview: 0)
        #expect(items.map(\.section) == [nil, .needsAction, .readyToMerge, .waitingForReview, .drafts])
        #expect(items.map(\.count) == [5, 1, 2, 0, 2])
    }

    @Test func hiddenSectionsHaveNoChip() throws {
        let prs = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let items = quickFilterItems(sections: [Section.needsAction, .readyToMerge, .waitingForReview, .drafts], visible: [.needsAction, .drafts], mine: groupMine(prs), directTotal: 3, teamTotal: nil, snoozedReview: 0)
        #expect(items.map(\.section) == [nil, .needsAction, .drafts])
        #expect(items.first?.count == 3)
    }

    @Test func reviewChipsUseTotalsAndHideUnknownTeamCount() {
        let items = quickFilterItems(sections: Section.reviewSections, visible: Set(Section.allCases), mine: MineGroups(), directTotal: 26, teamTotal: nil, snoozedReview: 0)
        #expect(items.map(\.section) == [nil, .needsYourReview, .needsTeamsReview])
        #expect(items.map(\.count) == [nil, 26, nil])
        let fetched = quickFilterItems(sections: Section.reviewSections, visible: Set(Section.allCases), mine: MineGroups(), directTotal: 26, teamTotal: 127, snoozedReview: 0)
        #expect(fetched.last?.count == 127)
    }

    @Test func chipsFollowCustomOrder() throws {
        let prs = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let items = quickFilterItems(sections: [.drafts, .needsAction, .readyToMerge, .waitingForReview], visible: Set(Section.allCases), mine: groupMine(prs), directTotal: 0, teamTotal: nil, snoozedReview: 0)
        #expect(items.map(\.section) == [nil, .drafts, .needsAction, .readyToMerge, .waitingForReview])
    }

    @Test func snoozedChipComesLastOnlyWhenSomethingIsSnoozed() throws {
        let prs = try parseSearchResponse(fixture("search-mine.json")).pullRequests
        let mineSections = Section.allCases.filter { $0.tab == .mine }
        let none = quickFilterItems(sections: mineSections, visible: Set(Section.allCases), mine: groupMine(prs), directTotal: 0, teamTotal: nil, snoozedReview: 0)
        #expect(none.map(\.section).contains(.snoozedMine) == false)
        let some = quickFilterItems(sections: mineSections, visible: Set(Section.allCases), mine: groupMine(prs, dormant: ["acme/api#102"]), directTotal: 0, teamTotal: nil, snoozedReview: 0)
        #expect(some.last == QuickFilterItem(section: .snoozedMine, count: 1))
        #expect(some.first?.count == 4, "the All chip does not count snoozed rows")
        let hidden = quickFilterItems(sections: mineSections, visible: Set(Section.allCases).subtracting([.snoozedMine]), mine: groupMine(prs, dormant: ["acme/api#102"]), directTotal: 0, teamTotal: nil, snoozedReview: 0)
        #expect(hidden.map(\.section).contains(.snoozedMine) == false)
    }

    @Test func reviewTabGetsItsOwnSnoozedChip() {
        let items = quickFilterItems(sections: Section.reviewSections, visible: Set(Section.allCases), mine: MineGroups(), directTotal: 26, teamTotal: nil, snoozedReview: 2)
        #expect(items.last == QuickFilterItem(section: .snoozedReview, count: 2))
    }

    @Test func singleVisibleSectionNeedsNoChips() {
        let items = quickFilterItems(sections: Section.reviewSections, visible: [.needsYourReview], mine: MineGroups(), directTotal: 26, teamTotal: nil, snoozedReview: 0)
        #expect(items.isEmpty)
    }
}

@Suite struct AssignedQuickFilterTests {
    @Test func assignedChipFollowsTheCount() {
        let prs = [makePR(repo: "acme/web", number: 1), makePR(repo: "acme/web", number: 2)]
        let base = quickFilterItems(sections: [Section.needsAction, .readyToMerge, .waitingForReview, .drafts], visible: Set(Section.allCases), mine: groupMine(prs), directTotal: 0, teamTotal: nil, snoozedReview: 0)
        #expect(!base.contains { $0.section == .assignedMine })
        let withAssigned = quickFilterItems(sections: [Section.needsAction, .readyToMerge, .waitingForReview, .drafts], visible: Set(Section.allCases), mine: groupMine(prs), directTotal: 0, teamTotal: nil, snoozedReview: 0, assigned: 1)
        let chip = withAssigned.first { $0.section == .assignedMine }
        #expect(chip?.count == 1)
        #expect(withAssigned.last?.section == .assignedMine)   // after the sections, before nothing (no snoozed)
        #expect(Section.assignedMine.isFixed)                   // never in the reorderable list, never a badge section
        #expect(!Section.reorderable(in: .mine).contains(.assignedMine))
    }
}
