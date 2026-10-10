import AppKit
import SwiftUI

struct EmptyStateView: View {
    enum Kind: Equatable {
        /// No open PRs of the user's own ("My PRs" tab).
        case allClear
        case ghNotFound
        case notAuthenticated
        case network(String)
    }

    let kind: Kind
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(tint)
                .padding(.bottom, 4)
            switch kind {
            case .allClear:
                Text("All clear", bundle: .app).font(.headline)
                Text("No open PRs of yours.", bundle: .app)
            case .ghNotFound:
                Text("gh CLI not found", bundle: .app).font(.headline)
                Text("Looked in /opt/homebrew/bin, /usr/local/bin and PATH.", bundle: .app).font(.caption)
                Text(verbatim: "brew install gh").font(.system(.caption, design: .monospaced))
                Button { NSWorkspace.shared.open(URL(string: "https://cli.github.com")!) } label: {
                    Text("Install with Homebrew", bundle: .app)
                }
                .buttonStyle(.borderedProminent)
            case .notAuthenticated:
                Text("gh is not logged in to github.com", bundle: .app).font(.headline)
                Text("Run this in Terminal, then refresh:", bundle: .app).font(.caption)
                Text(verbatim: "gh auth login")
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                Button {
                    let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                    NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
                } label: {
                    Text("Open Terminal", bundle: .app)
                }
                .buttonStyle(.borderedProminent)
            case .network(let message):
                Text("Couldn't reach GitHub", bundle: .app).font(.headline)
                Text(verbatim: message).font(.caption).lineLimit(3)
                if let retry {
                    Button(action: retry) { Text("Try again", bundle: .app) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }

    private var symbol: String {
        switch kind {
        case .allClear: "checkmark.circle"
        case .ghNotFound, .notAuthenticated: "exclamationmark.triangle"
        case .network: "wifi.exclamationmark"
        }
    }

    private var tint: Color {
        kind == .allClear ? .green : .yellow
    }
}

struct SkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            bar(0.4)
            bar(1)
            bar(0.7)
            bar(0.35).padding(.top, 12)
            bar(1)
            bar(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bar(_ fraction: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary)
                .frame(width: proxy.size.width * fraction, height: 10)
        }
        .frame(height: 10)
    }
}
