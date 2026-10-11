import SwiftUI

/// Numbers appear only after a successful refresh. Loading shows an ellipsis, errors show a warning glyph
/// and keep the last known numbers. `isError` is the store's `lastError != nil`, so the glyph does not
/// flicker away while the next refresh is in flight.
struct MenuBarLabel: View {
    /// `badgeText` from the store: nil before the first data or when there is nothing to count.
    let text: String?
    /// Whether a refresh has ever succeeded; decides between "…" and nothing when `text` is nil.
    let hasData: Bool
    let isError: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isError ? "exclamationmark.triangle" : "arrow.triangle.pull")
            if let shown {
                Text(verbatim: shown).font(.system(size: 11, weight: .semibold))
            }
        }
    }

    private var shown: String? {
        if let text { return text }
        if !hasData, !isError { return "…" }
        return nil
    }
}
