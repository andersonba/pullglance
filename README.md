<p align="center">
  <img src="docs/images/mascot-glance.png" width="150" alt="">
</p>

<h1 align="center">Pullglance</h1>

<p align="center">Your pull requests and review requests at a glance, in the macOS menu bar. <em>Vibe coded.</em></p>

<p align="center">
  <a href="https://github.com/andersonba/pullglance/actions/workflows/ci.yml"><img src="https://github.com/andersonba/pullglance/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/images/hero.png" width="560" alt="The Pullglance popover under the menu bar, showing review requests ordered by priority">
</p>

Pullglance talks to GitHub through the `gh` CLI you are already logged into. No GitHub App, no OAuth, no server, no tokens of its own.

- **See what depends on you.** Failing checks, approvals ready to merge, reviews asked of you, with a number on the menu bar.
- **Act from the row.** Merge, comment, snooze, pin, from the mouse or the keyboard.

## Install

Requires macOS 15 and [GitHub CLI](https://cli.github.com).

```sh
brew install gh && gh auth login
```

Build it with Xcode 26 installed; it lands in /Applications and opens:

```sh
git clone https://github.com/andersonba/pullglance && cd pullglance
Scripts/make-app.sh --install
```

## Privacy

Everything stays on your Mac. Preferences in `UserDefaults`, author avatars in `~/Library/Caches`, a small rolling log in `~/Library/Logs/Pullglance` with no titles, bodies or tokens in it. Nothing is sent anywhere but GitHub, through `gh`.

## Developing

```sh
swift run                     # start the app
swift test                    # run the tests
Scripts/build-review-js.sh    # rebuild the review window's page script
```

How it works, section by section: [docs/how-it-works.md](docs/how-it-works.md).

## Contributing

Issues and pull requests are welcome. Small, focused changes land faster.

## License

MIT. See [LICENSE](LICENSE).
