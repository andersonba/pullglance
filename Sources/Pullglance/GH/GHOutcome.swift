import Foundation

enum GHOutcome: Sendable, Equatable {
    case success(Data)
    case ghNotFound
    case notAuthenticated
    case failure(String)
}

protocol GHRunning: Sendable {
    func search(_ query: String) async -> GHOutcome
}
