import Foundation

/// A small rolling log file in `~/Library/Logs/Pullglance/`, where Console.app lists it and a user can
/// attach it to a bug report. Always on at INFO; DEBUG lines (gh commands, timings) only when verbose.
/// Never tokens (gh keeps them), never comment bodies, never PR titles: repository and number suffice.
final class AppLog: @unchecked Sendable {
    static let shared = AppLog(directory: defaultDirectory)

    static let defaultDirectory: URL = {
        // Test runs must not write into the user's real log.
        let process = ProcessInfo.processInfo.processName.lowercased()
        if process.contains("testing") || process.contains("xctest") {
            return FileManager.default.temporaryDirectory.appending(path: "pullglance-test-logs", directoryHint: .isDirectory)
        }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return library.appending(path: "Logs").appending(path: "Pullglance")
    }()

    let directory: URL
    let maxBytes: Int
    var fileURL: URL { directory.appending(path: "pullglance.log") }
    var rotatedURL: URL { directory.appending(path: "pullglance.1.log") }

    private let lock = NSLock()
    private var verbose: Bool
    private static let stampStyle: Date.ISO8601FormatStyle = .iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: true).timeSeparator(.colon)

    init(directory: URL, maxBytes: Int = 2_000_000, verbose: Bool = false) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.verbose = verbose
    }

    var isVerbose: Bool {
        get { lock.withLock { verbose } }
        set { lock.withLock { verbose = newValue } }
    }

    func info(_ message: String) { write("INFO", message) }

    func debug(_ message: String) {
        guard isVerbose else { return }
        write("DEBUG", message)
    }

    /// Current size of the live log file, for the Diagnostics tab.
    var fileSize: Int {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    }

    private func write(_ level: String, _ message: String) {
        let line = Data("\(Date().formatted(Self.stampStyle)) \(level) \(message)\n".utf8)
        lock.withLock {
            let fm = FileManager.default
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            if size > 0, size + line.count > maxBytes {
                try? fm.removeItem(at: rotatedURL)
                try? fm.moveItem(at: fileURL, to: rotatedURL)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: fileURL, options: .atomic)
            }
        }
    }
}

/// A short tag for a gh call, so concurrent calls can be told apart in the log: the subcommand and, for a
/// search, the start of its query. `gh api graphql [is:pr is:open author:@me archived:false…]`.
func ghLogLabel(_ arguments: [String]) -> String {
    var label = "gh " + arguments.prefix(2).joined(separator: " ")
    if let query = arguments.first(where: { $0.hasPrefix("q=") })?.dropFirst(2) {
        label += " [" + (query.count > 40 ? query.prefix(40).trimmingCharacters(in: .whitespaces) + "…" : String(query)) + "]"
    } else if arguments.count > 2, let target = arguments.dropFirst(2).first(where: { $0.hasPrefix("https://") || !$0.hasPrefix("-") }) {
        label += " " + target
    }
    return label
}

/// `gh` arguments as they may appear in the log: the comment body is the only free text we send, and a
/// GraphQL document is dozens of lines nobody needs in a log, so it is reduced to its size.
func redactedForLog(_ arguments: [String]) -> String {
    var out: [String] = []
    var redactNext = false
    for argument in arguments {
        if redactNext {
            out.append("<redacted>")
        } else if argument.hasPrefix("query=") {
            out.append("query=<graphql \(argument.count - 6) chars>")
        } else if argument.contains("\n") {
            out.append(argument.split(separator: "\n").first.map { "\($0)…" } ?? "…")
        } else {
            out.append(argument)
        }
        redactNext = argument == "--body"
    }
    return out.joined(separator: " ")
}
