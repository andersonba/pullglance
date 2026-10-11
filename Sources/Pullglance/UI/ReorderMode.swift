import SwiftUI

/// Replaces the footer while reordering: what to do, and the way out (also Esc and closing the popover).
struct ReorderFooter: View {
    let done: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.secondary)
            Text("Drag rows to reorder", bundle: .app)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: done) { Text("Done", bundle: .app) }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            Button(action: done) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
