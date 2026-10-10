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
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { expanded?.wrappedValue.toggle() }
    }
}
