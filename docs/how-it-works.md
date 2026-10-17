# How Pullglance works

The README stays short on purpose; this is the longer tour. Everything here is current as of the commit that last touched this file. When in doubt, the app's own UI and `Settings` are the source of truth.

## Where the data comes from

Pullglance never talks to GitHub by itself. Everything goes through the `gh` CLI you are already logged into, as GraphQL queries run with `gh api graphql`. Three searches, run together:

- `is:pr is:open author:@me`, one page of 100 → the **My PRs** tab.
- `is:pr is:open user-review-requested:@me`, one page of 100 → **Needs your review**.
- `is:pr is:open review-requested:@me -user-review-requested:@me`, one page of 30 → **Needs your teams' review**, only while that section is open or counted in the badge.

GitHub's search index lags the repository by minutes, so after each search your own pull requests are looked up directly in one batched query, which makes an approval or a finished check show up on the next refresh rather than five refreshes later. Everything refreshes every 2 minutes (configurable); while the popover is open, rows with CI still running are checked every 20 seconds.

## First launch

The first time it runs, Pullglance opens a short welcome window: it checks that the `gh` CLI is installed and logged in (and keeps checking while you fix either), then shows what the number counts, how the two tabs are ordered, how to act from a row, and what snooze does, with an optional switch for a notification when a timed snooze ends. Closing the window early is fine; it comes back next launch until `gh` is talking. You can reopen it any time with **Welcome…** in the icon's right-click menu.

## Background App Activity (macOS 26 and later)

Pullglance is a menu bar app: no Dock icon, and it keeps running after its windows close. macOS 26 and later lists apps like that under System Settings › General › Login Items & Extensions › Background App Activity, and may announce the first occurrence with an "App Running in Background" notification. That entry is the app itself, not a helper. Turning it off, or choosing **Stop Running in Background** on a Dock icon, quits Pullglance and keeps it from staying up; turn it back on to use the app again. The review window puts a Dock icon up while it is open, so ⌘-Tab reaches it, and takes it down when it closes.

## Updates

Pullglance updates itself, through [Sparkle](https://sparkle-project.org). Shortly after launch, and once a day while it runs, it reads the latest release's appcast (`releases/latest/download/appcast.xml` on GitHub). Both the feed (including its embedded release notes) and the zip are signed under the project's EdDSA key. The app requires a valid signed feed before presenting an offer, with no expiration that would allow unsigned offers, and verifies the zip before extraction. When there is a newer version, the icon's right-click menu and the popover's **···** menu offer "Update to X.Y.Z…", and nothing else happens until you click it. The click opens Sparkle's dialog with the release notes; "Install Update" downloads the zip, verifies its signature, replaces the app and relaunches it. The new copy carries no quarantine, so macOS does not ask you to allow it again. "Skip This Version" in that dialog keeps the version quiet until the next one. "Check for updates…" in the icon's menu looks right away and answers with the dialog, "You're up to date", or what went wrong, all Sparkle's own. A source checkout run with `swift run` has no feed and never checks.

Feed signing starts with the next release after 0.2.0. Installed copies of 0.2.0 can still read the signed feed and install that release; subsequent versions require the feed signature as well as the zip signature.

Releases are cut by `Scripts/release.sh`, which writes the version and the zip's checksum into `Casks/pullglance.rb` and signs the appcast with a key kept GPG-encrypted on the author's Mac (`Scripts/make-appcast.sh`; the YubiKey decrypts it), so Homebrew, the release and the app's offer always agree. The cask declares `auto_updates true`, Homebrew's word for a self-updating app: a plain `brew upgrade` leaves a copy the app has already updated alone, while `brew upgrade --cask pullglance` reinstalls it, with the "Open Anyway" step that any Homebrew install of an unsigned app brings.

## My PRs

Four sections, in the order you choose in Settings › Sections:

- **Needs action**: failing checks, requested changes, merge conflicts, branch behind base.
- **Ready to merge**: approved, checks green, no conflicts.
- **Waiting for review or checks**: the rest, including pull requests already in a merge queue or with auto-merge on, which GitHub will merge by itself.
- **Drafts**.

## To review

- **Needs your review**: requests made to you directly, ordered by what asks for you first: a re-review after you already reviewed, then activity you have not read, then small diffs, then everyone else oldest first, with red CI and drafts at the bottom. A blue pill says why a row is where it is. The section header switches between *Priority*, *Recent* and *Manual* order.
- **Needs your teams' review**: the 20 most recent requests made to teams you belong to, collapsed until you open it.

## Pinned and Snoozed

- **Pin** a row (menu, swipe tile on review rows, or `P` on a focused row) to keep it at the top of its tab, in your own order. Pinning does not change the badge.
- **Snooze** a row to move it to the bottom and out of the badge until the pull request gets a new commit, a review decision or a CI result. Pinning wakes a snoozed row; snoozing unpins.

## The menu bar number

By default the badge adds up *Needs action*, *Ready to merge* and *Needs your review*: everything that depends on you. Settings › Sections lets you pick the sections, or show two numbers, each adding up its own sections. When the number changes because of new data, the digits roll like an odometer (Settings › General).

## Acting on a pull request

Swipe a row to the left, right-click it, or focus it with the keyboard:

- **Merge**: a confirmation with the merge method, defaulting to what you used last in that repository, and the branch deletion policy of the repository. Where the base branch has a merge queue the pull request is added to the queue instead; where the pull request is blocked on checks and the repository allows auto-merge, the button reads *Merge when checks pass*. GitHub refuses a merge if the branch moved since the row was shown. When the repository deletes merged branches itself the app never asks `gh` to, because deleting right after the merge makes GitHub close pull requests stacked on that branch instead of retargeting them.
- **Comment**, **Open on GitHub**, **Copy link**, **Refresh** this one pull request, **Pin**, **Snooze**.

## Keyboard

`⌥⌘P` opens and closes the popover from any app (Settings › General changes or removes the shortcut). With the popover open, `↓` (or `J`) focuses the first row; `↑↓` move, `←→` switch tabs, and Vim's `H J K L` do the same as the arrows, `F` opens the repository/author filter with its search ready, `↩` opens the review window, `P` pins, `S` snoozes, `O` opens on GitHub, `R` refreshes, `C` comments, `M` merges where offered, `⌘C` copies the link, `esc` leaves. With the pointer on a row and no focus, `↩` and `⌘C` act on that row and `space` makes it the focus; with a focus, `space` opens the focused row's menu, the same one a right-click shows. `0`–`9` pick the quick filter chips. `⌘/` opens the full list of shortcuts, including the review window's.

## Filters

- The funnel next to the tabs narrows both tabs to a few repositories or a few authors, for the session. Clicking a row's avatar or repository name does the same for that author or repository.
- Settings › Filters hides organizations or accounts, and per owner keeps everything except a few repositories or only a chosen few. These leave the searches themselves, so lists, totals and the badge all follow.

## Review window (beta)

Off by default; Settings › Review turns it on. With it on, a click on a row opens the pull request in a window of its own, with a review bar above the page: the pull request's state, the file progress, and one primary action (merge when ready, approve otherwise) with the rest in its menu. On the Files tab a floating pill shows the current file, steps to the previous or next one, marks it viewed, and marks all test files viewed by preset or by your own globs (Settings › Review). Files marked as viewed leave GitHub's file tree sidebar (a folder goes with its last file), so the tree is what is left to review; once everything is viewed the tree is whole again. The eye button next to the progress turns that off, and the choice is kept. Compare pages remember what you collapsed. The GitHub session lives in the app, separate from your browser; downloads are quarantined like a browser's.

## Settings (⌘,)

- **General**: launch at login, refresh interval, the menu bar roll, the global shortcut.
- **Sections**: show or hide sections, drag to reorder them, choose what the badge counts, one number or two.
- **Filters**: hidden owners and per-owner repository rules.
- **Review**: which files count as tests, by preset or your own globs; how marking behaves; where the file pill sits; compare memory.
- **Diagnostics**: the failures of the last refreshes, the avatar cache, a verbose log toggle and *Export diagnostics…*, which zips a summary, the log and optional screenshots for a bug report.

## On disk

Preferences in `UserDefaults`, author avatars in `~/Library/Caches`, a small rolling log in `~/Library/Logs/Pullglance` with no titles, bodies or tokens in it. Nothing is sent anywhere but GitHub, through `gh`.

## Screenshots

`Scripts/snapshot.sh --demo` renders the popover, the Settings tabs and the README hero from fictional data, so the images can be regenerated whenever the UI changes.
