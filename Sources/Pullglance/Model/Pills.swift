enum Pill: Hashable, Sendable {
    case ciFailed
    case ciRunning
    case changesRequested
    case approved
    case readyToMerge
    case awaitingReview
    case conflicts
    case behindBase
    case openThreads(Int)
}

/// Ordered left to right as they appear in a row.
func pills(for pr: PullRequest) -> [Pill] {
    var result: [Pill] = []
    switch pr.ciState {
    case .failure: result.append(.ciFailed)
    case .pending: result.append(.ciRunning)
    case .success, .none: break
    }
    switch pr.reviewDecision {
    case .changesRequested:
        result.append(.changesRequested)
    case .approved:
        result.append(.approved)
        if pr.ciState == .success, !pr.hasConflicts, !pr.isBehindBase { result.append(.readyToMerge) }
    case .reviewRequired, nil:
        result.append(.awaitingReview)
    }
    if pr.hasConflicts { result.append(.conflicts) }
    if pr.isBehindBase { result.append(.behindBase) }
    if pr.unresolvedThreads > 0 {
        result.append(.openThreads(pr.unresolvedThreads))
    }
    return result
}
