import Foundation

/// One chip in the quick filter row. `section == nil` is "All".
struct QuickFilterItem: Equatable, Identifiable, Sendable {
    let section: Section?
    /// nil hides the number (e.g. team requests before they were fetched, or "All" on the review tab).
    let count: Int?
    var id: String { section?.rawValue ?? "all" }
}

/// Chips for a tab, honoring the sections the user keeps visible. Fewer than two sections means no chips:
/// there is nothing to isolate.
func quickFilterItems(sections ordered: [Section], visible: Set<Section>, mine: MineGroups, directTotal: Int, teamTotal: Int?) -> [QuickFilterItem] {
    let sections = ordered.filter { visible.contains($0) }
    guard sections.count >= 2, let tab = sections.first?.tab else { return [] }
    switch tab {
    case .mine:
        let all = QuickFilterItem(section: nil, count: sections.reduce(0) { $0 + mine[$1].count })
        return [all] + sections.map { QuickFilterItem(section: $0, count: mine[$0].count) }
    case .review:
        let all = QuickFilterItem(section: nil, count: nil)
        return [all] + sections.map { section in
            QuickFilterItem(section: section, count: section == .needsYourReview ? directTotal : teamTotal)
        }
    }
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
        }
    }
}
