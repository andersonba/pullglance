import Foundation

/// What the footer says, derived from the store's phase and the clock. Pure, so the rules are testable.
enum FooterStatus: Equatable, Sendable {
    case fetching
    case refreshing
    case updatedNow
    case countdown(seconds: Int)
    case failed(at: Date)

    /// Clicking the status refreshes, except while a cycle runs or right after one finished.
    var allowsManualRefresh: Bool {
        switch self {
        case .countdown, .failed: true
        case .fetching, .refreshing, .updatedNow: false
        }
    }

    /// "m:ss" for the countdown, empty otherwise.
    var countdownText: String {
        guard case .countdown(let seconds) = self else { return "" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static let updatedNowWindow: TimeInterval = 10
}

func footerStatus(phase: Phase, hasData: Bool, nextRefresh: Date?, now: Date) -> FooterStatus {
    switch phase {
    case .idle:
        return .fetching
    case .loading:
        return hasData ? .refreshing : .fetching
    case .ok(let date):
        if now.timeIntervalSince(date) < FooterStatus.updatedNowWindow { return .updatedNow }
        let remaining = nextRefresh.map { Int($0.timeIntervalSince(now).rounded(.down)) } ?? 0
        return .countdown(seconds: max(0, remaining))
    case .error(_, let date):
        return .failed(at: date)
    }
}

/// Which search a failure belongs to.
enum SearchKind: String, Sendable, Equatable, CaseIterable {
    case mine
    case direct
    case team
}

struct LogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let search: SearchKind
    let kind: ErrorKind

    init(date: Date, search: SearchKind, kind: ErrorKind) {
        self.id = UUID()
        self.date = date
        self.search = search
        self.kind = kind
    }

    /// Coarse category for the Logs table, derived from the message.
    var category: String {
        switch kind {
        case .ghNotFound: return String(localized: "gh not found", bundle: .app)
        case .notAuthenticated: return String(localized: "Not logged in", bundle: .app)
        case .other(let message):
            let lower = message.lowercased()
            if lower.contains("timed out") { return String(localized: "Timeout", bundle: .app) }
            if lower.contains("rate limit") { return String(localized: "Rate limit", bundle: .app) }
            if lower.contains("resource limits") || lower.contains("graphql") { return String(localized: "GraphQL", bundle: .app) }
            if lower.contains("connect") || lower.contains("network") || lower.contains("dial") || lower.contains("dns") {
                return String(localized: "Network", bundle: .app)
            }
            return String(localized: "Error", bundle: .app)
        }
    }

    var message: String {
        switch kind {
        case .ghNotFound: String(localized: "gh CLI not found", bundle: .app)
        case .notAuthenticated: String(localized: "gh is not logged in to github.com", bundle: .app)
        case .other(let message): message
        }
    }
}
