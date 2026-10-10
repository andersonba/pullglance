# Pullglance

Your pull requests and review requests at a glance, in the macOS menu bar. Vibe coded.

It talks to GitHub through the `gh` CLI you are already logged into. No GitHub App, no OAuth, no server, nothing stored.

## What you see

- **My PRs**, in three sections: *Needs you* (CI failing or changes requested), *Waiting on others*, *Drafts*.
- **To review**: pull requests where you were asked directly, always visible. Requests to your teams stay in a collapsed section.
- **A number on the menu bar icon**: your non-draft PRs that need action, plus direct review requests. Nothing else counts.

Click a row to open the PR. Click the CI dot to open its checks. Refreshes every 2 minutes.

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
