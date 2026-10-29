enum Pill: Hashable, Sendable {
    /// Why this review request comes first; review rows only, ahead of the rest.
    case reason(ReviewSignal)
    case ciFailed
    case ciRunning
    case changesRequested
    case approved
    case readyToMerge
    /// Added to the base branch's merge queue, at this 1-based position; replaces "ready".
    case inMergeQueue(Int)
    /// Auto-merge is on: GitHub merges when the requirements pass.
    case autoMerge
    case awaitingReview
    case conflicts
    case behindBase
    case openThreads(Int)
    /// A timed snooze ended at the last refresh; the row is back where it belongs.
    case woke
    /// A watched pull request moved, and why; the watch ended with the notification.
    case moved(WatchMovement)
    /// This pull request's place in its GitHub stack: position and size, both GitHub's. Always last.
    case stack(position: Int, size: Int)
}

/// Ordered left to right as they appear in a row.
func pills(for pr: PullRequest) -> [Pill] {
    var result: [Pill] = []
    switch pr.ciState {
    case .failure: result.append(.ciFailed)
    case .pending: result.append(.ciRunning)
    case .success, .none: break
    }
    let ready = !pr.isDraft && pr.mergeQueuePosition == nil && pr.ciState == .success && !pr.hasConflicts && !pr.isBehindBase
    switch pr.reviewDecision {
    case .changesRequested:
        result.append(.changesRequested)
    case .approved:
        result.append(.approved)
        if ready { result.append(.readyToMerge) }
    case nil where ready && pr.reviewAllowsMerge:
        // No review required: nothing to wait for, whatever requests are still open.
        result.append(.readyToMerge)
    case .reviewRequired, nil:
        result.append(.awaitingReview)
    }
    // Independent of the review: repositories without required reviews queue too.
    if let position = pr.mergeQueuePosition { result.append(.inMergeQueue(position)) }
    if pr.autoMergeMethod != nil { result.append(.autoMerge) }
    if pr.hasConflicts { result.append(.conflicts) }
    if pr.isBehindBase { result.append(.behindBase) }
    if pr.unresolvedThreads > 0 {
        result.append(.openThreads(pr.unresolvedThreads))
    }
    if let stack = pr.stack { result.append(.stack(position: stack.position, size: stack.size)) }
    return result
}
