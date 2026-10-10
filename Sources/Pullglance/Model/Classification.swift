import Foundation

/// The one rule for the "My PRs" sections. The badge adds up whichever sections the user selected.
/// Open review threads deliberately do not move a PR; they only show as a pill.
func mineSection(for pr: PullRequest) -> Section {
    if pr.isDraft { return .drafts }
    if pr.ciState == .failure || pr.reviewDecision == .changesRequested || pr.hasConflicts || pr.isBehindBase {
        return .needsAction
    }
    if pr.reviewDecision == .approved, pr.ciState == .success || pr.ciState == .none {
        return .readyToMerge
    }
    return .waitingForReview
}

struct MineGroups: Sendable, Equatable {
    var needsAction: [PullRequest] = []
    var readyToMerge: [PullRequest] = []
    var waitingForReview: [PullRequest] = []
    var drafts: [PullRequest] = []

    subscript(section: Section) -> [PullRequest] {
        switch section {
        case .needsAction: needsAction
        case .readyToMerge: readyToMerge
        case .waitingForReview: waitingForReview
        case .drafts: drafts
        case .needsYourReview, .needsTeamsReview: []
        }
    }
}

func sortedByRecency(_ prs: [PullRequest]) -> [PullRequest] {
    prs.sorted { $0.updatedAt > $1.updatedAt }
}

func groupMine(_ prs: [PullRequest]) -> MineGroups {
    var groups = MineGroups()
    for pr in sortedByRecency(prs) {
        switch mineSection(for: pr) {
        case .needsAction: groups.needsAction.append(pr)
        case .readyToMerge: groups.readyToMerge.append(pr)
        case .waitingForReview: groups.waitingForReview.append(pr)
        case .drafts: groups.drafts.append(pr)
        case .needsYourReview, .needsTeamsReview: break
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

/// `viaTeam` is the already filtered team list (see `filterViaTeam`).
func computeBadgeCount(mine: [PullRequest], direct: [PullRequest], viaTeam: [PullRequest], counting sections: Set<Section>) -> Int {
    let groups = groupMine(mine)
    var total = 0
    for section in sections {
        switch section.tab {
        case .mine: total += groups[section].count
        case .review: total += section == .needsYourReview ? direct.count : viaTeam.count
        }
    }
    return total
}
