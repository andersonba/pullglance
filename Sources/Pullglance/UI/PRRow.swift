import AppKit
import SwiftUI

struct PRRow: View {
    let pr: PullRequest
    let section: Section
    /// Review tab: author name in the metadata and the author's initial on the right.
    var showAuthor = false
    var teamLabel: String? = nil
    var isDormant = false
    /// A timed snooze's end, shown as what is left; nil on rows asleep until activity.
    var snoozedUntil: Date? = nil
    /// Back from a timed snooze since the last refresh.
    var isWoke = false
    /// For the menu: the length a snoozed row sleeps for.
    var snoozeLength: SnoozeDuration? = nil
    /// Pinned rows carry a small pin before the title: the section says it, the mark travels with the row.
    var isPinned = false
    var actionState: ActionState? = nil
    var onAction: (PRAction) -> Void = { _ in }
    /// nil is "until activity": the way to drop a length.
    var onSnoozeFor: (SnoozeDuration?) -> Void = { _ in }
    /// Reorder mode has no clicks; the row's tap stays off there.
    var handlesTap = true
    /// Reorder mode: a grip on the trailing edge, the content sliding over to make room.
    var showsGrip = false
    /// A click on the avatar narrows the lists to this author (see `PRStore.toggleQuickAuthor`); nil keeps
    /// the avatar inert (reorder mode).
    var onAuthorTap: (() -> Void)? = nil
    /// Whether the lists are already narrowed to this author, for the hint and the ring.
    var isAuthorFiltered = false
    /// A click on the repository name narrows the lists to this repository; nil keeps it plain text.
    var onRepoTap: (() -> Void)? = nil
    var isRepoFiltered = false

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
                    HStack(spacing: 0) {
                        if let onRepoTap {
                            RepoFilterLink(name: pr.repoName, isActive: isRepoFiltered, action: onRepoTap)
                        } else {
                            Text(verbatim: pr.repoName)
                        }
                        Text(verbatim: " #\(pr.number)")
                    }
                    if showAuthor { Text(verbatim: "· \(pr.author)") }
                    if let teamLabel { Text(verbatim: "· \(teamLabel)").foregroundStyle(.purple) }
                    Spacer(minLength: 8)
                    if let size = diffSizeText(additions: pr.additions, deletions: pr.deletions) {
                        // "+24 −44": the size of the thing, at a glance, in the diff's own colors.
                        DiffSizeText(text: size)
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                    }
                    Text(pr.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // Review rows lead with why they are where they are (see `reviewSignal`).
                let reason: [Pill] = section.tab == .review ? reviewSignal(for: pr, now: Date()).map { [.reason($0)] } ?? [] : []
                let rowPills = (isWoke ? [Pill.woke] : []) + reason + pills(for: pr)
                // Kept in place while an action runs or has failed, only dimmed: dropping them changed the
                // row's height and shifted everything below for the duration of a refresh.
                if !rowPills.isEmpty, !isDormant {
                    // Wraps to a second line when they do not fit, rather than truncating each pill.
                    PillFlow(spacing: 4, lineSpacing: 3) {
                        ForEach(rowPills, id: \.self) { PillView(pill: $0).fixedSize() }
                    }
                    .opacity(actionState == nil ? 1 : 0.35)
                } else if isDormant, let snoozedUntil {
                    SnoozeLeftPill(until: snoozedUntil).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showAuthor {
                if let onAuthorTap {
                    AuthorFilterButton(login: pr.author, url: pr.authorAvatarURL, isActive: isAuthorFiltered, action: onAuthorTap)
                } else {
                    AuthorAvatar(login: pr.author, url: pr.authorAvatarURL)
                }
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
            if ReviewSettingsStore.shared.settings.windowEnabled, let review = ReviewWindowController.shared {
                review.open(pr, landing: section.tab == .review ? .files : .conversation)
            } else {
                PopoverDismissal.open(pr.url)
            }
        }
        .contextMenu { PRRowMenu(section: section, isDormant: isDormant, isPinned: isPinned, offersMerge: pr.offersAutoMerge, autoMergeOn: pr.autoMergeMethod != nil, actionState: actionState, snoozeLength: snoozeLength, onAction: onAction, onSnoozeFor: onSnoozeFor) }
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

    /// Merge means three things, by configuration: a merge, a place in the queue, or a request for later.
    private var mergeProgress: Text {
        if pr.usesMergeQueue { return Text("Adding to the queue… ", bundle: .app) }
        if pr.offersAutoMerge { return Text("Enabling auto-merge… ", bundle: .app) }
        return Text("Merging… ", bundle: .app)
    }

    private var mergeDone: Text {
        if pr.usesMergeQueue { return Text("Queued · ", bundle: .app) }
        if pr.offersAutoMerge { return Text("Auto-merge on · ", bundle: .app) }
        return Text("Merged · ", bundle: .app)
    }

    private var pinMark: Text {
        guard isPinned else { return Text(verbatim: "") }
        return Text(Image(systemName: "pin.fill")).font(.system(size: 9)).foregroundStyle(.orange) + Text(verbatim: " ")
    }

    /// The title carries the action's status so the row needs no extra line.
    private var title: Text {
        switch actionState {
        case .running(.merge): mergeProgress.foregroundStyle(.secondary) + Text(verbatim: pr.title).foregroundStyle(.secondary)
        case .running(.disableAutoMerge): Text("Disabling auto-merge… ", bundle: .app).foregroundStyle(.secondary) + Text(verbatim: pr.title).foregroundStyle(.secondary)
        case .running(.comment): Text("Posting comment… ", bundle: .app).foregroundStyle(.secondary) + Text(verbatim: pr.title).foregroundStyle(.secondary)
        case .running: Text(verbatim: pr.title).foregroundStyle(.secondary)
        case .succeeded(.merge): mergeDone.foregroundStyle(.secondary) + Text(verbatim: pr.title).foregroundStyle(.secondary)
        case .succeeded: Text(verbatim: pr.title)
        case .failed(.merge, let message): Text("Merge failed: \(MergeFailure(ghMessage: message).shortDescription)", bundle: .app).foregroundStyle(.red)
        case .failed(.refresh, let message): Text("Refresh failed: \(message)", bundle: .app).foregroundStyle(.red)
        case .failed(_, let message): Text(verbatim: message).foregroundStyle(.red)
        case nil: pinMark + Text(verbatim: pr.title).foregroundStyle(.primary)
        }
    }

}

/// The row's full action list: the context menu, and the "more" tile revealed by a swipe.
struct PRRowMenu: View {
    let section: Section
    var isDormant = false
    var isPinned = false
    /// "Merge when checks pass" outside Ready to merge (see `PullRequest.offersAutoMerge`).
    var offersMerge = false
    var autoMergeOn = false
    var actionState: ActionState? = nil
    /// On a snoozed row, which length it sleeps for (nil: until activity); the submenu checks it.
    var snoozeLength: SnoozeDuration? = nil
    var onAction: (PRAction) -> Void = { _ in }
    var onSnoozeFor: (SnoozeDuration?) -> Void = { _ in }

    private var isRunning: Bool { if case .running = actionState { return true }; return false }

    var body: some View {
        ForEach(allActions(for: section, dormant: isDormant, offersMerge: offersMerge, autoMergeOn: autoMergeOn), id: \.self) { action in
            Button { onAction(action) } label: {
                switch action {
                case .merge: Label { Text(offersMerge ? "Merge when checks pass…" : "Merge…", bundle: .app) } icon: { Image(systemName: "arrow.triangle.merge") }
                case .disableAutoMerge: Label { Text("Disable auto-merge", bundle: .app) } icon: { Image(systemName: "arrow.triangle.merge") }
                case .pin: Label { Text(isPinned ? "Unpin" : "Pin to top", bundle: .app) } icon: { Image(systemName: isPinned ? "pin.slash" : "pin") }
                case .comment: Label { Text("Comment…", bundle: .app) } icon: { Image(systemName: "text.bubble") }
                case .approve: Label { Text("Approve…", bundle: .app) } icon: { Image(systemName: "checkmark.circle") }
                case .snooze: Label { Text(isDormant ? "Wake" : "Snooze", bundle: .app) } icon: { Image(systemName: isDormant ? "sun.max" : "moon.zzz") }
                case .open: Label { Text("Open on GitHub", bundle: .app) } icon: { Image(systemName: "arrow.up.forward.square") }
                case .copyLink: Label { Text("Copy link", bundle: .app) } icon: { Image(systemName: "link") }
                case .refresh: Label { Text("Refresh", bundle: .app) } icon: { Image(systemName: "arrow.clockwise") }
                }
            }
            .disabled(isRunning && (action == .merge || action == .comment || action == .refresh || action == .disableAutoMerge))
            // The key shown next to the item, as every Mac menu does; the key itself is handled by the
            // popover's monitor on the focused or hovered row, not registered here.
            .keyboardShortcut(Self.shortcut(for: action))
            if action == .snooze {
                // Right under Snooze: the timed ones. Under Wake it reads as "change the snooze", so it also
                // offers the plain kind, and checks what the row has now.
                Menu {
                    if isDormant {
                        snoozeItem(nil, checked: snoozeLength == nil)
                        Divider()
                    }
                    ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                        snoozeItem(duration, checked: isDormant && snoozeLength == duration)
                    }
                } label: {
                    Label { Text("Snooze for…", bundle: .app) } icon: { Image(systemName: "clock") }
                }
            }
        }
    }

    private static func shortcut(for action: PRAction) -> KeyboardShortcut? {
        switch action {
        case .pin: KeyboardShortcut("p", modifiers: [])
        case .snooze: KeyboardShortcut("s", modifiers: [])
        case .comment: KeyboardShortcut("c", modifiers: [])
        case .merge: KeyboardShortcut("m", modifiers: [])
        case .open: KeyboardShortcut("o", modifiers: [])
        case .refresh: KeyboardShortcut("r", modifiers: [])
        case .copyLink: KeyboardShortcut("c", modifiers: .command)
        case .approve, .disableAutoMerge: nil
        }
    }

    private func snoozeItem(_ duration: SnoozeDuration?, checked: Bool) -> some View {
        Toggle(isOn: Binding(get: { checked }, set: { _ in onSnoozeFor(duration) })) {
            if let duration { Text(verbatim: duration.label) } else { Text("Until activity", bundle: .app) }
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
/// The repository name as a quiet link: accent color under the pointer and while the lists are narrowed to it.
struct RepoFilterLink: View {
    let name: String
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: name)
                .foregroundStyle(isActive || hovering ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .underline(hovering, color: Color.accentColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .help(isActive ? Text("Show all repositories", bundle: .app) : Text("Show only \(name)", bundle: .app))
    }
}

/// The avatar as a button: a ring under the pointer, a filled ring while the lists are narrowed to this person.
struct AuthorFilterButton: View {
    let login: String
    let url: URL?
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            AuthorAvatar(login: login, url: url)
                .overlay(alignment: .top) {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                        .offset(y: 1)
                        .opacity(isActive || hovering ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .help(isActive ? Text("Show all authors", bundle: .app) : Text("Show only \(login)", bundle: .app))
        .accessibilityLabel(isActive ? Text("Show all authors", bundle: .app) : Text("Show only \(login)", bundle: .app))
    }
}

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

/// Left-to-right flow that wraps: pills keep their size and the row grows a line instead of truncating.
struct PillFlow: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width == .infinity ? maxX : width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Additions in green, deletions in red, monospaced digits so columns of rows line up.
struct DiffSizeText: View {
    let text: String

    var body: some View {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        HStack(spacing: 3) {
            Text(verbatim: parts.first ?? text).foregroundStyle(.green.mix(with: .primary, by: 0.3))
            if parts.count > 1 { Text(verbatim: parts[1]).foregroundStyle(.red.mix(with: .primary, by: 0.25)) }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .fixedSize()
        .accessibilityLabel(Text(verbatim: text))
    }
}

struct PillView: View {
    let pill: Pill

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 9.5, weight: .regular))
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
        case .reason(.reReview): String(localized: "Re-review", bundle: .app)
        case .reason(.newActivity): String(localized: "New activity", bundle: .app)
        case .reason(.quick(let files)): String(format: String(localized: "Quick · %lld files", bundle: .app), files)
        case .reason(.waiting(let days)): String(format: String(localized: "Waiting %lldd", bundle: .app), days)
        case .ciFailed: String(localized: "CI failed", bundle: .app)
        case .ciRunning: String(localized: "CI running", bundle: .app)
        case .changesRequested: String(localized: "Changes requested", bundle: .app)
        case .approved: String(localized: "Approved", bundle: .app)
        case .readyToMerge: String(localized: "Ready to merge", bundle: .app)
        case .inMergeQueue(let position): String(localized: "In queue · \(position)", bundle: .app)
        case .autoMerge: String(localized: "Auto-merge", bundle: .app)
        case .awaitingReview: String(localized: "Awaiting review", bundle: .app)
        case .conflicts: String(localized: "Conflicts", bundle: .app)
        case .behindBase: String(localized: "Behind base", bundle: .app)
        case .openThreads(let count): String(localized: "\(count) open threads", bundle: .app)
        case .woke: String(localized: "Woke", bundle: .app)
        }
    }

    private var tint: Color {
        switch pill {
        case .reason: .blue
        case .ciFailed, .changesRequested, .conflicts: .red
        case .ciRunning: .yellow
        case .approved, .readyToMerge: .green
        case .woke: .orange
        case .inMergeQueue, .autoMerge: .purple
        case .awaitingReview: .orange
        case .behindBase, .openThreads: .gray
        }
    }
}

extension SnoozeDuration {
    var label: String {
        switch self {
        case .thirtyMinutes: String(localized: "30 min", bundle: .app)
        case .oneHour: String(localized: "1 hour", bundle: .app)
        case .threeHours: String(localized: "3 hours", bundle: .app)
        case .oneDay: String(localized: "1 day", bundle: .app)
        case .oneWeek: String(localized: "1 week", bundle: .app)
        }
    }
}

/// "25 min left" on a snoozed row, in the pills' place. Counts from the moment the row is drawn; the next
/// refresh redraws it.
struct SnoozeLeftPill: View {
    let until: Date

    var body: some View {
        let left = Duration.seconds(max(60, until.timeIntervalSinceNow))
            .formatted(.units(allowed: [.weeks, .days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 1))
        Text("\(left) left", bundle: .app)
            .font(.system(size: 10.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .foregroundStyle(Color.orange.mix(with: .primary, by: 0.45))
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5))
    }
}
