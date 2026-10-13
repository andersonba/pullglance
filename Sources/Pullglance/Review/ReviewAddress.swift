import Foundation

/// Pure rules of the review window's address handling, kept out of AppKit so they can be tested.
enum ReviewAddress {
    /// "github.com/x", "https://github.com/x" and a bare "owner/repo/…" all mean the same page: a first
    /// segment without a dot is a GitHub path, not a host (that is what a path completion produces).
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            let first = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
            if !first.contains("."), !first.contains(":") { text = "github.com/" + text }
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    /// Page title trimmed, host as fallback, truncated so the title bar never wraps.
    static func windowTitle(pageTitle: String?, url: URL?, fallback: String) -> String {
        let trimmed = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = trimmed.isEmpty ? (url?.host ?? fallback) : trimmed
        return base.count > 55 ? String(base.prefix(54)) + "…" : base
    }

    /// Safari's zoom steps.
    static let zoomSteps: [Double] = [0.5, 0.75, 0.85, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    static func zoomStep(after current: Double) -> Double { zoomSteps.first { $0 > current + 0.001 } ?? zoomSteps.last! }
    static func zoomStep(before current: Double) -> Double { zoomSteps.last { $0 < current - 0.001 } ?? zoomSteps.first! }

    /// Where a pull request opens: review requests on the diff, the user's own on the conversation.
    enum Landing { case conversation, files }

    static func url(for pr: PullRequest, landing: Landing) -> URL {
        switch landing {
        case .conversation: pr.url
        case .files: pr.url.appending(path: "files")
        }
    }
}
