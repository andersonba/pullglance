import Foundation

/// What the review window is looking at, from the URL alone. Pure, so the bar's presence rules are testable.
enum ReviewPage: Equatable, Sendable {
    enum Tab: Equatable, Sendable { case conversation, commits, files, checks }
    case pullRequest(repo: String, number: Int, tab: Tab)
    case compare(repo: String, range: String)
    case other

    static func classify(_ url: URL?) -> ReviewPage {
        guard let url, url.host?.lowercased() == "github.com" else { return .other }
        // pathComponents keeps percent-encoding decoded ("feat%2Fcheckout" → one component "feat/checkout").
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4 else { return .other }
        let repo = parts[0] + "/" + parts[1]
        switch parts[2] {
        case "pull":
            guard let number = Int(parts[3]), number > 0 else { return .other }
            let tab: Tab = switch parts.count > 4 ? parts[4] : "" {
            case "files", "changes": .files
            case "commits": .commits
            case "checks": .checks
            default: .conversation
            }
            return .pullRequest(repo: repo, number: number, tab: tab)
        case "compare":
            let range = parts[3...].joined(separator: "/")
            return range.isEmpty ? .other : .compare(repo: repo, range: range)
        default:
            return .other
        }
    }

    var repo: String? {
        switch self {
        case .pullRequest(let repo, _, _), .compare(let repo, _): repo
        case .other: nil
        }
    }

    var showsBar: Bool { self != .other }

    /// Same pull request, any tab. Clicking a row for the PR already on screen must not throw away the
    /// tab the user navigated to.
    func isSamePullRequest(as other: ReviewPage) -> Bool {
        guard case .pullRequest(let repo, let number, _) = self, case .pullRequest(let otherRepo, let otherNumber, _) = other else { return false }
        return repo == otherRepo && number == otherNumber
    }

    /// "main...feat/x" shown as "main…feat/x".
    var compareTitle: String? {
        guard case .compare(_, let range) = self else { return nil }
        return range.replacingOccurrences(of: "...", with: "…")
    }
}
