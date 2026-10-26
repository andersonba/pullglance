import Foundation

/// The one rule for the "My PRs" sections. The badge adds up whichever sections the user selected.
/// Open review threads deliberately do not move a PR; they only show as a pill.
func mineSection(for pr: PullRequest) -> Section {
    if pr.isDraft { return .drafts }
    if pr.ciState == .failure || pr.reviewDecision == .changesRequested || pr.hasConflicts || pr.isBehindBase {
        return .needsAction
    }
    // In the merge queue or with auto-merge on, GitHub merges by itself: nothing left to do here.
    if pr.mergeQueuePosition != nil || pr.autoMergeMethod != nil { return .waitingForReview }
    if pr.reviewAllowsMerge, pr.ciState == .success || pr.ciState == .none {
        return .readyToMerge
    }
    return .waitingForReview
}

struct MineGroups: Sendable, Equatable {
    var needsAction: [PullRequest] = []
    var readyToMerge: [PullRequest] = []
    var waitingForReview: [PullRequest] = []
    var drafts: [PullRequest] = []
    var snoozed: [PullRequest] = []
    var pinned: [PullRequest] = []

    subscript(section: Section) -> [PullRequest] {
        switch section {
        case .needsAction: needsAction
        case .readyToMerge: readyToMerge
        case .waitingForReview: waitingForReview
        case .drafts: drafts
        case .snoozedMine: snoozed
        case .pinnedMine: pinned
        case .needsYourReview, .needsTeamsReview, .snoozedReview, .pinnedReview, .assignedMine: []
        }
    }
}

func sortedByRecency(_ prs: [PullRequest]) -> [PullRequest] {
    prs.sorted { $0.updatedAt > $1.updatedAt }
}

/// Snoozed PRs leave their section for the tab's "Snoozed" one; pinned ones for "Pinned".
func groupMine(_ prs: [PullRequest], dormant: Set<String> = [], pinned: Set<String> = []) -> MineGroups {
    var groups = MineGroups()
    for pr in sortedByRecency(prs) {
        if dormant.contains(pr.id) { groups.snoozed.append(pr); continue }
        if pinned.contains(pr.id) { groups.pinned.append(pr); continue }
        switch mineSection(for: pr) {
        case .needsAction: groups.needsAction.append(pr)
        case .readyToMerge: groups.readyToMerge.append(pr)
        case .waitingForReview: groups.waitingForReview.append(pr)
        case .drafts: groups.drafts.append(pr)
        case .needsYourReview, .needsTeamsReview, .snoozedMine, .snoozedReview, .pinnedMine, .pinnedReview, .assignedMine: break
        }
    }
    return groups
}

/// Team-requested PRs worth showing: not already a direct request, not authored by the viewer, newest first, capped.
func filterViaTeam(all: [PullRequest], direct: [PullRequest], viewerLogin: String?, limit: Int = 20) -> [PullRequest] {
    let directIDs = Set(direct.map(\.id))
    return Array(
        sortedByRecency(all)
            .filter { !directIDs.contains($0.id) && $0.author != viewerLogin }
            .prefix(limit)
    )
}

/// `viaTeam` is the already filtered team list (see `filterViaTeam`). Snoozed PRs never count.
/// How the menu bar number is built: one total, or two numbers each adding up its own sections.
enum BadgeMode: String, Codable, Sendable, CaseIterable {
    case single, dual
}

/// One rolling change of the menu bar text, frame by frame (see `PRStore.badgeRoll`).
struct BadgeRoll: Equatable, Sendable {
    let from: String
    let to: String
    /// 0 shows `from`, 1 shows `to`.
    var progress: Double
    /// New digits come from below when the count went up.
    let up: Bool
}

/// Which of the two numbers a section counts toward.
enum BadgeSlot: Sendable, Equatable {
    case first, second
}

/// The menu bar text. Two numbers keep both positions ("2 · 0") so the eye learns where each lives;
/// nothing is shown when everything is zero.
func badgeText(first: Int, second: Int?, mode: BadgeMode) -> String? {
    switch mode {
    case .single:
        return first > 0 ? "\(first)" : nil
    case .dual:
        let second = second ?? 0
        return first == 0 && second == 0 ? nil : "\(first) · \(second)"
    }
}

func computeBadgeCount(mine: [PullRequest], direct: [PullRequest], viaTeam: [PullRequest], counting sections: Set<Section>, dormant: Set<String> = []) -> Int {
    let awake = { (prs: [PullRequest]) in prs.filter { !dormant.contains($0.id) } }
    let groups = groupMine(awake(mine))
    var total = 0
    for section in sections {
        switch section.tab {
        case .mine: total += groups[section].count
        case .review: total += section == .needsYourReview ? awake(direct).count : awake(viaTeam).count
        }
    }
    return total
}

/// What the row's leading dot stands for. The checks, unless the pull request has left the user's hands:
/// in the merge queue, or with auto-merge on, GitHub merges by itself, and the dot says so in the purple of
/// the pill, with the checks kept for the tooltip. Checks that fail take the pull request out of the queue,
/// and the dot turns red with them. Queued wins over auto-merge: it is the later, more specific fact.
enum RowIndicator: Equatable, Sendable {
    case checks(CIState)
    case queued(position: Int, checks: CIState)
    case autoMerge(checks: CIState)

    static func of(_ pr: PullRequest) -> RowIndicator {
        if let position = pr.mergeQueuePosition { return .queued(position: position, checks: pr.ciState) }
        if pr.autoMergeMethod != nil { return .autoMerge(checks: pr.ciState) }
        return .checks(pr.ciState)
    }
}
