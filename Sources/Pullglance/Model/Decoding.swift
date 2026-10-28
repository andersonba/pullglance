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
    let pullRequests = search.nodes.compactMap { $0.value?.pullRequest }
    // GitHub reports per-node failures (e.g. "Resource limits for this query exceeded") as null nodes
    // next to a non-zero issueCount. Nothing usable came back: surface it instead of showing an empty list.
    if pullRequests.isEmpty, !search.nodes.isEmpty, !errors.isEmpty {
        throw DecodingFailure.noData(errors: errors)
    }
    return SearchPage(
        issueCount: search.issueCount,
        pullRequests: pullRequests,
        viewerLogin: envelope.data?.viewer?.login,
        viewerOrganizations: envelope.data?.viewer?.organizations?.nodes.compactMap { $0.value?.login } ?? [],
        errorMessages: errors
    )
}

/// What `pull-request.graphql` says about one pull request.
enum PullRequestLookup: Equatable, Sendable {
    case open(PullRequest)
    /// Merged or closed since it was shown.
    case closed(merged: Bool)
    /// Deleted, or the repository is gone or no longer visible.
    case notFound
}

func parsePullRequestResponse(_ data: Data) throws -> PullRequestLookup {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let envelope: Envelope
    do {
        envelope = try decoder.decode(Envelope.self, from: data)
    } catch {
        throw DecodingFailure.malformed(String(describing: error))
    }
    let errors = envelope.errors?.map(\.message) ?? []
    let unresolved = errors.contains { $0.localizedCaseInsensitiveContains("could not resolve") }
    guard let repository = envelope.data?.repository else {
        if unresolved { return .notFound }
        throw DecodingFailure.noData(errors: errors)
    }
    guard let node = repository.pullRequest?.value else {
        if !errors.isEmpty, !unresolved { throw DecodingFailure.noData(errors: errors) }
        return .notFound
    }
    if let state = node.state, state != "OPEN" { return .closed(merged: state == "MERGED") }
    guard let pullRequest = node.pullRequest else { throw DecodingFailure.malformed("pull request without its required fields") }
    return .open(pullRequest)
}

/// The batch form: alias → what that lookup said. Aliases whose node lacks required fields are left out,
/// so the caller keeps what it had for them.
func parsePullRequestsResponse(_ data: Data) throws -> [String: PullRequestLookup] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let envelope: BatchEnvelope
    do {
        envelope = try decoder.decode(BatchEnvelope.self, from: data)
    } catch {
        throw DecodingFailure.malformed(String(describing: error))
    }
    let errors = envelope.errors?.map(\.message) ?? []
    guard let payload = envelope.data else { throw DecodingFailure.noData(errors: errors) }
    // A null alias means "gone" only when every error is a "could not resolve"; any other error (rate
    // limit, server trouble) leaves those aliases out so the caller keeps what it had.
    let onlyUnresolved = errors.allSatisfy { $0.localizedCaseInsensitiveContains("could not resolve") }
    var result: [String: PullRequestLookup] = [:]
    for (alias, repository) in payload {
        guard let repository, let node = repository.pullRequest?.value else {
            if onlyUnresolved { result[alias] = .notFound }
            continue
        }
        if let state = node.state, state != "OPEN" { result[alias] = .closed(merged: state == "MERGED"); continue }
        if let pullRequest = node.pullRequest { result[alias] = .open(pullRequest) }
    }
    return result
}

private struct BatchEnvelope: Decodable {
    let data: [String: RepositoryPayload?]?
    let errors: [GraphQLError]?
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
    let repository: RepositoryPayload?
}

private struct RepositoryPayload: Decodable {
    let pullRequest: Lossy<PRNode>?
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
    let id: String?
    let state: String?
    let number: Int?
    let title: String?
    let url: URL?
    let isDraft: Bool?
    let mergeable: String?
    let mergeStateStatus: String?
    let isMergeQueueEnabled: Bool?
    let mergeQueueEntry: QueueEntry?
    let mergeQueue: Queue?
    let viewerCanEnableAutoMerge: Bool?
    let autoMergeRequest: AutoMerge?
    let baseRefName: String?
    let headRefName: String?
    let headRefOid: String?
    let updatedAt: Date?
    let createdAt: Date?
    let isReadByViewer: Bool?
    let changedFiles: Int?
    let additions: Int?
    let deletions: Int?
    let viewerLatestReview: LatestReview?
    let viewerLatestReviewRequest: ReviewRequestRef?
    let repository: Repository?
    let author: Login?
    let reviewDecision: String?
    let reviewThreads: Threads?
    let reviewRequests: Requests?
    let commits: Commits?

    struct Repository: Decodable {
        let nameWithOwner: String
        let mergeCommitAllowed: Bool?
        let squashMergeAllowed: Bool?
        let rebaseMergeAllowed: Bool?
        let deleteBranchOnMerge: Bool?
        let viewerDefaultMergeMethod: String?

        var mergeOptions: MergeOptions {
            guard mergeCommitAllowed != nil || squashMergeAllowed != nil || rebaseMergeAllowed != nil else { return .permissive }
            var allowed = Set<MergeMethod>()
            if mergeCommitAllowed ?? false { allowed.insert(.merge) }
            if squashMergeAllowed ?? false { allowed.insert(.squash) }
            if rebaseMergeAllowed ?? false { allowed.insert(.rebase) }
            return MergeOptions(
                allowed: allowed,
                defaultMethod: viewerDefaultMergeMethod.flatMap(MergeMethod.init(apiValue:)) ?? .merge,
                deleteBranchOnMerge: deleteBranchOnMerge ?? false
            )
        }
    }
    struct Login: Decodable {
        let login: String
        let avatarUrl: URL?
    }
    struct QueueEntry: Decodable { let position: Int? }
    struct AutoMerge: Decodable { let mergeMethod: String? }
    struct LatestReview: Decodable { let state: String? }
    struct ReviewRequestRef: Decodable { let id: String? }
    struct Queue: Decodable {
        let configuration: Configuration?
        struct Configuration: Decodable { let mergeMethod: String? }
    }
    struct Threads: Decodable { let nodes: [Lossy<Thread>] }
    struct Thread: Decodable { let isResolved: Bool; let path: String? }
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
        let openThreads = reviewThreads?.nodes.compactMap(\.value).filter { !$0.isResolved } ?? []
        let unresolved = openThreads.count
        var threadPaths: [String] = []
        for path in openThreads.compactMap(\.path) where !threadPaths.contains(path) { threadPaths.append(path) }
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
            unresolvedThreadPaths: threadPaths,
            requestedTeams: teams,
            hasConflicts: mergeable == "CONFLICTING",
            isBehindBase: mergeStateStatus == "BEHIND",
            authorAvatarURL: author?.avatarUrl,
            baseRefName: baseRefName ?? "",
            headRefName: headRefName ?? "",
            headRefOid: headRefOid ?? "",
            mergeOptions: repository.mergeOptions,
            nodeID: id ?? "",
            hasMergeState: mergeable != nil,
            usesMergeQueue: isMergeQueueEnabled ?? false,
            mergeQueuePosition: mergeQueueEntry?.position,
            queueMergeMethod: mergeQueue?.configuration?.mergeMethod.flatMap(MergeMethod.init(apiValue:)),
            isBlocked: mergeStateStatus == "BLOCKED",
            canEnableAutoMerge: viewerCanEnableAutoMerge ?? false,
            autoMergeMethod: autoMergeRequest?.mergeMethod.flatMap(MergeMethod.init(apiValue:)),
            createdAt: createdAt ?? updatedAt,
            isReadByViewer: isReadByViewer ?? true,
            changedFiles: changedFiles,
            additions: additions,
            deletions: deletions,
            viewerReviewedBefore: viewerLatestReview != nil,
            viewerRequested: viewerLatestReviewRequest != nil
        )
    }
}

struct FileCounts: Equatable, Sendable {
    var total: Int
    var viewed: Int
}

struct FileCountsPage: Equatable, Sendable {
    let total: Int
    let viewedOnPage: Int
    let nextCursor: String?
}

func parsePullRequestFilesResponse(_ data: Data) throws -> FileCountsPage {
    struct Envelope: Decodable {
        struct Payload: Decodable { let repository: Repository? }
        struct Repository: Decodable { let pullRequest: PR? }
        struct PR: Decodable { let changedFiles: Int; let files: Files }
        struct Files: Decodable { let pageInfo: PageInfo; let nodes: [Node] }
        struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
        struct Node: Decodable { let viewerViewedState: String? }
        let data: Payload?
        let errors: [GraphQLError]?
    }
    let envelope: Envelope
    do { envelope = try JSONDecoder().decode(Envelope.self, from: data) } catch { throw DecodingFailure.malformed(String(describing: error)) }
    guard let pr = envelope.data?.repository?.pullRequest else { throw DecodingFailure.noData(errors: envelope.errors?.map(\.message) ?? []) }
    return FileCountsPage(total: pr.changedFiles,
                          viewedOnPage: pr.files.nodes.filter { $0.viewerViewedState == "VIEWED" }.count,
                          nextCursor: pr.files.pageInfo.hasNextPage ? pr.files.pageInfo.endCursor : nil)
}

/// Pages of 100; GitHub lists at most 3000 files on a pull request, so a cursor still coming back after
/// this many pages is not a listing worth following.
let fileCountsPageLimit = 30

/// Every page, or nothing: a partial count would look final.
func fetchFileCounts(_ client: GHRunning, ref: PullRequestRef) async -> FileCounts? {
    var viewed = 0
    var total = 0
    var cursor: String? = nil
    var pages = 0
    repeat {
        guard pages < fileCountsPageLimit,
              case .success(let data) = await client.pullRequestFiles(owner: ref.owner, name: ref.name, number: ref.number, after: cursor),
              let page = try? parsePullRequestFilesResponse(data) else { return nil }
        pages += 1
        total = page.total
        viewed += page.viewedOnPage
        cursor = page.nextCursor
    } while cursor != nil
    return FileCounts(total: total, viewed: viewed)
}

/// The queue position from `enqueue.graphql`, nil when GitHub returned the entry without one. GraphQL
/// errors (already queued, not allowed, head moved) come back as `errors` next to a null payload.
func parseEnqueueResponse(_ data: Data) throws -> Int? {
    struct Envelope: Decodable {
        let data: Payload?
        let errors: [GraphQLError]?
        struct Payload: Decodable { let enqueuePullRequest: Result? }
        struct Result: Decodable { let mergeQueueEntry: Entry? }
        struct Entry: Decodable { let position: Int? }
    }
    let envelope: Envelope
    do {
        envelope = try JSONDecoder().decode(Envelope.self, from: data)
    } catch {
        throw DecodingFailure.malformed(String(describing: error))
    }
    let errors = envelope.errors?.map(\.message) ?? []
    guard let result = envelope.data?.enqueuePullRequest else { throw DecodingFailure.noData(errors: errors) }
    guard let entry = result.mergeQueueEntry else {
        // No entry and errors next to it: GitHub did not confirm anything.
        if !errors.isEmpty { throw DecodingFailure.noData(errors: errors) }
        return nil
    }
    return entry.position
}

/// GitHub's hourly GraphQL budget as of one response, when the query asked for it (`pull-request.graphql`
/// does, for the watch poll's log). Never an error: a response without it is just quiet about the cost.
struct RateLimitStatus: Equatable, Sendable {
    let remaining: Int
    let resetAt: Date
}

func parseRateLimit(_ data: Data) -> RateLimitStatus? {
    struct Envelope: Decodable {
        struct Payload: Decodable { let rateLimit: Limit? }
        struct Limit: Decodable { let remaining: Int; let resetAt: Date }
        let data: Payload?
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let limit = (try? decoder.decode(Envelope.self, from: data))?.data?.rateLimit else { return nil }
    return RateLimitStatus(remaining: limit.remaining, resetAt: limit.resetAt)
}

/// A mutation that only acknowledges: `data.<field>` must be there, and no `errors` next to it.
func parseMutationAck(_ data: Data, field: String) throws {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw DecodingFailure.malformed("not a JSON object")
    }
    let errors = (object["errors"] as? [[String: Any]])?.compactMap { $0["message"] as? String } ?? []
    let payload = (object["data"] as? [String: Any])?[field]
    guard payload != nil, !(payload is NSNull), errors.isEmpty else { throw DecodingFailure.noData(errors: errors) }
}
