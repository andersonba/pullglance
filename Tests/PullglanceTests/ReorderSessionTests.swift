import Foundation
import Testing
@testable import Pullglance

@Suite struct ReorderSessionTests {
    private let items = ["a", "b", "c", "d"]

    @Test func orderMovesTheSourceToTheDestination() {
        #expect(ReorderSession(original: items, source: 0, destination: 2).order == ["b", "c", "a", "d"])
        #expect(ReorderSession(original: items, source: 3, destination: 0).order == ["d", "a", "b", "c"])
        #expect(ReorderSession(original: items, source: 1, destination: 1).order == items)
    }

    @Test func insertionOffsetMatchesSwiftUIMoveSemantics() {
        for source in items.indices {
            for destination in items.indices {
                let session = ReorderSession(original: items, source: source, destination: destination)
                var moved = items
                moved.move(fromOffsets: IndexSet(integer: source), toOffset: session.insertionOffset)
                #expect(moved == session.order, "source \(source) → \(destination)")
            }
        }
    }

    @Test func slotClampsToTheGroup() {
        #expect(ReorderSession<String>.slot(at: -40, rowHeight: 44, count: 4) == 0)
        #expect(ReorderSession<String>.slot(at: 0, rowHeight: 44, count: 4) == 0)
        #expect(ReorderSession<String>.slot(at: 43.9, rowHeight: 44, count: 4) == 0)
        #expect(ReorderSession<String>.slot(at: 44, rowHeight: 44, count: 4) == 1)
        #expect(ReorderSession<String>.slot(at: 1000, rowHeight: 44, count: 4) == 3)
    }
}
