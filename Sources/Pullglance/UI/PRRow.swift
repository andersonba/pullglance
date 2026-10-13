import AppKit
import SwiftUI

struct PRRow: View {
    let pr: PullRequest
    let section: Section
    /// Review tab: author name in the metadata and the author's initial on the right.
    var showAuthor = false
    var teamLabel: String? = nil
    var isDormant = false
    /// Where a snoozed PR came from; shown in its metadata.
    var originSection: Section? = nil
    var actionState: ActionState? = nil
    var onAction: (PRAction) -> Void = { _ in }
    /// Reorder mode has no clicks; the row's tap stays off there.
    var handlesTap = true
    /// Reorder mode: a grip on the trailing edge, the content sliding over to make room.
    var showsGrip = false

    private var isRunning: Bool { if case .running = actionState { return true }; return false }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                title
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                // Kept in place while an action runs or has failed, only dimmed: dropping them changed the
                // row's height and shifted everything below for the duration of a refresh.
                if !rowPills.isEmpty, !isDormant {
                    HStack(spacing: 4) {
                        ForEach(rowPills, id: \.self) { PillView(pill: $0) }
                    }
                    .lineLimit(1)
                    .opacity(actionState == nil ? 1 : 0.35)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showAuthor {
                AuthorAvatar(login: pr.author, url: pr.authorAvatarURL)
            }
            if showsGrip {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .opacity(isDormant ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard handlesTap else { return }
            // A failed action reopens its modal; otherwise the row opens the PR in the review window
            // (review requests land on the diff, the user's own on the conversation). "Open on GitHub"
            // in the context menu keeps the browser.
            if case .failed(let action, _) = actionState { onAction(action); return }
            if let review = ReviewWindowController.shared {
                review.open(pr, landing: section.tab == .review ? .files : .conversation)
            } else {
                PopoverDismissal.open(pr.url)
            }
        }
        .contextMenu { PRRowMenu(section: section, isDormant: isDormant, actionState: actionState, onAction: onAction) }
    }

    /// Left column: CI dot normally; spinner, merged check or failure mark while an action is in play;
    /// a moon for snoozed rows.
    @ViewBuilder private var leading: some View {
        switch actionState {
        case .running:
            ProgressView().controlSize(.mini).frame(width: 16, height: 16).padding(.top, 3)
        case .succeeded:
            StatusDot(color: Color(red: 0.51, green: 0.31, blue: 0.87), symbol: "checkmark")
        case .failed:
            StatusDot(color: .red, symbol: "exclamationmark")
        case nil:
            if isDormant {
                Image(systemName: "moon.zzz").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16, height: 16).padding(.top, 3)
            } else {
                CIDot(state: pr.ciState, url: pr.checksURL)
            }
        }
    }

    /// The title carries the action's status so the row needs no extra line.
    private var title: Text {
        switch actionState {
        case .running(.merge): Text("Merging… ", bundle: .app).foregroundStyle(.secondary) + Text(verbatim: pr.title).foregroundStyle(.secondary)
        case .running(.comment): Text("Posting comment… ", bundle: .app).foregroundStyle(.secondary) + Text(verbatim: pr.title).foregroundStyle(.secondary)
        case .running: Text(verbatim: pr.title).foregroundStyle(.secondary)
        case .succeeded(.merge): Text("Merged · ", bundle: .app).foregroundStyle(.secondary) + Text(verbatim: pr.title).foregroundStyle(.secondary)
        case .succeeded: Text(verbatim: pr.title)
        case .failed(.merge, let message): Text("Merge failed: \(MergeFailure(ghMessage: message).shortDescription)", bundle: .app).foregroundStyle(.red)
        case .failed(.refresh, let message): Text("Refresh failed: \(message)", bundle: .app).foregroundStyle(.red)
        case .failed(_, let message): Text(verbatim: message).foregroundStyle(.red)
        case nil: Text(verbatim: pr.title).foregroundStyle(.primary)
        }
    }

}

/// The row's full action list: the context menu, and the "more" tile revealed by a swipe.
struct PRRowMenu: View {
    let section: Section
    var isDormant = false
    var actionState: ActionState? = nil
    var onAction: (PRAction) -> Void = { _ in }

    private var isRunning: Bool { if case .running = actionState { return true }; return false }

    var body: some View {
        ForEach(allActions(for: section, dormant: isDormant), id: \.self) { action in
            Button { onAction(action) } label: {
                switch action {
                case .merge: Label { Text("Merge…", bundle: .app) } icon: { Image(systemName: "arrow.triangle.merge") }
                case .comment: Label { Text("Comment…", bundle: .app) } icon: { Image(systemName: "text.bubble") }
                case .snooze: Label { Text(isDormant ? "Wake" : "Snooze", bundle: .app) } icon: { Image(systemName: isDormant ? "sun.max" : "moon.zzz") }
                case .open: Label { Text("Open on GitHub", bundle: .app) } icon: { Image(systemName: "arrow.up.forward.square") }
                case .copyLink: Label { Text("Copy link", bundle: .app) } icon: { Image(systemName: "link") }
                case .refresh: Label { Text("Refresh", bundle: .app) } icon: { Image(systemName: "arrow.clockwise") }
                }
            }
            .disabled(isRunning && (action == .merge || action == .comment || action == .refresh))
        }
    }
}

/// A plain colored circle with a white glyph, for action outcomes.
struct StatusDot: View {
    let color: Color
    let symbol: String
    var body: some View {
        ZStack {
            Circle().fill(color).frame(width: 14, height: 14)
            Image(systemName: symbol).font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white)
        }
        .padding(.top, 3)
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

/// The author's GitHub picture from `AvatarCache`; a neutral initial until it arrives or when there is none
/// (deleted account, offline). Reading the cache in `body` keeps a redrawn row from flashing the initial.
struct AuthorAvatar: View {
    let login: String
    let url: URL?
    var cache: AvatarCache = .shared

    private var sizedURL: URL? { url?.appending(queryItems: [URLQueryItem(name: "s", value: "40")]) }

    var body: some View {
        Group {
            if let sizedURL, let image = cache.cachedImage(sizedURL) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                initial
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(Circle())
        .padding(.top, 3)
        .help(Text(verbatim: login))
        .task(id: sizedURL) {
            guard let sizedURL else { return }
            _ = await cache.image(for: sizedURL)
        }
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
