import Foundation

/// A repository found by searching GitHub, as opposed to one seen in PR results.
struct CatalogRepo: Equatable, Sendable, Identifiable {
    let fullName: String
    let isArchived: Bool
    var id: String { fullName }
    var owner: String { fullName.split(separator: "/").first.map(String.init) ?? fullName }
    var name: String { fullName.split(separator: "/").last.map(String.init) ?? fullName }
}

struct RepoSearchResult: Equatable, Sendable {
    let total: Int
    let repos: [CatalogRepo]
}

enum RepoSearchQuery {
    /// Repository search scoped to one organization or account, most recently updated first.
    static func string(owner: String, term: String) -> String {
        let cleaned = term.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "org:\(owner) \(cleaned) sort:updated"
    }
}

func parseRepoSearch(_ data: Data) throws -> RepoSearchResult {
    struct Envelope: Decodable { let data: Payload?; let errors: [GraphQLMessage]? }
    struct Payload: Decodable { let search: Connection? }
    struct Connection: Decodable { let repositoryCount: Int; let nodes: [Lossy<Node>] }
    let envelope: Envelope
    do { envelope = try JSONDecoder().decode(Envelope.self, from: data) } catch { throw DecodingFailure.malformed(String(describing: error)) }
    guard let connection = envelope.data?.search else {
        throw DecodingFailure.noData(errors: envelope.errors?.map(\.message) ?? [])
    }
    return RepoSearchResult(total: connection.repositoryCount, repos: connection.nodes.compactMap { $0.value?.repo })
}

private struct GraphQLMessage: Decodable { let message: String }

private struct Node: Decodable {
    let nameWithOwner: String?
    let isArchived: Bool?
    var repo: CatalogRepo? {
        guard let nameWithOwner else { return nil }
        return CatalogRepo(fullName: nameWithOwner, isArchived: isArchived ?? false)
    }
}
