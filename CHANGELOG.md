# Changelog

Notable changes, newest first, in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Write under **Unreleased** as you go; `Scripts/release.sh X.Y.Z` turns that section into the version and
publishes it as the release notes.

## [Unreleased]

### Added
- **Watch** a pull request you are waiting on (row menu, or `W`): a bell on the row, a lookup every 30 seconds popover open or not, and a macOS notification the moment it moves (checks passed or failed, approved, changes requested, conflicts, merge queue position, merged, closed). The notification ends the watch and a click on it opens the pull request; the row says *Moved · why* until the popover has been opened and closed. Up to 10 at a time. Merging from the app with a merge queue or "Merge when checks pass" offers to watch until it lands, checked by default. Each lookup logs how much of GitHub's hourly GraphQL budget is left, so the cost of watching can be read in Settings › Advanced › Diagnostics.
- `Pullglance --demo` runs the app on the fictional data, for trying a feature by hand without a real pull request.
- The Review Desk answers to three more browser keys: `⌘←` / `⌘→` go back and forward (outside a text field, where they stay the line's start and end), `⌘E` takes the selected text as the find term and finds the next match, and `esc` stops a page still loading when no find bar or dialog is up.

### Changed
- In the Review Desk, the previous and next file are now `⌘K` and `⌘J` (the popover's J and K, with the modifier the page needs), and `⌘↑` / `⌘↓` are the page's again: top and end, as in any browser, on the diff and on the conversation. The `⌘/` card lists both, plus `space` / `⇧space`.
- A pull request in the merge queue, or with auto-merge on, shows a purple dot at the left (a queue glyph, or a bolt) instead of the green of its checks: GitHub will merge it, it has left your hands. The checks moved to the dot's tooltip, and the click still opens them.

## [0.5.0] - 2026-10-19

### Added
- Pull requests assigned to you that someone else opened (a bot, a coding agent, a teammate) now show in My PRs: same sections by state, same number next to the clock, the author on the row so you can tell them apart, and an **Assigned** quick filter. A click on the author's avatar narrows the list to that bot or person, as before. Settings › Sections turns it off. Asked for in [#3](https://github.com/andersonba/pullglance/issues/3).

### Fixed
- In the Review Desk, marking right after a page load sometimes left the file unmarked on the page while GitHub had it as viewed: GitHub's new Files UI finishes taking the page over, and renders the file list again from data it fetches, after the page looks ready, and a click before that is drawn over. Every mark, step or jump now waits for the page to be ready, and a mark that the page draws over is applied again. "Mark automatically" was the usual victim.

### Changed
- The pull request number in a row is easier to find: semibold, in the accent color, with tabular digits, still next to the repository name.

## [0.4.0] - 2026-10-17

### Added
- In the Review Desk, files you mark as viewed leave the file tree sidebar, and a folder goes with its last file, so the tree shows what is left to review; once everything is viewed the tree shows all files again. Works in both of GitHub's Files experiences. An eye button next to the progress turns it off, and the choice is remembered.
- Settings › Review Desk has a choice for where a pull request opens: Files (the diff, at the first file still to review), Conversation, or By list, the rule that was implicit until now (My PRs on the conversation, To review on the diff). It applies to a click, to `↩`, and to the browser when the Desk is off. The test presets and the custom globs moved behind a Choose… button, with a one-line summary in their place, so the tab fits without scrolling.
- The welcome window has a step for the global shortcut, with the recorder right there, and mentions `J` next to `↓`.

### Fixed
- "Mark automatically" in the Review Desk now remembers the pull requests it already handled across app runs. Before, a restart (an update installs one) made it mark again the test files you had unmarked since.
- In the Review Desk, scrolling past the collapsed header of a viewed file no longer makes it the current file while an unviewed one is in view below: the highlight and the pill go to that one, where the arrows and the check go. A viewed file left open keeps the cursor, and once everything is viewed every file counts, as before.
- In the Review Desk's file pill, the arrows show their tooltips again, with the keys: `⌘↑`/`⌘↓` go to the previous or next unviewed file and, once every file is viewed, walk every file, the same as the arrows. Before, the keys did nothing once everything was viewed.

### Changed
- The review window is now the Review Desk, in Settings, the shortcuts card and the triage hints; "Review" stays as the name of its menu, which holds the review actions.

## [0.3.0] - 2026-10-17

### Added
- In the popover, Vim's `H J K L` do what the arrows do: `J`/`K` move the focus through the rows (and `J` starts it), `H`/`L` switch tabs. `F` opens the repository/author filter with its search field ready to type. With a row focused, `space` opens its menu, the same one a right-click shows.
- A global shortcut opens and closes the popover from any app, with the menu bar icon lit as for a click: `⌥⌘P` to start with, changeable or removable in Settings › General.

### Fixed
- With two numbers in the menu bar, the odometer roll now plays when only the second number changes, and in that number's direction; before, only a change in the first one rolled. Settings › General › Preview also rolls when the first number is 0, by stepping the second.

### Security
- Update offers and their release notes must now carry a valid EdDSA signature, and downloaded updates are verified before extraction. Release checks also reject incorrect update metadata and accidental signing-key changes.

## [0.2.0] - 2026-10-16

### Added
- The app updates itself: a release shows up as "Update to X.Y.Z…" in the menus, and installing it is one click, with the release notes in the dialog. This version still arrives through `brew upgrade --cask pullglance` and the "Open Anyway" step; from the next one on, neither.

### Fixed
- On macOS 15, clicking a row, its repository name or its author's avatar works again. Outside reorder mode the row's gestures were turned off with `GestureMask.none`, which also disables every gesture inside the row; `.subviews` turns off only the reorder drag and hold.

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
