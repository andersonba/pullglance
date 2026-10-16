import AppKit
import SwiftUI
import Testing
@testable import Pullglance

/// Reads every string the accessibility tree exposes under a view.
@MainActor
func renderedStrings(_ view: NSView) -> [String] {
    var out: [String] = []
    func walk(_ element: Any) {
        if let s = (element as? NSAccessibilityProtocol)?.accessibilityValue() as? String, !s.isEmpty { out.append(s) }
        if let s = (element as? NSAccessibilityProtocol)?.accessibilityLabel(), !s.isEmpty { out.append(s) }
        if let s = (element as? NSAccessibilityProtocol)?.accessibilityTitle(), !s.isEmpty { out.append(s) }
        for child in (element as? NSAccessibilityProtocol)?.accessibilityChildren() ?? [] { walk(child) }
    }
    walk(view)
    return out
}

/// Counts pixels by hue class in a rendered view: the pills are the only saturated colors in a row.
@MainActor
func pillPixels(_ view: NSView) -> (green: Int, orange: Int) {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    var green = 0, orange = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
            if g > r + 0.12 && g > b + 0.12 { green += 1 }
            if r > g + 0.12 && r > b + 0.25 { orange += 1 }
        }
    }
    return (green, orange)
}

@MainActor
@Suite struct RowRefreshRenderTests {
    @Test func rowPillsFollowARefreshedPullRequest() async throws {
        let gh = FakeGH()
        await gh.set(.success(envelope(nodes: [node(number: 7, ci: "SUCCESS", decision: "REVIEW_REQUIRED"), node(number: 8, ci: "FAILURE", decision: nil)])), for: SearchQuery.mine)
        await gh.set(.success(envelope(nodes: [])), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        #expect(store.mineGroups.waitingForReview.map(\.number) == [7])
        let host = NSHostingView(rootView: PopoverView(store: store).frame(width: 380))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded() }
        let before = pillPixels(host)
        print("[render] before green=\(before.green) orange=\(before.orange)")
        let baselineGreen = before.green

        // The row moves from Waiting for review to Ready to merge; its pills must turn green.
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: 7, ci: "SUCCESS", decision: "APPROVED"))), number: 7)
        _ = await store.refreshOne(store.mine.value.first { $0.number == 7 }!)
        #expect(store.mineGroups.readyToMerge.map(\.number) == [7])
        for _ in 0..<8 { try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded() }
        let after = pillPixels(host)
        print("[render] after green=\(after.green) orange=\(after.orange)")
        #expect(after.green > baselineGreen + 50)
        #expect(after.orange < before.orange)
    }
}
