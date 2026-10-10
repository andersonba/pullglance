import Foundation

enum MineSection: Sendable, Equatable, CaseIterable {
    case needsYou
    case waitingOnOthers
    case drafts
}

/// The one rule for both the "My PRs" sections and the menu bar badge.
/// Open review threads deliberately do not move a PR here; they only show as a pill.
func mineSection(for pr: PullRequest) -> MineSection {
    if pr.isDraft { return .drafts }
    if pr.ciState == .failure || pr.reviewDecision == .changesRequested { return .needsYou }
    return .waitingOnOthers
}

struct MineGroups: Sendable, Equatable {
    var needsYou: [PullRequest] = []
    var waitingOnOthers: [PullRequest] = []
    var drafts: [PullRequest] = []
}

func sortedByRecency(_ prs: [PullRequest]) -> [PullRequest] {
    prs.sorted { $0.updatedAt > $1.updatedAt }
}

func groupMine(_ prs: [PullRequest]) -> MineGroups {
    var groups = MineGroups()
    for pr in sortedByRecency(prs) {
        switch mineSection(for: pr) {
        case .needsYou: groups.needsYou.append(pr)
        case .waitingOnOthers: groups.waitingOnOthers.append(pr)
        case .drafts: groups.drafts.append(pr)
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

func computeBadgeCount(mine: [PullRequest], direct: [PullRequest]) -> Int {
    mine.filter { mineSection(for: $0) == .needsYou }.count + direct.count
}
