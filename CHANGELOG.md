# Changelog

Notable changes, newest first, in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Write under **Unreleased** as you go; `Scripts/release.sh X.Y.Z` turns that section into the version and
publishes it as the release notes.

## [Unreleased]

## [0.1.2] - 2026-10-16

### Fixed
- Clicking a row opens the pull request again, and the popover shrinks back when its content does. Builds made with Swift 6.4's new build system were stamped as linked against macOS 15, which put SwiftUI on compatibility paths that broke both; 0.1.1 shipped that way. The build now states the real SDK and the release script refuses a binary that does not.

## [0.1.1] - 2026-10-16

### Fixed
- A pull request in a repository that requires no review is ready to merge as soon as GitHub offers the button, even with a review still requested.
- The popover shrinks with its content: a shorter tab no longer floats lower in the window with empty glass above it.
- Section headers stay on one line; "20 most recent" moved next to "Open all on GitHub" and shows only when the list is cut.

## [0.1.0] - 2026-10-15

### Added
- The number of pull requests that need you, next to the clock. Settings › Sections picks which sections it counts; it can show two numbers, and it rolls like an odometer when it changes.
- Two tabs: My PRs by state (needs action, ready to merge, waiting for review, drafts), To review by what asks for you first. Quick filters by section, author and repository, also by clicking a row's avatar or repository name.
- Repository rules per owner: hide every repository but some, or only some, with search.
- Actions from the row, by swipe, menu or key: merge (through the merge queue when the base needs one, or when checks pass through GitHub's auto-merge), comment, approve, snooze, pin, refresh, mark a draft as ready, open, copy link. Everything that cannot be undone asks first.
- Snooze until something happens on the pull request, or for a length you choose; a timed snooze ends with the row marked, a dot on the icon and an optional notification.
- Keyboard: ↓ drives the list, every key works on the row under the pointer, ⌘/ shows them all.
- A review window, behind Settings › Advanced › Experimental: the pull request page with a native bar that walks the changed files, marks them viewed, marks tests in bulk, and approves or comments without leaving it.
- A welcome window on the first launch that checks `gh` is installed and logged in, and a right-click menu on the icon.
- English and Brazilian Portuguese.
- Everything through the `gh` you are already logged into. Preferences, avatars and a small log stay on your Mac; Settings › Advanced exports diagnostics.
- Install and upgrade through Homebrew; the app tells you when a release is out.
