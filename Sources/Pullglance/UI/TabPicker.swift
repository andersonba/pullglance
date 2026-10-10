import SwiftUI

/// Two-segment picker styled like the approved prototype: a soft full-width track with a white,
/// slightly raised selected segment. The counts sit next to the labels in a lighter weight.
struct TabPicker: View {
    @Binding var selection: PopoverView.Tab
    let mineCount: Int
    let reviewCount: Int
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            segment(.mine, Text("My PRs", bundle: .app), count: mineCount)
            segment(.review, Text("To review", bundle: .app), count: reviewCount)
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func segment(_ tab: PopoverView.Tab, _ label: Text, count: Int) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selection = tab }
        } label: {
            HStack(spacing: 6) {
                label.fontWeight(.medium)
                Text(verbatim: "\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.system(size: 13))
            .foregroundStyle(selected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                        .matchedGeometryEffect(id: "selected", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
