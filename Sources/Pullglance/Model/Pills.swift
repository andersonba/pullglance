enum Pill: Hashable, Sendable {
    case ciFailed
    case ciRunning
    case changesRequested
    case approved
    case readyToMerge
    /// Added to the base branch's merge queue, at this 1-based position; replaces "ready".
    case inMergeQueue(Int)
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
        if pr.mergeQueuePosition == nil, pr.ciState == .success, !pr.hasConflicts, !pr.isBehindBase { result.append(.readyToMerge) }
    case .reviewRequired, nil:
        result.append(.awaitingReview)
    }
    // Independent of the review: repositories without required reviews queue too.
    if let position = pr.mergeQueuePosition { result.append(.inMergeQueue(position)) }
    if pr.hasConflicts { result.append(.conflicts) }
    if pr.isBehindBase { result.append(.behindBase) }
    if pr.unresolvedThreads > 0 {
        result.append(.openThreads(pr.unresolvedThreads))
    }
    return result
}
