import AppKit
import SwiftUI

/// `Pullglance --snapshot [directory]`: instead of living in the menu bar, the app fetches once with the
/// real `gh`, renders the popover (both tabs, light and dark) and every Settings tab to PNG files, prints
/// their paths and exits. For looking at the UI without a screen recording permission.
struct SnapshotOptions: Equatable {
    /// Per-user temporary directory, not the shared /tmp.
    static let defaultDirectory = FileManager.default.temporaryDirectory.appending(path: "pullglance-snapshots", directoryHint: .isDirectory)
    let directory: URL
    /// `--demo`: fictional pull requests from `DemoGH` and a throwaway defaults suite, plus the composed README
    /// hero (`hero.png`, the popover under a menu bar band). Nothing of the user's is read or written.
    var demo = false

    static func parse(_ arguments: [String]) -> SnapshotOptions? {
        guard let index = arguments.firstIndex(of: "--snapshot") else { return nil }
        let next = arguments.dropFirst(index + 1).first
        var options = SnapshotOptions(directory: defaultDirectory)
        if let next, !next.hasPrefix("-") {
            options = SnapshotOptions(directory: URL(fileURLWithPath: next, isDirectory: true))
        }
        options.demo = arguments.contains("--demo")
        return options
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
        var revealed: PullRequest.ID? = nil
        if options.demo {
            // One row pinned, one snoozed, one with its swipe tiles out: the hero shows the pieces, not an
            // empty state. The team sample stays collapsed so the popover ends within the hero's height.
            let direct = store.directList
            if let first = direct.first { store.pin(first) }
            revealed = store.directList.first?.id
            // The number on the menu bar counts only what the hero shows: the review requests. The snoozed
            // example lives on the other tab, so no number in the picture disagrees with another.
            store.badgeSections = [.needsYourReview]
            if let draft = store.mineGroups.drafts.first { store.snooze(draft) }
            // Avatars come from the network; have them in the cache before the first render.
            for pr in store.mine.value + store.direct.value {
                if let url = pr.authorAvatarURL { _ = await AvatarCache.shared.image(for: url.appending(queryItems: [URLQueryItem(name: "s", value: "40")])) }
            }
        }
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
        if options.demo {
            await write("hero") {
                let popover = try await ViewSnapshot.png(PopoverView(store: store, tab: .review, openRow: revealed), width: 380, appearance: .darkAqua, settle: .milliseconds(900))
                return try HeroComposer.compose(popover: popover, label: MenuBarLabel.render(text: store.badgeText, isError: false))
            }
            // The welcome window, one PNG per step, with gh pretending to be ready.
            let checker = RequirementChecker(locate: { URL(fileURLWithPath: "/opt/homebrew/bin/gh") },
                                             probe: { _ in (.success(Data("gh version 2.86.0\n".utf8)), .loggedIn(login: "octocat")) })
            await checker.checkOnce()
            for index in OnboardingStep.all.indices {
                await write("onboarding-\(index + 1)") {
                    try await ViewSnapshot.png(OnboardingView(store: store, checker: checker, model: OnboardingModel(step: index), finish: {}, quit: {}), width: 560, appearance: .aqua, settle: .milliseconds(600))
                }
            }
        }
        return written
    }
}

/// The README hero: a dark menu bar band with the app's item at the right, the popover hanging under it.
enum HeroComposer {
    static func compose(popover: Data, label: NSImage) throws -> Data {
        guard let popoverImage = NSImage(data: popover) else { throw CocoaError(.fileReadCorruptFile) }
        let scale: CGFloat = 2
        let popSize = NSSize(width: popoverImage.size.width, height: popoverImage.size.height)
        let margin: CGFloat = 36, band: CGFloat = 24, gap: CGFloat = 6
        let canvas = NSSize(width: popSize.width + margin * 2 + 120, height: band + gap + popSize.height + margin)
        let image = NSImage(size: NSSize(width: canvas.width * scale, height: canvas.height * scale), flipped: false) { rect in
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            let bandRect = NSRect(x: 0, y: canvas.height - band, width: canvas.width, height: band)
            let bandPath = NSBezierPath(roundedRect: bandRect.insetBy(dx: 0, dy: 0), xRadius: 10, yRadius: 10)
            NSGradient(colors: [NSColor(white: 0.19, alpha: 1), NSColor(white: 0.14, alpha: 1)])?.draw(in: bandPath, angle: -90)
            // Square off the band's bottom corners: the popover hangs from it.
            NSColor(white: 0.14, alpha: 1).setFill()
            NSRect(x: 0, y: bandRect.minY, width: canvas.width, height: 10).fill()
            // The item, highlighted as while the popover is open, and a clock to its right.
            let itemWidth = label.size.width + 12
            let itemX = canvas.width - margin - 72 - itemWidth
            NSColor(white: 1, alpha: 0.18).setFill()
            NSBezierPath(roundedRect: NSRect(x: itemX, y: bandRect.minY + 3, width: itemWidth, height: band - 6), xRadius: 5, yRadius: 5).fill()
            let tinted = label.copy() as! NSImage
            tinted.isTemplate = false
            tinted.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop); tinted.unlockFocus()
            tinted.draw(in: NSRect(x: itemX + 6, y: bandRect.minY + (band - label.size.height) / 2, width: label.size.width, height: label.size.height))
            let clock = NSAttributedString(string: "Wed 9:41", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white])
            clock.draw(at: NSPoint(x: canvas.width - margin - clock.size().width, y: bandRect.minY + (band - clock.size().height) / 2))
            // The popover, right-aligned under the item, with a soft shadow.
            let popX = canvas.width - margin - 60 - popSize.width
            let popRect = NSRect(x: popX, y: canvas.height - band - gap - popSize.height, width: popSize.width, height: popSize.height)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.set()
            NSColor(white: 0.12, alpha: 1).setFill()
            NSBezierPath(roundedRect: popRect, xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: popRect, xRadius: 12, yRadius: 12).addClip()
            popoverImage.draw(in: popRect)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }
}
