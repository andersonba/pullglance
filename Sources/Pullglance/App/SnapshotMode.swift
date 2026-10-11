import AppKit
import SwiftUI

/// `Pullglance --snapshot [directory]`: instead of living in the menu bar, the app fetches once with the
/// real `gh`, renders the popover (both tabs, light and dark) and every Settings tab to PNG files, prints
/// their paths and exits. For looking at the UI without a screen recording permission.
struct SnapshotOptions: Equatable {
    /// Per-user temporary directory, not the shared /tmp.
    static let defaultDirectory = FileManager.default.temporaryDirectory.appending(path: "pullglance-snapshots", directoryHint: .isDirectory)
    let directory: URL

    static func parse(_ arguments: [String]) -> SnapshotOptions? {
        guard let index = arguments.firstIndex(of: "--snapshot") else { return nil }
        let next = arguments.dropFirst(index + 1).first
        if let next, !next.hasPrefix("-") {
            return SnapshotOptions(directory: URL(fileURLWithPath: next, isDirectory: true))
        }
        return SnapshotOptions(directory: defaultDirectory)
    }
}

/// Renders a SwiftUI view to PNG bytes by hosting it in an off-screen window. Works for AppKit-backed
/// pieces too (the row scroll views), as long as the window gets a few layout and display passes first.
@MainActor
enum ViewSnapshot {
    static func png<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, appearance: NSAppearance.Name = .darkAqua, settle: Duration = .milliseconds(350)) async throws -> Data {
        // The real popover sits on the menu bar window's material; off screen there is none, and white
        // text on a transparent PNG is invisible, so paint the window background behind the view.
        let host = NSHostingView(rootView: view.frame(width: width, height: height).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: height ?? 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        window.setContentSize(host.fittingSize)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let passes = 6
        for _ in 0..<passes {
            try await Task.sleep(for: settle / passes)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
        }
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SnapshotError.noBitmap }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.noBitmap }
        return data
    }

    enum SnapshotError: Error { case noBitmap }
}

@MainActor
enum SnapshotRunner {
    /// Fetches once, renders everything, writes the files. Returns what was written.
    static func run(_ options: SnapshotOptions, store: PRStore) async -> [URL] {
        try? FileManager.default.createDirectory(at: options.directory, withIntermediateDirectories: true)
        await store.refresh()
        var written: [URL] = []
        func write(_ name: String, _ make: () async throws -> Data) async {
            do {
                let url = options.directory.appending(path: "\(name).png")
                try await make().write(to: url, options: .atomic)
                written.append(url)
                print(url.path)
            } catch {
                FileHandle.standardError.write(Data("snapshot \(name) failed: \(error)\n".utf8))
            }
        }
        for (scheme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            for tab in [PopoverView.Tab.mine, .review] {
                await write("popover-\(tab)-\(scheme)") {
                    try await ViewSnapshot.png(PopoverView(store: store, tab: tab), width: 380, appearance: appearance)
                }
            }
        }
        for tab in SettingsTab.allCases {
            SettingsSelection.shared.tab = tab
            await write("settings-\(tab.rawValue)") {
                try await ViewSnapshot.png(SettingsView(store: store), width: 520, appearance: .aqua)
            }
        }
        return written
    }
}
