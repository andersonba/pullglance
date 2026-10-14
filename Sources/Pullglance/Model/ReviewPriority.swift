import Foundation

/// Why a review request comes first, in a word the row can show. Tiers, not points: the pill says the
/// tier, and where a pull request lands is predictable.
enum ReviewSignal: Hashable, Sendable {
    /// You reviewed before and are asked again: you are the one blocking.
    case reReview
    /// Activity you have not looked at.
    case newActivity
    /// Small diff: done in a minute.
    case quick(files: Int)
    /// Asked this many days ago; shown from two days on.
    case waiting(days: Int)

    static let quickFiles = 5
    static let quickLines = 60
    static let waitingFromDays = 2
}

/// The first tier that applies, or nil. CI failing and drafts are not here: they sort to the bottom, with
/// the pills they already have.
func reviewSignal(for pr: PullRequest, now: Date) -> ReviewSignal? {
    if pr.viewerReviewedBefore, pr.viewerRequested { return .reReview }
    if !pr.isReadByViewer { return .newActivity }
    if let files = pr.changedFiles, files <= ReviewSignal.quickFiles { return .quick(files: files) }
    if let lines = pr.linesChanged, lines <= ReviewSignal.quickLines, let files = pr.changedFiles { return .quick(files: files) }
    let days = Int(now.timeIntervalSince(pr.createdAt) / 86_400)
    if days >= ReviewSignal.waitingFromDays { return .waiting(days: days) }
    return nil
}

/// Lower first. The author still working (red CI, draft) sinks below everyone, keeping the tiers inside.
func reviewPriorityTier(for pr: PullRequest, now: Date) -> Int {
    let base: Int
    switch reviewSignal(for: pr, now: now) {
    case .reReview: base = 0
    case .newActivity: base = 1
    case .quick: base = 2
    case .waiting, nil: base = 3
    }
    return pr.ciState == .failure || pr.isDraft ? base + 10 : base
}

/// Tier, then the oldest request first.
func sortedByPriority(_ prs: [PullRequest], now: Date) -> [PullRequest] {
    prs.sorted { a, b in
        let ta = reviewPriorityTier(for: a, now: now), tb = reviewPriorityTier(for: b, now: now)
        if ta != tb { return ta < tb }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id < b.id
    }
}

/// How a section's rows are ordered when the user has not ordered them by hand.
enum ListSort: String, Codable, Sendable, CaseIterable {
    case priority, recent

    /// Reviews come by priority; your own pull requests by recency, as before.
    static func `default`(for section: Section) -> ListSort {
        section.tab == .review ? .priority : .recent
    }
}
