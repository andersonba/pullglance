import Foundation

/// The what's new tour: the welcome window's shell, once after an update, with the release's best
/// screens. Written by hand per release, three or four screens plus "And more"; the changelog stays the
/// list, this is the tour. Titles, texts and bullets are localization keys.
enum WhatsNewStep {
    /// Every tour screen ever written, newest release first, in reading order inside a release. Every one
    /// carries its version. The two oldest are a one-time catch-up: nobody saw a tour before 0.6.0, so the
    /// first run also shows what stayed hidden since 0.3.0 and 0.5.0; a seen version hides them for good.
    static let all: [OnboardingStep] = [
        OnboardingStep(id: "watch", pose: .pointing,
                       title: "Watch a pull request",
                       text: "Press W on a row you are waiting on. The app looks at it every half minute, popover open or not, and a notification tells you the moment it moves: checks, approval, merge. One notification, then the watch ends.",
                       content: .watch, button: "Next", version: "0.6.0"),
        OnboardingStep(id: "stacks", pose: .neutral,
                       title: "Stacks",
                       text: "A pull request in a gh stack shows its place, 2 of 3. Hover for the stack, click to see only it.",
                       content: .stacks, button: "Next", version: "0.6.0"),
        OnboardingStep(id: "handoff", pose: .celebrating,
                       title: "Out of your hands",
                       text: "A purple dot at the left means GitHub will merge it: in the merge queue, or auto-merge on. Green is still yours to merge.",
                       content: .handoff, button: "Next", version: "0.6.0"),
        OnboardingStep(id: "deskKeys", pose: .glance,
                       title: "The Review Desk's keys",
                       text: "⌘J and ⌘K step through the files, ⌘← ⌘→ go back and forward, ⌘E finds the selection, esc stops a load. ⌘/ lists them all.",
                       content: .deskKeys, button: "Next", version: "0.6.0"),
        OnboardingStep(id: "more-0.6.0", pose: .glance,
                       title: "And more",
                       text: "Smaller things in this release:",
                       content: .more([
                           "Pullglance --demo runs the app on fictional data, to try things without a real pull request.",
                           "Closing the Review Desk lets the page go instead of keeping it alive hidden.",
                           "Five stability fixes: a stuck gh, a held key, a popover in a loop.",
                       ]),
                       button: "Next", version: "0.6.0", tryIt: .openURL(releaseNotesURL(for: "0.6.0"))),
        OnboardingStep(id: "assigned", pose: .waiting,
                       title: "Assigned to you",
                       text: "Pull requests assigned to you that someone else opened (a bot, an agent, a teammate) join My PRs, with the author on the row and an Assigned chip. Settings › Sections turns it off.",
                       content: .assigned, button: "Next", version: "0.5.0"),
        OnboardingStep(id: "keyboard", pose: .neutral,
                       title: "Drive it from the keyboard",
                       text: "J starts, H J K L do what the arrows do, F opens the filter, space opens the row's menu, ⌘/ lists every key.",
                       content: .keyboard, button: "Next", version: "0.3.0"),
    ]

    /// `all` filtered to the releases newer than `seen` (all of them when nothing was ever seen), order kept.
    static func due(after seen: String?) -> [OnboardingStep] {
        guard let seen else { return all }
        return all.filter { step in step.version.map { compareVersions($0, seen) == .orderedDescending } ?? false }
    }

    /// The latest release that has screens, for the menu item.
    static func latest() -> [OnboardingStep] {
        guard let newest = all.first?.version else { return [] }
        return all.filter { $0.version == newest }
    }

    static func releaseNotesURL(for version: String) -> URL {
        URL(string: "https://github.com/andersonba/pullglance/releases/tag/v\(version)")!
    }
}

/// Dotted numbers, not strings: "0.10.0" is newer than "0.9.0". A part that is not a number counts as 0
/// ("0.6.0-beta" reads as 0.6.0) and a missing part too ("0.6" is "0.6.0"); "dev" is older than everything.
func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
    func parts(_ v: String) -> [Int] {
        var numbers = v.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        while numbers.count < 3 { numbers.append(0) }
        return numbers
    }
    for (x, y) in zip(parts(a), parts(b)) where x != y { return x < y ? .orderedAscending : .orderedDescending }
    return .orderedSame
}

/// The last version the tour was seen in. Written when the window opens, so a crash or ⌘Q mid-tour does
/// not bring it back; the menu is the way back.
struct WhatsNewProgress {
    static let key = "whatsNew.seenVersion"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var seenVersion: String? { defaults.string(forKey: Self.key) }

    func markSeen(version: String) { defaults.set(version, forKey: Self.key) }

    /// Due when `current` is a real version newer than the seen one, and some screen is newer than the
    /// seen one: a release with nothing worth a screen opens nothing and leaves the seen version alone.
    func isDue(current: String) -> Bool {
        guard current != "dev" else { return false }
        if let seen = seenVersion, compareVersions(current, seen) != .orderedDescending { return false }
        return !WhatsNewStep.due(after: seenVersion).isEmpty
    }
}
