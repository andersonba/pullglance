import Foundation

enum ReviewDecision: String, Sendable, Equatable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum CIState: Sendable, Equatable {
    case success
    case failure
    case pending
    case none
}

struct PullRequest: Sendable, Equatable, Identifiable {
    let repo: String
    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let author: String
    let updatedAt: Date
    let reviewDecision: ReviewDecision?
    let ciState: CIState
    let unresolvedThreads: Int
    let requestedTeams: [String]

    var id: String { "\(repo)#\(number)" }
    var checksURL: URL { url.appendingPathComponent("checks") }
    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
    var ownerLogin: String { repo.split(separator: "/").first.map(String.init) ?? repo }
}
