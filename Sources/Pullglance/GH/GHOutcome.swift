import Foundation

enum GHOutcome: Sendable, Equatable {
    case success(Data)
    case ghNotFound
    case notAuthenticated
    case failure(String)
}

protocol GHRunning: Sendable {
    /// `includeMergeState` asks for `mergeable`/`mergeStateStatus`, which GitHub computes on demand and
    /// refuses for large pages ("Resource limits for this query exceeded"). Only your own PRs need it.
    func search(_ query: String, includeMergeState: Bool) async -> GHOutcome
}
