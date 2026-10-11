import AppKit
import CryptoKit
import Foundation
import Observation

/// Avatar bytes on disk, one file per URL, in a folder of our own under the user's Caches.
/// The file's modification date doubles as the time it was stored.
struct AvatarDisk: Sendable {
    struct Usage: Equatable, Sendable {
        var files: Int
        var bytes: Int
    }

    let directory: URL

    /// `~/Library/Caches/<bundle id>/avatars`.
    static func standard() -> AvatarDisk {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return AvatarDisk(directory: caches.appending(path: AppInfo.bundleID).appending(path: "avatars"))
    }

    func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name)
    }

    func read(_ url: URL) -> (data: Data, storedAt: Date)? {
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let storedAt = attributes[.modificationDate] as? Date
        else { return nil }
        return (data, storedAt)
    }

    func write(_ data: Data, for url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: url), options: .atomic)
    }

    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// Drops files not written for longer than `age`, so avatars of people no longer around do not pile up.
    func prune(olderThan age: TimeInterval, now: Date = Date()) throws {
        for (file, attributes) in files() {
            if let storedAt = attributes[.modificationDate] as? Date, now.timeIntervalSince(storedAt) > age {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    func usage() -> Usage {
        files().reduce(into: Usage(files: 0, bytes: 0)) { usage, entry in
            usage.files += 1
            usage.bytes += (entry.attributes[.size] as? Int) ?? 0
        }
    }

    private func files() -> [(url: URL, attributes: [FileAttributeKey: Any])] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path)).map { (url, $0) }
        }
    }
}

/// Whether a stored avatar is old enough to be fetched again. A clock that went backwards counts as fresh.
func avatarIsStale(storedAt: Date, now: Date, ttl: TimeInterval = AvatarCache.ttl) -> Bool {
    now.timeIntervalSince(storedAt) > ttl
}

/// Avatars for the rows: memory first (so a redrawn row never flashes the initial), then our disk copy,
/// then the network. A stale disk copy is shown right away and refreshed in the background, so GitHub's
/// five-minute `max-age` no longer costs one request per avatar on every open.
@MainActor @Observable
final class AvatarCache {
    nonisolated static let ttl: TimeInterval = 24 * 3_600
    nonisolated static let pruneAge: TimeInterval = 30 * 86_400

    static let shared = AvatarCache(disk: .standard()) { url in
        try await URLSession.shared.data(from: url).0
    }

    private struct Entry {
        let image: NSImage
        let storedAt: Date
    }

    private let disk: AvatarDisk
    private let now: @Sendable () -> Date
    private let fetch: @Sendable (URL) async throws -> Data
    private var memory: [URL: Entry] = [:]
    private var loads: [URL: Task<NSImage?, Never>] = [:]
    private var refreshes: [URL: Task<Void, Never>] = [:]

    /// Files and bytes on disk as of the last `refreshUsage()` or `clear()`.
    private(set) var usage = AvatarDisk.Usage(files: 0, bytes: 0)

    init(disk: AvatarDisk, now: @escaping @Sendable () -> Date = { Date() }, fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.disk = disk
        self.now = now
        self.fetch = fetch
    }

    /// What is already decoded, without waiting. Observed by the rows.
    func cachedImage(_ url: URL) -> NSImage? {
        memory[url]?.image
    }

    func image(for url: URL) async -> NSImage? {
        if let entry = memory[url] {
            refreshIfStale(url, storedAt: entry.storedAt)
            return entry.image
        }
        if let running = loads[url] {
            return await running.value
        }
        let task = Task { await load(url) }
        loads[url] = task
        let image = await task.value
        loads[url] = nil
        return image
    }

    /// Forgets everything in memory and on disk.
    func clear() async {
        for task in refreshes.values { task.cancel() }
        refreshes = [:]
        memory = [:]
        let disk = self.disk
        await Task.detached { try? disk.removeAll() }.value
        usage = AvatarDisk.Usage(files: 0, bytes: 0)
    }

    func refreshUsage() async {
        let disk = self.disk
        usage = await Task.detached { disk.usage() }.value
    }

    /// Removes long-unused files; meant to run once at launch.
    func pruneDisk() async {
        let disk = self.disk
        await Task.detached { try? disk.prune(olderThan: Self.pruneAge) }.value
    }

    /// Lets tests wait for background refreshes started by stale hits.
    func waitForRefreshes() async {
        for task in refreshes.values { await task.value }
    }

    private func load(_ url: URL) async -> NSImage? {
        let disk = self.disk
        if let stored = await Task.detached(operation: { disk.read(url) }).value,
           let image = NSImage(data: stored.data) {
            memory[url] = Entry(image: image, storedAt: stored.storedAt)
            refreshIfStale(url, storedAt: stored.storedAt)
            return image
        }
        return await download(url)
    }

    private func refreshIfStale(_ url: URL, storedAt: Date) {
        guard avatarIsStale(storedAt: storedAt, now: now()), refreshes[url] == nil else { return }
        refreshes[url] = Task {
            _ = await download(url)
            refreshes[url] = nil
        }
    }

    /// Fetches, decodes, stores. Bytes that are not an image are dropped as if the fetch had failed.
    private func download(_ url: URL) async -> NSImage? {
        guard let data = try? await fetch(url), let image = NSImage(data: data) else { return nil }
        memory[url] = Entry(image: image, storedAt: now())
        let disk = self.disk
        await Task.detached { try? disk.write(data, for: url) }.value
        return image
    }
}
