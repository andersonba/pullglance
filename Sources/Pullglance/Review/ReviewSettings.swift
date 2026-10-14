import Foundation
import Observation

struct ReviewPreset: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let group: String
    let label: String
    let description: String
    let globs: [String]
    let enabled: Bool
}

/// The presets the page script knows, from the same source (`review-presets.json` is written by the build).
enum ReviewPresets {
    static let all: [ReviewPreset] = {
        guard let url = Bundle.app.url(forResource: "review-presets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let presets = try? JSONDecoder().decode([ReviewPreset].self, from: data) else { return [] }
        return presets
    }()
}

/// Where the floating file pill sits over the page.
enum FilePillPosition: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
}

struct ReviewSettings: Codable, Equatable, Sendable {
    var presets: [String: Bool]
    var customGlobsText: String
    var autoMark: Bool
    var rememberCompare: Bool
    var verify: Bool
    var loadBeforeMark: Bool
    var filePill: FilePillPosition = .bottom
    /// The review window is a beta: off, rows open on GitHub in the browser as they always did.
    var windowEnabled: Bool = false

    static let `default` = ReviewSettings(
        presets: Dictionary(uniqueKeysWithValues: ReviewPresets.all.map { ($0.id, $0.enabled) }),
        customGlobsText: "", autoMark: false, rememberCompare: true, verify: true, loadBeforeMark: true)

    init(presets: [String: Bool], customGlobsText: String, autoMark: Bool, rememberCompare: Bool, verify: Bool, loadBeforeMark: Bool, filePill: FilePillPosition = .bottom) {
        self.presets = presets
        self.customGlobsText = customGlobsText
        self.autoMark = autoMark
        self.rememberCompare = rememberCompare
        self.verify = verify
        self.loadBeforeMark = loadBeforeMark
        self.filePill = filePill
    }

    /// Settings saved before a field existed decode with that field's default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        presets = try c.decode([String: Bool].self, forKey: .presets)
        customGlobsText = try c.decode(String.self, forKey: .customGlobsText)
        autoMark = try c.decode(Bool.self, forKey: .autoMark)
        rememberCompare = try c.decode(Bool.self, forKey: .rememberCompare)
        verify = try c.decode(Bool.self, forKey: .verify)
        loadBeforeMark = try c.decode(Bool.self, forKey: .loadBeforeMark)
        filePill = try c.decodeIfPresent(FilePillPosition.self, forKey: .filePill) ?? .bottom
        windowEnabled = try c.decodeIfPresent(Bool.self, forKey: .windowEnabled) ?? false
    }

    static let key = "reviewSettings"

    var customGlobs: [String] {
        customGlobsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// The `Settings` object the script's `setSettings` expects.
    var scriptPayload: [String: Any] {
        ["version": 1, "presets": presets, "customGlobs": customGlobs, "customGlobsText": customGlobsText,
         "autoMark": autoMark, "verify": verify, "rememberCompare": rememberCompare, "loadBeforeMark": loadBeforeMark]
    }

    static func load(_ defaults: UserDefaults) -> ReviewSettings {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(ReviewSettings.self, from: data) else { return .default }
        var merged = saved
        for preset in ReviewPresets.all where merged.presets[preset.id] == nil { merged.presets[preset.id] = preset.enabled }
        return merged
    }

    func save(_ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

enum ReviewPresetChoice: Hashable, Sendable {
    case auto
    case preset(String)
    case custom

    static let key = "reviewPresetChoice"

    static func load(_ defaults: UserDefaults, repo: String) -> ReviewPresetChoice {
        switch defaults.dictionary(forKey: key)?[repo] as? String {
        case nil, "auto": .auto
        case "custom": .custom
        case let id?: .preset(id)
        }
    }

    func save(_ defaults: UserDefaults, repo: String) {
        var all = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        switch self {
        case .auto: all.removeValue(forKey: repo)
        case .custom: all[repo] = "custom"
        case .preset(let id): all[repo] = id
        }
        defaults.set(all, forKey: Self.key)
    }
}

/// nil means "the rules as configured"; otherwise the single rule the user picked for this repository.
func ruleIDs(for choice: ReviewPresetChoice, settings: ReviewSettings) -> [String]? {
    switch choice {
    case .auto: nil
    case .preset(let id): [id]
    case .custom: ["custom"]
    }
}

@Observable
@MainActor
final class ReviewSettingsStore {
    static let shared = ReviewSettingsStore(defaults: .standard)
    private let defaults: UserDefaults
    var settings: ReviewSettings { didSet { settings.save(defaults); onChange?(settings) } }
    var onChange: ((ReviewSettings) -> Void)?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = ReviewSettings.load(defaults)
    }
}
