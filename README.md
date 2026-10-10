# Pullglance

Your pull requests and review requests at a glance, in the macOS menu bar. Vibe coded.

It talks to GitHub through the `gh` CLI you are already logged into. No GitHub App, no OAuth, no server, nothing stored.

## What you see

- **My PRs**, in four sections: *Needs action* (failing checks, requested changes, merge conflicts, branch behind base), *Ready to merge*, *Waiting for review or checks*, *Drafts*.
- **To review**: pull requests where you were asked directly, plus a collapsed section for requests to your teams.
- **A number on the menu bar icon**. By default it adds up *Needs action*, *Ready to merge* and *Needs your review*: everything that depends on you.

Click a row to open the PR. Click the CI dot to open its checks. Refreshes every 2 minutes.

A row of chips under the tabs isolates one section with a click (keys `1`–`4`, `0` for all) and doubles as a count summary.

## Settings (⌘,)

- **General**: launch at login, refresh interval, language.
- **Sections**: choose which sections appear and which ones count toward the badge.
- **Filters**: hide organizations or accounts. Hidden owners are excluded from the searches themselves, so lists, totals and the badge all follow. Stored per machine.

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
swift run     # start the app
swift test    # run the tests
```

The UI follows your system language. To change it for this app only: System Settings → General → Language & Region → Applications.

## How it works

Three GraphQL searches via `gh api graphql`, one page of 100 each:

- `is:pr is:open author:@me`
- `is:pr is:open user-review-requested:@me`
- `is:pr is:open review-requested:@me` (only while the team section is expanded)

Each search costs 3 rate-limit points. The only thing written to disk is two preferences in `UserDefaults`.

## License

MIT. See [LICENSE](LICENSE).
