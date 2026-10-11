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
func quickFilterItems(sections ordered: [Section], visible: Set<Section>, mine: MineGroups, directTotal: Int, teamTotal: Int?, snoozedReview: Int) -> [QuickFilterItem] {
    let sections = ordered.filter { visible.contains($0) && !$0.isSnoozed }
    guard sections.count >= 2, let tab = sections.first?.tab else { return [] }
    let items: [QuickFilterItem]
    let snoozed: QuickFilterItem
    switch tab {
    case .mine:
        let all = QuickFilterItem(section: nil, count: sections.reduce(0) { $0 + mine[$1].count })
        items = [all] + sections.map { QuickFilterItem(section: $0, count: mine[$0].count) }
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
        }
    }
}
