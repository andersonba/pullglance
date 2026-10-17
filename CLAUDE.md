# Pullglance

macOS menu bar app for pull requests: SwiftUI + AppKit, Swift 6 language mode, SwiftPM, no Xcode project.
Everything reaches GitHub through the user's own `gh`. `docs/how-it-works.md` explains the product section by section.

## Running it

- `Scripts/make-app.sh --install` builds the release app from this checkout and installs it in /Applications,
  quitting and replacing the copy that is there. This is how the app runs day to day on the author's Mac
  (no Homebrew copy here). It uses the real identity, `com.andersonba.pullglance`, and the version in
  `version.env`, so it offers newer GitHub releases; `git pull && Scripts/make-app.sh --install` is the update.
- `swift run` starts a debug build for iterating; it ends with the terminal. The debug executable embeds
  `Scripts/Info-debug.plist` (linker `-sectcreate`, debug only): it is a UI element from the first instant and
  has its own identity, `com.andersonba.pullglance.debug`, so its defaults never touch the installed app's.
  It reports version `dev` and is never nagged about updates.
- The packaged app updates itself through Sparkle: `Scripts/make-app.sh` embeds the framework from the SwiftPM
  artifact, re-signs it ad hoc and writes the feed URL and the public key into Info.plist. `swift run` has no
  feed and never starts Sparkle. `Scripts/release.sh` signs the appcast (`Scripts/make-appcast.sh`) with the
  private key kept GPG-encrypted at `~/.config/pullglance/sparkle-ed25519.key.gpg`, which the YubiKey decrypts,
  so cutting a release needs it plugged in. A rehearsal against a local feed uses the `PULLGLANCE_REHEARSAL_*`
  variables of `make-app.sh` and a throwaway key through `make-appcast.sh --key-file`.
- The app log is `~/Library/Logs/Pullglance/pullglance.log` (`AppLog`); Settings › Advanced exports diagnostics.
- The MenuBarExtra popover opens on a real click or on the global shortcut (⌥⌘P, `PopoverHotKey`), which
  goes through `PopoverPresenter` and the MenuBarExtraAccess package: on macOS 27 the window belongs to a
  session of the system's menu bar host, `performClick` does nothing, and the icon lights only for sessions
  the host begins, so the hotkey asks the host first. From a terminal nothing opens it (synthetic events and
  osascript need Accessibility, not granted), so anything that needs the popover open needs the user; instrument
  with `AppLog` and read the log instead.

## Checks before claiming anything works

- `swift test` must pass (a few seconds). `Scripts/release.sh X.Y.Z` runs them, builds, tags, pushes and
  publishes the GitHub Release plus the cask, and refuses a binary whose `LC_BUILD_VERSION` sdk is below 26.
- After `Scripts/make-app.sh`, run `python3 -B -m unittest discover -s Scripts/tests -v` for the signed-feed,
  strict appcast and release-key guards. CI and `release.sh` run these too; only disposable keys are used.
- `otool -l .build/debug/Pullglance | grep -A4 LC_BUILD_VERSION` must say `sdk 27.0` (or the current SDK).
  SwiftPM 6.4's default build system stamps `sdk 15.0` otherwise, and SwiftUI then runs the app in macOS 15
  compatibility: taps inside the swipe rows stop firing and the popover never shrinks. `Package.swift` passes
  `-platform_version` to prevent it; bump the version there when the SDK moves, and drop the flag once
  https://github.com/swiftlang/swift-package-manager/issues/10696 is fixed in the toolchain in use.
- When the popover misbehaves after a toolchain or macOS update, check that stamp before touching SwiftUI.

## Conventions

- Commits in English, `type: summary` (feat, fix, build, test, docs, release), body says why. Write user-facing
  changes under `## [Unreleased]` in `CHANGELOG.md`; the release script turns that into the release notes.
- Code comments explain intent and non-obvious constraints, in the voice of the existing ones.
- English and pt-BR strings live in `Sources/Pullglance/Resources/*.lproj`; `LocalizationCoverageTests` fails
  on a key missing in either.
