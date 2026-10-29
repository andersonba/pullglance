import Foundation

/// A stacked pull request's neighbours, as GitHub lists them (`PullRequestStack`). Position 1 is the
/// closest to the base branch; `size` and every `position` are GitHub's and do not shift when a member
/// merges, so "2 of 3" keeps saying the truth after the first one lands.
enum StackMemberState: Equatable, Sendable { case open, draft, merged, closed }

struct StackMember: Equatable, Sendable {
    let position: Int
    let number: Int
    let title: String
    let state: StackMemberState
}

struct PullRequestStack: Equatable, Sendable {
    let number: Int
    let size: Int
    let baseRefName: String
    /// This pull request's own place in the stack.
    let position: Int
    /// In position order; may be shorter than `size` (the query asks for the first 30).
    let members: [StackMember]
}

/// A stack is scoped to its repository: the number is unique inside it, not across GitHub.
struct StackKey: Hashable, Sendable {
    let repo: String
    let number: Int
}

extension PullRequestStack {
    /// The stack as the pill's tooltip shows it: number and base on the first line, then one line per entry
    /// in position order, this pull request's own marked, and a state word for the ones not plainly open.
    func hoverText() -> String {
        var lines = [String(format: String(localized: "Stack #%lld on %@", bundle: .app), number, baseRefName)]
        for member in members {
            let mark = member.position == position ? "▸ " : "  "
            var line = "\(mark)\(member.position)  #\(member.number) \(member.title)"
            let state: String? = switch member.state {
            case .open: nil
            case .merged: String(localized: "merged", bundle: .app)
            case .closed: String(localized: "closed", bundle: .app)
            case .draft: String(localized: "draft", bundle: .app)
            }
            if let state { line += " · " + state }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
