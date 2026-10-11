import SwiftUI

struct SectionHeader: View {
    let title: String
    /// nil hides the count (used for "Via team" before it has been fetched).
    let count: Int?
    var expanded: Binding<Bool>? = nil
    var detail: String? = nil
    /// A small action shown only while the pointer is over the header (e.g. "Sort by update").
    var hoverAction: HoverAction? = nil

    struct HoverAction {
        let title: String
        /// Shown all the time instead of only under the pointer (reorder mode).
        var alwaysVisible = false
        let perform: () -> Void
    }

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let expanded {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Text(verbatim: count.map { "\(title) · \($0)" } ?? title)
                .textCase(.uppercase)
            if let detail {
                Spacer()
                Text(verbatim: detail).fontWeight(.regular)
            }
            if let hoverAction {
                if detail == nil { Spacer() }
                // Quiet on purpose: a secondary label, underlined only under the pointer.
                Button(action: hoverAction.perform) {
                    Text(verbatim: hoverAction.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering || hoverAction.alwaysVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.12), value: hovering)
                .accessibilityHidden(!(hovering || hoverAction.alwaysVisible))
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Color.primary.opacity(0.6))
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { expanded?.wrappedValue.toggle() }
    }
}
