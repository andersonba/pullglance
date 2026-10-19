import SwiftUI

struct QuickFilterBar: View {
    let items: [QuickFilterItem]
    @Binding var selection: Section?

    var body: some View {
        // Fixed-size chips in a horizontal scroller: never truncated, never taller than one row.
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(items) { item in
                    Chip(item: item, isSelected: selection == item.section) {
                        selection = (selection == item.section) ? nil : item.section
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.never)
        .frame(height: 24)
        .padding(.bottom, 6)
        .transaction { $0.animation = nil }
        // Plain number keys isolate a section by position; 0 goes back to All.
        .background {
            Group {
                Button { selection = nil } label: { EmptyView() }.keyboardShortcut("0", modifiers: [])
                ForEach(Array(items.dropFirst().prefix(4).enumerated()), id: \.offset) { index, item in
                    Button { selection = item.section } label: { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                }
            }
            .buttonStyle(.plain)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }
}

private struct Chip: View {
    let item: QuickFilterItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let section = item.section {
                    Circle().fill(dot(for: section)).frame(width: 6, height: 6)
                }
                Text(verbatim: item.section?.shortTitle ?? String(localized: "All", bundle: .app))
                if let count = item.count {
                    Text(verbatim: "\(count)").fontWeight(.semibold).monospacedDigit()
                }
            }
            .font(.system(size: 10.5))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 0.5))
            .opacity(item.count == 0 ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    private var isAll: Bool { item.section == nil }
    private var foreground: Color { isSelected && !isAll ? Color(nsColor: .windowBackgroundColor) : .primary }
    private var background: Color {
        if !isSelected { return Color.primary.opacity(0.07) }
        return isAll ? Color(nsColor: .windowBackgroundColor) : .primary
    }
    private var border: Color { isSelected && isAll ? Color.primary.opacity(0.2) : .clear }

    private func dot(for section: Section) -> Color {
        switch section {
        case .needsAction: .red
        case .readyToMerge: .green
        case .waitingForReview: .orange
        case .drafts: .gray
        case .needsYourReview: .blue
        case .needsTeamsReview: .purple
        case .snoozedMine, .snoozedReview: .gray
        case .pinnedMine, .pinnedReview: .yellow
        case .assignedMine: .teal
        }
    }
}
