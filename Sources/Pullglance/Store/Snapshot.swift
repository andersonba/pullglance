import Foundation

/// The last good result of one search, kept across failed refreshes.
struct Snapshot<Value: Sendable & Equatable>: Sendable, Equatable {
    var value: Value
    /// `issueCount` from the API. Can exceed `value.count` because we fetch one page.
    var total: Int
    var fetchedAt: Date?
}

enum ErrorKind: Sendable, Equatable {
    case ghNotFound
    case notAuthenticated
    case other(String)
}

enum Phase: Sendable, Equatable {
    case idle
    case loading
    case ok(Date)
    case error(ErrorKind, Date)
}
