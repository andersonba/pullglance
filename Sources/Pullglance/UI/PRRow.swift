import AppKit
import SwiftUI

struct PRRow: View {
    let pr: PullRequest
    /// Review tab: author name in the metadata and the author's initial on the right.
    var showAuthor = false
    var teamLabel: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // CI status always on the left, on both tabs.
            CIDot(state: pr.ciState, url: pr.checksURL)
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .help(Text(verbatim: pr.title))
                HStack(spacing: 4) {
                    Text(verbatim: "\(pr.repoName) #\(pr.number)")
                    if showAuthor { Text(verbatim: "· \(pr.author)") }
                    if let teamLabel { Text(verbatim: "· \(teamLabel)").foregroundStyle(.purple) }
                    Spacer(minLength: 8)
                    Text(pr.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                let rowPills = pills(for: pr)
                if !rowPills.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(rowPills, id: \.self) { PillView(pill: $0) }
                    }
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showAuthor {
                AuthorAvatar(login: pr.author, url: pr.authorAvatarURL)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { PopoverDismissal.open(pr.url) }
    }
}

struct CIDot: View {
    let state: CIState
    let url: URL

    var body: some View {
        Button {
            PopoverDismissal.open(url)
        } label: {
            ZStack {
                Circle().fill(color).frame(width: 14, height: 14)
                if state == .pending {
                    // A small dark dot reads better than any glyph on yellow; the pulse says "still running".
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Color.black.opacity(0.75))
                        .symbolEffect(.pulse, options: .repeating)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 3)
        .help(Text("Open checks", bundle: .app))
    }

    private var color: Color {
        switch state {
        case .success: .green
        case .failure: .red
        case .pending: .yellow
        case .none: Color.gray.opacity(0.35)
        }
    }


    private var symbol: String {
        switch state {
        case .success: "checkmark"
        case .failure: "xmark"
        case .pending: "circle.fill"
        case .none: "minus"
        }
    }
}

/// The author's GitHub picture, loaded through the shared URL cache; a neutral initial until it arrives
/// or when there is none (deleted account, offline).
struct AuthorAvatar: View {
    let login: String
    let url: URL?

    var body: some View {
        AsyncImage(url: url?.appending(queryItems: [URLQueryItem(name: "s", value: "40")])) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                initial
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(Circle())
        .padding(.top, 3)
        .help(Text(verbatim: login))
    }

    private var initial: some View {
        Text(verbatim: String(login.prefix(1)).uppercased())
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.primary.opacity(0.1)))
    }
}

struct PillView: View {
    let pill: Pill

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            // Pure tints read poorly on the translucent popover; pull the text toward the
            // primary color (darker in light mode, lighter in dark mode) and keep the fill soft.
            .foregroundStyle(tint.mix(with: .primary, by: 0.45))
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
    }

    private var title: String {
        switch pill {
        case .ciFailed: String(localized: "CI failed", bundle: .app)
        case .ciRunning: String(localized: "CI running", bundle: .app)
        case .changesRequested: String(localized: "Changes requested", bundle: .app)
        case .approved: String(localized: "Approved", bundle: .app)
        case .readyToMerge: String(localized: "Ready to merge", bundle: .app)
        case .awaitingReview: String(localized: "Awaiting review", bundle: .app)
        case .conflicts: String(localized: "Conflicts", bundle: .app)
        case .behindBase: String(localized: "Behind base", bundle: .app)
        case .openThreads(let count): String(localized: "\(count) open threads", bundle: .app)
        }
    }

    private var tint: Color {
        switch pill {
        case .ciFailed, .changesRequested, .conflicts: .red
        case .ciRunning: .yellow
        case .approved, .readyToMerge: .green
        case .awaitingReview: .orange
        case .behindBase, .openThreads: .gray
        }
    }
}
