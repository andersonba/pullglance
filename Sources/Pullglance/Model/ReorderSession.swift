import Foundation

/// The transient state of a drag-to-reorder gesture: the order when it started, which slot was picked up,
/// and which slot the pointer is over now. Pure, so the arithmetic is testable without a view.
struct ReorderSession<Item: Equatable>: Equatable {
    let original: [Item]
    let source: Int
    var destination: Int

    /// The order as it should be displayed right now.
    var order: [Item] {
        var result = original
        let item = result.remove(at: source)
        result.insert(item, at: destination)
        return result
    }

    /// `toOffset` for `Array.move(fromOffsets:toOffset:)`, which counts positions before the removal.
    var insertionOffset: Int {
        destination > source ? destination + 1 : destination
    }

    /// Row index under a vertical position, clamped to the group.
    static func slot(at y: CGFloat, rowHeight: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let bounded = min(max(y, 0), CGFloat(count - 1) * rowHeight)
        return Int(bounded / rowHeight)
    }
}
