import SwiftUI

/// The app's segmented look: a soft full-width track with a white, slightly raised selected segment.
/// Used by the tab picker and the merge method picker so both read the same.
struct SegmentedControl<Value: Hashable>: View {
    struct Segment {
        let value: Value
        let title: Text
        var count: Int? = nil
        var enabled: Bool = true
    }

    @Binding var selection: Value
    let segments: [Segment]
    var fontSize: CGFloat = 13
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments.indices, id: \.self) { index in
                segment(segments[index])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func segment(_ segment: Segment) -> some View {
        let selected = selection == segment.value
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selection = segment.value }
        } label: {
            HStack(spacing: 6) {
                segment.title.fontWeight(.medium)
                if let count = segment.count {
                    Text(verbatim: "\(count)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.system(size: fontSize))
            .foregroundStyle(selected ? .primary : .secondary)
            .opacity(segment.enabled ? 1 : 0.35)
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
        .disabled(!segment.enabled)
        .help(segment.enabled ? Text(verbatim: "") : Text("Not allowed by this repository", bundle: .app))
    }
}
