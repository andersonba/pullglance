import AppKit
import SwiftUI

/// Confirmation before merging. Shown inside the popover (sheets do not attach well to the menu bar window).
struct MergeConfirmView: View {
    let pr: PullRequest
    @Bindable var store: PRStore
    /// Called with the chosen options to start the merge, or nil on cancel. The modal closes either way;
    /// the row shows the progress and the outcome.
    let onDone: ((method: MergeMethod, deleteBranch: Bool)?) -> Void

    @State private var method: MergeMethod
    @State private var deleteBranch: Bool
    @State private var failure: MergeFailure?

    init(pr: PullRequest, store: PRStore, previousFailure: String? = nil, onDone: @escaping ((method: MergeMethod, deleteBranch: Bool)?) -> Void) {
        self.pr = pr
        self.store = store
        self.onDone = onDone
        _method = State(initialValue: pr.mergeOptions.preselected)
        _deleteBranch = State(initialValue: false)
        _failure = State(initialValue: mergePreflight(pr) ?? previousFailure.map(MergeFailure.init(ghMessage:)))
    }

    private let running = false
    private var blocked: Bool { failure != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Merge #\(pr.number)?", bundle: .app).font(.headline)
            (Text(verbatim: pr.title).foregroundStyle(.secondary) + Text(verbatim: " → ") + Text(verbatim: pr.baseRefName).fontWeight(.semibold))
                .font(.caption)
                .lineLimit(2)

            SegmentedControl(
                selection: $method,
                segments: MergeMethod.allCases.map { candidate in
                    .init(value: candidate, title: Text(verbatim: label(candidate)), enabled: pr.mergeOptions.allowed.contains(candidate))
                },
                fontSize: 12
            )
            .disabled(running)

            if pr.mergeOptions.deleteBranchOnMerge {
                // GitHub deletes it and retargets anything stacked on it; asking gh to delete it too would
                // close those pull requests instead.
                Label { Text("The repository deletes the branch after merge.", bundle: .app) } icon: { Image(systemName: "arrow.triangle.branch") }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle(isOn: $deleteBranch) { Text("Delete branch after merge", bundle: .app) }
                    .toggleStyle(.checkbox)
                    .disabled(running)
            }

            if let failure {
                Label {
                    Text(verbatim: describe(failure))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button { onDone(nil) } label: { Text("Cancel", bundle: .app) }
                    .keyboardShortcut(.cancelAction)
                Button { onDone((method, requestedBranchDeletion(options: pr.mergeOptions, toggle: deleteBranch))) } label: { Text(verbatim: confirmLabel) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(blocked && !isRetryable)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }

    /// Preflight blocks are final; a failure that came back from GitHub can be retried.
    private var isRetryable: Bool {
        guard let failure else { return true }
        switch failure {
        case .temporarilyUnavailable, .changedSinceShown, .other: return true
        default: return mergePreflight(pr) == nil
        }
    }

    private var confirmLabel: String {
        if failure != nil, isRetryable, mergePreflight(pr) == nil { return String(localized: "Retry", bundle: .app) }
        switch method {
        case .merge: return String(localized: "Merge", bundle: .app)
        case .squash: return String(localized: "Squash and merge", bundle: .app)
        case .rebase: return String(localized: "Rebase and merge", bundle: .app)
        }
    }

    private func label(_ method: MergeMethod) -> String {
        switch method {
        case .merge: String(localized: "Merge", bundle: .app)
        case .squash: String(localized: "Squash", bundle: .app)
        case .rebase: String(localized: "Rebase", bundle: .app)
        }
    }


    private func describe(_ failure: MergeFailure) -> String {
        switch failure {
        case .draft: String(localized: "This PR is a draft. Mark it ready for review first.", bundle: .app)
        case .conflicts: String(localized: "This PR has merge conflicts. Resolve them on the branch first.", bundle: .app)
        case .checksNotPassing: String(localized: "Required checks are failing or still running.", bundle: .app)
        case .reviewRequired: String(localized: "Branch protection requires an approving review.", bundle: .app)
        case .changedSinceShown: String(localized: "The branch changed since this list was loaded. Refresh and look again.", bundle: .app)
        case .temporarilyUnavailable: String(localized: "GitHub could not merge right now. Try again in a few seconds.", bundle: .app)
        case .alreadyMerged: String(localized: "Already merged.", bundle: .app)
        case .closed: String(localized: "This PR is closed.", bundle: .app)
        case .notAllowed: String(localized: "You do not have permission to merge here.", bundle: .app)
        case .other(let message): message
        }
    }
}

/// Comment on a PR without leaving the popover.
struct CommentView: View {
    let pr: PullRequest
    @Bindable var store: PRStore
    let onDone: (ActionResult?) -> Void

    @State private var body_ = ""
    @State private var running = false
    @State private var error: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comment on #\(pr.number)", bundle: .app).font(.headline)
            Text(verbatim: pr.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            TextEditor(text: $body_)
                .font(.system(size: 12))
                .frame(height: 90)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                .focused($focused)
                .disabled(running)
            if let error {
                Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Text("⌘↩ to send", bundle: .app).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button { onDone(nil) } label: { Text("Cancel", bundle: .app) }
                    .keyboardShortcut(.cancelAction)
                    .disabled(running)
                Button(action: send) {
                    if running { ProgressView().controlSize(.small).frame(width: 50) } else { Text("Send", bundle: .app) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(running || body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .onAppear { focused = true }
    }

    private func send() {
        running = true
        error = nil
        Task {
            let result = await store.comment(pr, body: body_)
            running = false
            switch result {
            case .success: onDone(.success())
            case .failure(let message): error = message
            }
        }
    }
}

/// Short confirmation at the bottom of the popover.
struct ToastView: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}
