import AppKit
import Foundation
import Testing
@testable import Pullglance

/// A valid 1×1 PNG so the cache can decode what the fake network returns.
private func tinyPNG(gray: UInt8 = 0x80) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.setColor(NSColor(white: CGFloat(gray) / 255, alpha: 1), atX: 0, y: 0)
    return rep.representation(using: .png, properties: [:])!
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "avatar-tests-\(UUID().uuidString)")
}

private actor FetchLog {
    private(set) var urls: [URL] = []
    var payload: Data = tinyPNG()
    var fails = false
    func record(_ url: URL) throws -> Data {
        urls.append(url)
        if fails { throw URLError(.notConnectedToInternet) }
        return payload
    }
    func set(payload: Data) { self.payload = payload }
    func set(fails: Bool) { self.fails = fails }
}

@Suite struct AvatarDiskTests {
    let alice = URL(string: "https://avatars.example.com/u/1?s=40")!
    let bob = URL(string: "https://avatars.example.com/u/2?s=40")!

    @Test func roundTripsBytesAndKeepsStoreDate() throws {
        let disk = AvatarDisk(directory: tempDirectory())
        defer { try? disk.removeAll() }
        #expect(disk.read(alice) == nil)
        try disk.write(Data([1, 2, 3]), for: alice)
        let stored = try #require(disk.read(alice))
        #expect(stored.data == Data([1, 2, 3]))
        #expect(abs(stored.storedAt.timeIntervalSinceNow) < 5)
    }

    @Test func differentURLsGetDifferentFiles() {
        let disk = AvatarDisk(directory: tempDirectory())
        #expect(disk.fileURL(for: alice) != disk.fileURL(for: bob))
        #expect(disk.fileURL(for: alice) == disk.fileURL(for: alice))
        #expect(disk.fileURL(for: alice).deletingLastPathComponent().path == disk.directory.path)
    }

    @Test func usageCountsFilesAndBytesAndRemoveAllEmpties() throws {
        let disk = AvatarDisk(directory: tempDirectory())
        #expect(disk.usage() == AvatarDisk.Usage(files: 0, bytes: 0))
        try disk.write(Data(count: 10), for: alice)
        try disk.write(Data(count: 30), for: bob)
        #expect(disk.usage() == AvatarDisk.Usage(files: 2, bytes: 40))
        try disk.removeAll()
        #expect(disk.usage() == AvatarDisk.Usage(files: 0, bytes: 0))
        #expect(disk.read(alice) == nil)
    }

    @Test func pruneDropsOnlyFilesOlderThanTheLimit() throws {
        let disk = AvatarDisk(directory: tempDirectory())
        defer { try? disk.removeAll() }
        try disk.write(Data(count: 1), for: alice)
        try disk.write(Data(count: 1), for: bob)
        let old = Date().addingTimeInterval(-40 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: disk.fileURL(for: bob).path)
        try disk.prune(olderThan: 30 * 86_400)
        #expect(disk.read(alice) != nil)
        #expect(disk.read(bob) == nil)
    }
}

@Suite struct AvatarFreshnessTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func entriesAreFreshWithinTheTTLAndStaleAfter() {
        #expect(!avatarIsStale(storedAt: t0, now: t0.addingTimeInterval(AvatarCache.ttl - 1)))
        #expect(avatarIsStale(storedAt: t0, now: t0.addingTimeInterval(AvatarCache.ttl + 1)))
    }

    @Test func clockGoingBackwardsCountsAsFresh() {
        #expect(!avatarIsStale(storedAt: t0, now: t0.addingTimeInterval(-3_600)))
    }
}

@MainActor
@Suite struct AvatarCacheTests {
    let alice = URL(string: "https://avatars.example.com/u/1?s=40")!

    private func makeCache(log: FetchLog, disk: AvatarDisk? = nil, now: @escaping @Sendable () -> Date = { Date() }) -> AvatarCache {
        AvatarCache(disk: disk ?? AvatarDisk(directory: tempDirectory()), now: now) { url in try await log.record(url) }
    }

    @Test func firstLoadFetchesAndLaterLoadsAreServedFromMemory() async {
        let log = FetchLog()
        let cache = makeCache(log: log)
        #expect(cache.cachedImage(alice) == nil)
        #expect(await cache.image(for: alice) != nil)
        #expect(cache.cachedImage(alice) != nil)
        #expect(await cache.image(for: alice) != nil)
        #expect(await log.urls == [alice])
    }

    @Test func concurrentLoadsOfTheSameURLFetchOnce() async {
        let log = FetchLog()
        let cache = makeCache(log: log)
        async let a = cache.image(for: alice)
        async let b = cache.image(for: alice)
        _ = await (a, b)
        #expect(await log.urls.count == 1)
    }

    @Test func aFreshDiskCopyIsUsedWithoutTouchingTheNetwork() async throws {
        let log = FetchLog()
        let disk = AvatarDisk(directory: tempDirectory())
        defer { try? disk.removeAll() }
        try disk.write(tinyPNG(), for: alice)
        let cache = makeCache(log: log, disk: disk)
        #expect(await cache.image(for: alice) != nil)
        #expect(await log.urls.isEmpty)
    }

    @Test func aStaleDiskCopyIsShownNowAndRefreshedInTheBackground() async throws {
        let log = FetchLog()
        let disk = AvatarDisk(directory: tempDirectory())
        defer { try? disk.removeAll() }
        try disk.write(tinyPNG(gray: 0x10), for: alice)
        let old = Date().addingTimeInterval(-(AvatarCache.ttl + 60))
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: disk.fileURL(for: alice).path)
        await log.set(payload: tinyPNG(gray: 0xF0))
        let cache = makeCache(log: log, disk: disk)
        #expect(await cache.image(for: alice) != nil)
        await cache.waitForRefreshes()
        #expect(await log.urls == [alice])
        let refreshed = try #require(disk.read(alice))
        #expect(refreshed.data == tinyPNG(gray: 0xF0))
    }

    @Test func networkFailureYieldsNoImageAndNothingOnDisk() async {
        let log = FetchLog()
        await log.set(fails: true)
        let disk = AvatarDisk(directory: tempDirectory())
        let cache = makeCache(log: log, disk: disk)
        #expect(await cache.image(for: alice) == nil)
        #expect(disk.read(alice) == nil)
        #expect(disk.usage().files == 0)
    }

    @Test func undecodableBytesAreNotCached() async {
        let log = FetchLog()
        await log.set(payload: Data("not an image".utf8))
        let disk = AvatarDisk(directory: tempDirectory())
        let cache = makeCache(log: log, disk: disk)
        #expect(await cache.image(for: alice) == nil)
        #expect(disk.read(alice) == nil)
        #expect(cache.cachedImage(alice) == nil)
    }

    @Test func clearForgetsMemoryAndDiskAndReportsUsage() async throws {
        let log = FetchLog()
        let disk = AvatarDisk(directory: tempDirectory())
        let cache = makeCache(log: log, disk: disk)
        _ = await cache.image(for: alice)
        await cache.refreshUsage()
        #expect(cache.usage.files == 1)
        #expect(cache.usage.bytes > 0)
        await cache.clear()
        #expect(cache.cachedImage(alice) == nil)
        #expect(disk.read(alice) == nil)
        #expect(cache.usage == AvatarDisk.Usage(files: 0, bytes: 0))
        _ = await cache.image(for: alice)
        #expect(await log.urls.count == 2)
    }
}
