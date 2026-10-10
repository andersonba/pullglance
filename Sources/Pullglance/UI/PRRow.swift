import AppKit
import SwiftUI

struct PRRow: View {
    enum Leading { case ci, author }

    let pr: PullRequest
    let leading: Leading
    var showAuthor = false
    var teamLabel: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch leading {
            case .ci: CIDot(state: pr.ciState, url: pr.checksURL)
            case .author: AuthorInitial(login: pr.author)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
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
            if leading == .author {
                CIDot(state: pr.ciState, url: pr.checksURL)
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
                Circle().fill(color).frame(width: 16, height: 16)
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(glyphColor)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
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

    /// White on green/red/gray; a deep amber on yellow, where white washes out.
    private var glyphColor: Color {
        state == .pending ? Color(red: 0.45, green: 0.30, blue: 0.0) : .white
    }

    private var symbol: String {
        switch state {
        case .success: "checkmark"
        case .failure: "xmark"
        case .pending: "clock"
        case .none: "minus"
        }
    }
}

struct AuthorInitial: View {
    let login: String

    var body: some View {
        Text(verbatim: String(login.prefix(1)).uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(color))
            .padding(.top, 2)
    }

    /// Stable hue per login so the same author always gets the same color.
    private var color: Color {
        let hue = Double(abs(login.hashValue % 360)) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
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
        case .behindBase: .gray
        case .openThreads: .blue
        }
    }
}
