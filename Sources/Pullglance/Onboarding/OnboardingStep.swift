import Foundation

/// The flea's poses, by resource name (`Resources/<rawValue>.png`).
enum MascotPose: String, Sendable {
    case neutral = "mascot"
    case glance = "mascot-glance"
    case sleeping = "mascot-sleeping"
    case waiting = "mascot-waiting"
    case celebrating = "mascot-celebrating"
    case pointing = "mascot-pointing"
}

/// One screen of the welcome window. The list is the whole flow: to add, reorder or reword a screen,
/// edit `all`. Titles and texts are localization keys.
struct OnboardingStep: Identifiable, Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case none
        /// gh installed and logged in, checked live (`RequirementChecker`).
        case requirements
        /// The drawn menu bar count rolling and the tabs switching.
        case badgeAndTabs
        /// The drawn row sliding open and taking the keyboard focus.
        case rowActions
        /// The global shortcut's recorder, ⌥⌘P unless changed.
        case hotkey
        /// The "notify when a snooze ends" toggle.
        case notifications
        /// The what's new drawings (`WhatsNewAnimations.swift`).
        case watch, deskKeys, handoff, stacks, keyboard, assigned
        /// The release's smaller changes as bullets (localization keys), with the release notes button.
        case more([String])
    }

    /// What a screen's "try it" button does; the view runs it.
    enum TryIt: Equatable, Sendable {
        case openURL(URL)
    }

    let id: String
    let pose: MascotPose
    let title: String
    let text: String
    let content: Content
    /// The primary button's label.
    let button: String
    /// The release a what's new screen belongs to; nil on the welcome's steps.
    var version: String? = nil
    var tryIt: TryIt? = nil

    /// Every key a list of steps looks up through `LocalizedStringKey`, for the coverage test (the scan
    /// in `LocalizationCoverageTests` only sees literals).
    static func localizationKeys(of steps: [OnboardingStep]) -> [String] {
        steps.flatMap { step -> [String] in
            var keys = [step.title, step.text, step.button]
            if case .more(let bullets) = step.content { keys += bullets }
            return keys
        }
    }

    static let all: [OnboardingStep] = [
        OnboardingStep(id: "welcome", pose: .glance,
                       title: "Your pull requests, in the menu bar.",
                       text: "Pullglance watches the pull requests that need you and puts a number next to the clock. It talks to GitHub through the gh you already have, so it never needs a token of its own.",
                       content: .none, button: "Let's go"),
        OnboardingStep(id: "gh", pose: .waiting,
                       title: "Two things first",
                       text: "The app is only as logged in as your gh. I check both while you fix them.",
                       content: .requirements, button: "Continue"),
        OnboardingStep(id: "badge", pose: .glance,
                       title: "The number, and two tabs",
                       text: "The number counts what needs you: failing checks, approvals ready to merge, reviews asked of you. Pick the sections it counts in Settings › Sections. Inside, My PRs by state, To review by who asks first.",
                       content: .badgeAndTabs, button: "Continue"),
        OnboardingStep(id: "actions", pose: .neutral,
                       title: "Act from the row",
                       text: "Swipe a row for Pin, Snooze and Comment. Press ↓ or J to drive the list from the keyboard, H J K L do what the arrows do, ⌘/ shows every key. The same keys work on the row under the pointer. Right-click the icon up there for the menu.",
                       content: .rowActions, button: "Continue"),
        OnboardingStep(id: "hotkey", pose: .glance,
                       title: "Open it from anywhere",
                       text: "⌥⌘P opens and closes the popover whichever app is in front, with the icon lit as for a click. Record another shortcut here, or later in Settings › General.",
                       content: .hotkey, button: "Continue"),
        OnboardingStep(id: "snooze", pose: .pointing,
                       title: "Snooze what can wait",
                       text: "Snooze puts a row to sleep until something happens on it, or for a length you choose. When a timed snooze ends, the row comes back marked and the icon gets a dot. That's it: the icon is next to the clock, with a dot right now so you can find it.",
                       content: .notifications, button: "Open Pullglance"),
    ]

    static func index(of id: String) -> Int? { all.firstIndex { $0.id == id } }
}
