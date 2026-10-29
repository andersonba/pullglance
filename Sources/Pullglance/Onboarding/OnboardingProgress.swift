import Foundation

/// Whether the welcome window is still owed. Stores the version it was completed in, so a later
/// "what's new" can reuse the renderer with steps filtered by version.
struct OnboardingProgress {
    static let key = "onboarding.completedVersion"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var completedVersion: String? { defaults.string(forKey: Self.key) }
    var isDue: Bool { completedVersion == nil }

    /// A newcomer has just seen the app itself: the what's new tour has nothing to add about this version.
    func markCompleted(version: String) {
        defaults.set(version, forKey: Self.key)
        WhatsNewProgress(defaults: defaults).markSeen(version: version)
    }

    /// Closing early is allowed; it only counts once gh passed, because until then the app cannot work.
    static func shouldMarkCompleted(onClose ghPassed: Bool) -> Bool { ghPassed }
}
