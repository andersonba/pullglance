import Foundation

struct ReviewStorageError: Error, Equatable {
    let message: String
}

/// The `browser.storage` areas the page script expects, kept in `UserDefaults` as JSON bytes (not a plist
/// dictionary: `null` is a legal storage value and `NSNull` inside a dictionary makes `set` throw).
/// `session` lives in memory. All mutations run here, serially, so change sets are exact.
@MainActor
final class ReviewStorage {
    private let defaults: UserDefaults
    private let key: String
    private var session: [String: Any] = [:]
    private static let areas: Set<String> = ["local", "sync", "session"]

    init(defaults: UserDefaults, key: String = "reviewStorage") {
        self.defaults = defaults
        self.key = key
    }

    func handle(_ body: [String: Any]) -> Result<Any, ReviewStorageError> {
        guard let area = body["area"] as? String, let op = body["op"] as? String else { return .failure(ReviewStorageError(message: "bad storage request")) }
        guard Self.areas.contains(area) else { return .failure(ReviewStorageError(message: "unknown area \(area)")) }
        let before = read(area)
        var dict = before
        switch op {
        case "get": return .success(dict)
        case "set": for (k, v) in body["items"] as? [String: Any] ?? [:] { dict[k] = v }
        case "remove": for k in body["keys"] as? [String] ?? [] { dict.removeValue(forKey: k) }
        case "clear": dict = [:]
        default: return .failure(ReviewStorageError(message: "unknown op \(op)"))
        }
        guard write(area, dict) else { return .failure(ReviewStorageError(message: "value is not JSON")) }
        var changes: [String: [String: Any]] = [:]
        for k in Set(before.keys).union(dict.keys) {
            let old = before[k], new = dict[k]
            if let old, let new, (old as AnyObject).isEqual(new) { continue }
            var change: [String: Any] = [:]
            if let old { change["oldValue"] = old }
            if let new { change["newValue"] = new }
            changes[k] = change
        }
        return .success(changes)
    }

    /// Settings › Review "Clear compare memory" and Diagnostics "Clear cache".
    func clearPersistent() {
        for area in ["local", "sync"] { defaults.removeObject(forKey: storageKey(area)) }
    }

    private func storageKey(_ area: String) -> String { "\(key).\(area)" }

    private func read(_ area: String) -> [String: Any] {
        if area == "session" { return session }
        guard let data = defaults.data(forKey: storageKey(area)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private func write(_ area: String, _ dict: [String: Any]) -> Bool {
        if area == "session" { session = dict; return true }
        guard JSONSerialization.isValidJSONObject(dict), let data = try? JSONSerialization.data(withJSONObject: dict) else { return false }
        defaults.set(data, forKey: storageKey(area))
        return true
    }
}
