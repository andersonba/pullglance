import SwiftUI

struct SectionHeader: View {
    let title: String
    /// nil hides the count (used for "Via team" before it has been fetched).
    let count: Int?
    var expanded: Binding<Bool>? = nil
    var detail: String? = nil

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
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Color.primary.opacity(0.6))
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { expanded?.wrappedValue.toggle() }
    }
}
