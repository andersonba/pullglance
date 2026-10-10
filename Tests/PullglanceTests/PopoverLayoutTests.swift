import AppKit
import SwiftUI
import Testing
@testable import Pullglance

/// MenuBarExtra's window sizes itself to the content's ideal size, which is what `fittingSize` reports.
/// A ScrollView without an explicit height has an ideal height of zero there, so the lists vanish.
@MainActor
@Suite struct PopoverLayoutTests {
    private func loadedStore() async throws -> PRStore {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        return store
    }

    @Test func popoverWithDataHasRoomForTheLists() async throws {
        let store = try await loadedStore()
        let host = NSHostingView(rootView: PopoverView(store: store))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let height = host.fittingSize.height
        // Tabs (~44) + footer (~30) alone are under 100 points; five rows plus three headers need far more.
        #expect(height > 200, "popover ideal height was \(height)")
        #expect(height <= PopoverView.maxListHeight + 100, "popover must stay capped, got \(height)")
    }
}
