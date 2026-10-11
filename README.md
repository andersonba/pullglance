# Pullglance

Your pull requests and review requests at a glance, in the macOS menu bar. Vibe coded.

It talks to GitHub through the `gh` CLI you are already logged into. No GitHub App, no OAuth, no server, no tokens of its own.

## What you see

- **My PRs**, in four sections: *Needs action* (failing checks, requested changes, merge conflicts, branch behind base), *Ready to merge*, *Waiting for review or checks*, *Drafts*.
- **To review**: pull requests where you were asked directly, plus a collapsed section for requests to your teams.
- **A number on the menu bar icon.** By default it adds up *Needs action*, *Ready to merge* and *Needs your review*: everything that depends on you. It can also show two numbers, each adding up sections of your choice.

Click a row to open the PR, the CI dot to open its checks. A row of chips under the tabs isolates one section (keys `1`–`4`, `0` for all). The folder icon narrows both tabs to a few repositories for the session.

## Acting on a pull request

Swipe a row to the left, or right-click it:

- **Merge** (only in *Ready to merge*): a confirmation with the merge method, defaulting to the one you used last in that repository. Refused by GitHub if the branch moved since the row was shown.
- **Comment**, **Open on GitHub**, **Copy link**, **Refresh** this one pull request.
- **Snooze**: the row moves to a *Snoozed* section at the bottom and leaves the badge until the PR gets a new commit, a review decision or a CI result.

Hold a row for a moment, or click *Reorder* on a section title, to drag rows into your own order within a section. *Sort by update* brings a section back.

While the popover is open, rows with CI still running are checked every 20 seconds, so a finished run moves the row and brings *Merge* with it. Everything refreshes every 2 minutes.

## Settings (⌘,)

- **General**: launch at login, refresh interval, language.
- **Sections**: show or hide sections, drag to reorder them, choose what the badge counts, one number or two.
- **Filters**: hide organizations or accounts, and per owner either keep everything except a few repositories or only a chosen few. Hidden owners and excluded repositories leave the searches themselves, so lists, totals and the badge all follow.
- **Diagnostics**: the failures of the last refreshes, the avatar cache, a verbose log toggle and *Export diagnostics…*, which zips a summary, the log and optional screenshots for a bug report.

## Install

Requires macOS 15+ and [GitHub CLI](https://cli.github.com):

```sh
brew install gh && gh auth login
git clone https://github.com/andersonba/pullglance && cd pullglance
Scripts/make-app.sh --install
```

That builds `Pullglance.app`, signs it ad hoc and copies it to `/Applications`. Turn on *Launch at login* from the app's menu.

## Run from source

```sh
swift run              # start the app
swift test             # run the tests
Scripts/snapshot.sh    # render the popover and Settings to PNG files, then exit
```

The UI follows your system language (English, Portuguese). To change it for this app only: System Settings → General → Language & Region → Applications.

## How it works

Three GraphQL searches through `gh api graphql`, run together:

- `is:pr is:open author:@me`, one page of 100
- `is:pr is:open user-review-requested:@me`, one page of 100
- `is:pr is:open review-requested:@me -user-review-requested:@me`, one page of 30, only while the team section is open or counted in the badge

Merging runs `gh pr merge` pinned to the commit you saw. When the repository deletes merged branches itself the app never asks `gh` to, because deleting right after the merge makes GitHub close pull requests stacked on that branch instead of retargeting them; when you ask for the deletion, it first checks that nothing is based on the branch.

On disk: preferences in `UserDefaults`, author avatars in `~/Library/Caches`, and a small rolling log in `~/Library/Logs/Pullglance` with no titles, bodies or tokens in it.

## License

MIT. See [LICENSE](LICENSE).
