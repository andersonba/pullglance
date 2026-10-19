import Foundation

/// One chip in the quick filter row. `section == nil` is "All".
struct QuickFilterItem: Equatable, Identifiable, Sendable {
    let section: Section?
    /// nil hides the number (e.g. team requests before they were fetched, or "All" on the review tab).
    let count: Int?
    var id: String { section?.rawValue ?? "all" }
}

/// Chips for a tab, honoring the sections the user keeps visible. Fewer than two sections means no chips:
/// there is nothing to isolate. Snoozed gets a chip only while something is snoozed; "All" never counts it.
/// `assigned`: how many pull requests assigned to the user are in the list (nil when the feature is off);
/// more than none gets the Assigned chip after the sections.
func quickFilterItems(sections ordered: [Section], visible: Set<Section>, mine: MineGroups, directTotal: Int, teamTotal: Int?, snoozedReview: Int, assigned: Int? = nil) -> [QuickFilterItem] {
    let sections = ordered.filter { visible.contains($0) && !$0.isFixed }
    guard sections.count >= 2, let tab = sections.first?.tab else { return [] }
    var items: [QuickFilterItem]
    let snoozed: QuickFilterItem
    switch tab {
    case .mine:
        let all = QuickFilterItem(section: nil, count: sections.reduce(0) { $0 + mine[$1].count })
        items = [all] + sections.map { QuickFilterItem(section: $0, count: mine[$0].count) }
        if let assigned, assigned > 0 { items.append(QuickFilterItem(section: .assignedMine, count: assigned)) }
        snoozed = QuickFilterItem(section: .snoozedMine, count: mine.snoozed.count)
    case .review:
        let all = QuickFilterItem(section: nil, count: nil)
        items = [all] + sections.map { section in
            QuickFilterItem(section: section, count: section == .needsYourReview ? directTotal : teamTotal)
        }
        snoozed = QuickFilterItem(section: .snoozedReview, count: snoozedReview)
    }
    let showSnoozed = visible.contains(snoozed.section!) && (snoozed.count ?? 0) > 0
    return showSnoozed ? items + [snoozed] : items
}

extension Section {
    /// Short label for the chips, where space is tight.
    var shortTitle: String {
        switch self {
        case .needsAction: String(localized: "Action", bundle: .app)
        case .readyToMerge: String(localized: "Ready", bundle: .app)
        case .waitingForReview: String(localized: "Waiting", bundle: .app)
        case .drafts: String(localized: "Drafts", bundle: .app)
        case .needsYourReview: String(localized: "Yours", bundle: .app)
        case .needsTeamsReview: String(localized: "Teams", bundle: .app)
        case .snoozedMine, .snoozedReview: String(localized: "Snoozed", bundle: .app)
        case .pinnedMine, .pinnedReview: String(localized: "Pinned", bundle: .app)
        case .assignedMine: String(localized: "Assigned", bundle: .app)
        }
    }
}
