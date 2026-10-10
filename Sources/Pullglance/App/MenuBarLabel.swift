import SwiftUI

/// Number appears only after a successful refresh. Loading shows an ellipsis, errors show a warning glyph
/// and keep the last known number. `isError` is the store's `lastError != nil`, so the glyph does not
/// flicker away while the next refresh is in flight.
struct MenuBarLabel: View {
    let badgeCount: Int?
    let isError: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isError ? "exclamationmark.triangle" : "arrow.triangle.pull")
            if let text {
                Text(verbatim: text).font(.system(size: 11, weight: .semibold))
            }
        }
    }

    private var text: String? {
        if let badgeCount, badgeCount > 0 { return "\(badgeCount)" }
        if badgeCount == nil, !isError { return "…" }
        return nil
    }
}
