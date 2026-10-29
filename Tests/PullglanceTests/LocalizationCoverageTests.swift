import Foundation
import Testing

/// Every key the app looks up in its own bundle must exist in both languages: a missing key shows in English
/// (or as a raw format) for Portuguese users and the other tests cannot see it.
@Suite struct LocalizationCoverageTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = repo.appendingPathComponent("Sources/Pullglance")
    private static let resources = sources.appendingPathComponent("Resources")

    /// Keys built from `\(…)` interpolations, in the form the lookup uses. The scan skips interpolated literals.
    private static let formattedKeys = [
        "%lld files", "%lld marked", "%lld marked · %lld failed", "%lld unmarked", "Mark tests · %lld",
        "Approve #%@", "Comment on #%@", "Downloaded %@ · Show in Finder",
        "%lld of %lld", "%lld of %lld viewed", "Tests · %lld",
        "In queue · %lld", "The merge queue merges it with the strategy set for %@.", "Show only %@",
        "Stack #%lld on %@", "Stack #%lld",
    ]

    /// `Text("key", bundle: .app)`, `Text(flag ? "a" : "b", bundle: .app)` and `String(localized: "key", bundle: .app)`.
    private static func scannedKeys() throws -> Set<String> {
        let literal = #""((?:[^"\\\n]|\\.)*)""#
        let patterns = [
            #"\bText\(\s*"# + literal + #"\s*,\s*bundle:\s*\.app"#,
            #"String\(localized:\s*"# + literal + #"\s*,\s*bundle:\s*\.app"#,
            #"\bText\(\s*[^"()\n]*\?\s*"# + literal + #"\s*:\s*"# + literal + #"\s*,\s*bundle:\s*\.app"#,
        ].map { try! NSRegularExpression(pattern: $0) }
        var keys: Set<String> = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for regex in patterns {
                for match in regex.matches(in: text, range: range) {
                    for group in 1..<match.numberOfRanges {
                        guard let r = Range(match.range(at: group), in: text) else { continue }
                        let key = String(text[r])
                        if !key.contains(#"\("#) { keys.insert(key) }
                    }
                }
            }
        }
        return keys
    }

    private static func contents(_ language: String, _ file: String) throws -> String {
        try String(contentsOf: resources.appendingPathComponent("\(language).lproj/\(file)"), encoding: .utf8)
    }

    @Test func everyLookedUpKeyExistsInBothLanguages() throws {
        let scanned = try Self.scannedKeys()
        #expect(scanned.count > 50, "the scan found too few keys: \(scanned.count)")
        let keys = scanned.union(Self.formattedKeys)
        for language in ["en", "pt-BR"] {
            let strings = try Self.contents(language, "Localizable.strings")
            let plurals = try Self.contents(language, "Localizable.stringsdict")
            let missing = keys.filter { key in
                !strings.contains("\"\(key)\" = ") && !plurals.contains("<key>\(key)</key>")
            }.sorted()
            #expect(missing.isEmpty, "\(language) is missing \(missing.count) keys:\n\(missing.joined(separator: "\n"))")
        }
    }
}
