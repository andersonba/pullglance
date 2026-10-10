import Foundation

struct SearchPage: Sendable, Equatable {
    let issueCount: Int
    let pullRequests: [PullRequest]
    let viewerLogin: String?
    let viewerOrganizations: [String]
    let errorMessages: [String]
}

enum DecodingFailure: Error, Equatable {
    case noData(errors: [String])
    case malformed(String)
}

/// Parses the JSON printed by `gh api graphql` for `search.graphql`.
/// Tolerant by design: a malformed or null node is dropped, `errors` next to `data` are reported, not fatal.
func parseSearchResponse(_ data: Data) throws -> SearchPage {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let envelope: Envelope
    do {
        envelope = try decoder.decode(Envelope.self, from: data)
    } catch {
        throw DecodingFailure.malformed(String(describing: error))
    }
    let errors = envelope.errors?.map(\.message) ?? []
    guard let search = envelope.data?.search else {
        throw DecodingFailure.noData(errors: errors)
    }
    return SearchPage(
        issueCount: search.issueCount,
        pullRequests: search.nodes.compactMap { $0.value?.pullRequest },
        viewerLogin: envelope.data?.viewer?.login,
        viewerOrganizations: envelope.data?.viewer?.organizations?.nodes.compactMap { $0.value?.login } ?? [],
        errorMessages: errors
    )
}

/// Decodes to nil instead of failing the enclosing array when the element is null or malformed.
struct Lossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?
    init(from decoder: Decoder) {
        if let container = try? decoder.singleValueContainer(), container.decodeNil() {
            value = nil
            return
        }
        value = try? Wrapped(from: decoder)
    }
}

// MARK: - Wire format (private)

private struct Envelope: Decodable {
    let data: Payload?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}

private struct Payload: Decodable {
    let viewer: Viewer?
    let search: SearchConnection?
}

private struct Viewer: Decodable {
    let login: String
    let organizations: Organizations?

    struct Organizations: Decodable { let nodes: [Lossy<Org>] }
    struct Org: Decodable { let login: String }
}

private struct SearchConnection: Decodable {
    let issueCount: Int
    let nodes: [Lossy<PRNode>]
}

private struct PRNode: Decodable {
    let number: Int?
    let title: String?
    let url: URL?
    let isDraft: Bool?
    let updatedAt: Date?
    let repository: Repository?
    let author: Login?
    let reviewDecision: String?
    let reviewThreads: Threads?
    let reviewRequests: Requests?
    let commits: Commits?

    struct Repository: Decodable { let nameWithOwner: String }
    struct Login: Decodable { let login: String }
    struct Threads: Decodable { let nodes: [Lossy<Thread>] }
    struct Thread: Decodable { let isResolved: Bool }
    struct Requests: Decodable { let nodes: [Lossy<Request>] }
    struct Request: Decodable { let requestedReviewer: Reviewer? }
    struct Reviewer: Decodable {
        let typename: String?
        let slug: String?
        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case slug
        }
    }
    struct Commits: Decodable { let nodes: [Lossy<CommitNode>] }
    struct CommitNode: Decodable { let commit: Commit }
    struct Commit: Decodable { let statusCheckRollup: Rollup? }
    struct Rollup: Decodable { let state: String? }

    var pullRequest: PullRequest? {
        guard let number, let title, let url, let repository, let updatedAt else { return nil }
        let rollup = commits?.nodes.first?.value?.commit.statusCheckRollup?.state
        let ci: CIState
        switch rollup {
        case "SUCCESS": ci = .success
        case "FAILURE", "ERROR": ci = .failure
        case "PENDING", "EXPECTED": ci = .pending
        default: ci = .none
        }
        let unresolved = reviewThreads?.nodes.compactMap(\.value).filter { !$0.isResolved }.count ?? 0
        let teams = reviewRequests?.nodes
            .compactMap { $0.value?.requestedReviewer }
            .filter { $0.typename == "Team" }
            .compactMap(\.slug) ?? []
        return PullRequest(
            repo: repository.nameWithOwner,
            number: number,
            title: title,
            url: url,
            isDraft: isDraft ?? false,
            author: author?.login ?? "ghost",
            updatedAt: updatedAt,
            reviewDecision: reviewDecision.flatMap(ReviewDecision.init(rawValue:)),
            ciState: ci,
            unresolvedThreads: unresolved,
            requestedTeams: teams
        )
    }
}
