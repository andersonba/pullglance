import AppKit
import SwiftUI
import Testing
@testable import Pullglance

/// Renders the popover to a PNG and prints the frames of the row scroll views, so sub-pixel layout can be
/// checked without screen-recording permission. The PNG path is printed; nothing is asserted on pixels.
@MainActor
@Suite struct PopoverSnapshotTests {
    @Test func rowsSitOnWholePixels() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()

        let host = NSHostingView(rootView: PopoverView(store: store).frame(width: 380))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI run its layout passes.
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded() }

        var fractional: [String] = []
        func walk(_ view: NSView, depth: Int) {
            if view is NSScrollView {
                let f = view.convert(view.bounds, to: nil)
                let line = String(format: "%@ y=%.3f h=%.3f", String(describing: type(of: view)), f.origin.y, f.height)
                // Half points are whole pixels on a 2x display; anything finer blurs hairlines.
                if (f.origin.y * 2) != (f.origin.y * 2).rounded() || (f.height * 2) != (f.height * 2).rounded() { fractional.append(line) }
                print("[snap] \(String(repeating: " ", count: depth))\(line)")
            }
            view.subviews.forEach { walk($0, depth: depth + 1) }
        }
        walk(host, depth: 0)

        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let url = FileManager.default.temporaryDirectory.appending(path: "pullglance-popover.png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        print("[snap] png: \(url.path) scale=\(rep.pixelsWide)/\(Int(host.bounds.width))")
        #expect(fractional.isEmpty, "row scroll views on fractional pixels: \(fractional)")
    }
}
