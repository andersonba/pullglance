import AppKit
import Foundation

/// The environment summary that goes into an export: facts a bug report needs, nothing private.
struct DiagnosticsReport: Equatable {
    var appVersion: String
    var macOSVersion: String
    var ghVersion: String?
    var ghAuthenticated: Bool?
    var refreshIntervalSeconds: Int
    var badgeMode: String
    var visibleSections: [String]
    var badgeSections: [String]
    var hiddenOwnerCount: Int
    var repoRuleCount: Int
    var lastGoodDate: Date?
    var lastError: String?
    var failureCount: Int
    var verbose: Bool

    func render() -> String {
        let yesNo = { (value: Bool?) -> String in value.map { $0 ? "yes" : "no" } ?? "unknown" }
        return """
        Pullglance \(appVersion)
        macOS \(macOSVersion)
        gh: \(ghVersion ?? "not found")
        gh authenticated: \(yesNo(ghAuthenticated))
        refresh interval: \(refreshIntervalSeconds) s
        badge mode: \(badgeMode)
        visible sections: \(visibleSections.joined(separator: ", "))
        badge sections: \(badgeSections.joined(separator: ", "))
        hidden owners: \(hiddenOwnerCount)
        repository rules: \(repoRuleCount)
        last successful refresh: \(lastGoodDate.map { $0.formatted(.iso8601) } ?? "never")
        last error: \(lastError ?? "none")
        failures logged: \(failureCount)
        verbose logging: \(verbose ? "on" : "off")
        """
    }
}

/// Bundles the summary, the log files and optional screenshots into one zip for a bug report.
enum DiagnosticsExporter {
    static let folderName = "Pullglance-diagnostics"

    static func export(to destination: URL, summary: String, logs: [URL], screenshots: [URL]) throws {
        let fm = FileManager.default
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        defer { try? fm.removeItem(at: staging) }
        let root = staging.appending(path: folderName)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(summary.utf8).write(to: root.appending(path: "summary.txt"), options: .atomic)
        for log in logs where fm.fileExists(atPath: log.path) {
            try fm.copyItem(at: log, to: root.appending(path: log.lastPathComponent))
        }
        if !screenshots.isEmpty {
            let folder = root.appending(path: "screenshots")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for shot in screenshots where fm.fileExists(atPath: shot.path) {
                try fm.copyItem(at: shot, to: folder.appending(path: shot.lastPathComponent))
            }
        }
        try? fm.removeItem(at: destination)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, destination.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw ExportError.zipFailed(ditto.terminationStatus) }
    }

    enum ExportError: Error { case zipFailed(Int32) }

    static var suggestedFileName: String {
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        return "\(folderName)-\(stamp).zip"
    }
}

/// The whole export: summary from the store, the two log files, optional screenshots, one zip.
@MainActor
enum DiagnosticsExport {
    static func run(store: PRStore, to destination: URL, includeScreenshots: Bool) async throws {
        let summary = await store.diagnosticsReport().render()
        var screenshots: [URL] = []
        if includeScreenshots {
            let folder = FileManager.default.temporaryDirectory.appending(path: "pullglance-export-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for tab in [PopoverView.Tab.mine, .review] {
                let url = folder.appending(path: "popover-\(tab).png")
                try await ViewSnapshot.png(PopoverView(store: store, tab: tab), width: 380).write(to: url, options: .atomic)
                screenshots.append(url)
            }
        }
        try DiagnosticsExporter.export(to: destination, summary: summary, logs: [store.appLog.fileURL, store.appLog.rotatedURL], screenshots: screenshots)
        store.appLog.info("diagnostics exported")
    }
}
