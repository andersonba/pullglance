import Foundation

/// A section the user has reordered by hand keeps the ids in that order. PRs the order does not know yet
/// (new, or just moved into the section) come first, in the order they arrived, which is newest first;
/// ids that are not in the list are skipped.
func applyManualOrder(_ prs: [PullRequest], ids: [String]) -> [PullRequest] {
    guard !ids.isEmpty else { return prs }
    let byID = Dictionary(prs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let known = Set(ids)
    let newcomers = prs.filter { !known.contains($0.id) }
    let kept = ids.compactMap { byID[$0] }
    return newcomers + kept
}

/// Drops ids that are no longer in any result (closed, merged, filtered out for good), and sections left
/// with nothing, so the stored orders do not grow forever.
func pruneManualOrders(_ orders: [String: [String]], keeping ids: Set<String>) -> [String: [String]] {
    orders.compactMapValues { list in
        let kept = list.filter(ids.contains)
        return kept.isEmpty ? nil : kept
    }
}
