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
        /// The "notify when a snooze ends" toggle.
        case notifications
    }

    let id: String
    let pose: MascotPose
    let title: String
    let text: String
    let content: Content
    /// The primary button's label.
    let button: String

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
                       text: "Swipe a row for Pin, Snooze and Comment. Press ↓ to drive the list from the keyboard, ⌘/ shows every key. The same keys work on the row under the pointer. Right-click the icon up there for the menu.",
                       content: .rowActions, button: "Continue"),
        OnboardingStep(id: "snooze", pose: .pointing,
                       title: "Snooze what can wait",
                       text: "Snooze puts a row to sleep until something happens on it, or for a length you choose. When a timed snooze ends, the row comes back marked and the icon gets a dot. That's it: the icon is next to the clock, with a dot right now so you can find it.",
                       content: .notifications, button: "Open Pullglance"),
    ]

    static func index(of id: String) -> Int? { all.firstIndex { $0.id == id } }
}
