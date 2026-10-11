import SwiftUI

struct TabPicker: View {
    @Binding var selection: PopoverView.Tab
    let mineCount: Int
    let reviewCount: Int

    var body: some View {
        SegmentedControl(selection: $selection, segments: [
            .init(value: .mine, title: Text("My PRs", bundle: .app), count: mineCount),
            .init(value: .review, title: Text("To review", bundle: .app), count: reviewCount),
        ])
    }
}
