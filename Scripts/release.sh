#!/bin/bash
# Cuts a release from main: Scripts/release.sh X.Y.Z
#
# Runs the tests and the Web build, writes the version into version.env, moves CHANGELOG's Unreleased into
# the version, builds and zips the app, writes the zip's sha256 into the cask, commits "release: vX.Y.Z",
# tags, pushes, and publishes the GitHub Release with the zip. The cask and the release come from the same
# bytes, and the cask is on main before the release exists, so the app's offer never points at a version
# Homebrew cannot find.
#
# Phases, each resumable by running the same command again: prepare (any failure restores the files),
# commit+tag (local), push, publish. A finished release is a no-op.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "release: $*" >&2; exit 1; }

NEW="${1:-}"
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: Scripts/release.sh X.Y.Z" >&2; exit 2; }
TAG="v$NEW"
ZIP="build/Pullglance.zip"
CASK="Casks/pullglance.rb"
# shellcheck disable=SC1091
source version.env

[[ "$(git branch --show-current)" == "main" ]] || die "not on main"
[[ -z "$(git status --porcelain)" ]] || die "the working tree is not clean"
gh auth status >/dev/null 2>&1 || die "gh is not logged in"
git fetch -q origin main
remote_tag="$(git ls-remote --tags origin "refs/tags/$TAG" | cut -f1)"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  # Tagged already: the push or the publishing is what is left.
  [[ "$VERSION" == "$NEW" ]] || die "tag $TAG exists but version.env says $VERSION"
  [[ -f "$ZIP" ]] || die "tag $TAG exists but $ZIP is gone, and a rebuild is not byte-identical. If nothing was pushed: git tag -d $TAG && git reset --hard origin/main, then run again"
  cask_sha="$(sed -n 's/^  sha256 "\(.*\)"/\1/p' "$CASK")"
  [[ "$(shasum -a 256 "$ZIP" | cut -d' ' -f1)" == "$cask_sha" ]] || die "$ZIP does not match the sha256 in $CASK; see the note above about starting over"
  [[ -z "$remote_tag" || "$remote_tag" == "$(git rev-parse "$TAG")" ]] || die "origin already has a different $TAG"
  echo "==> resuming $TAG"
else
  [[ -z "$remote_tag" ]] || die "origin has $TAG but this checkout does not: git fetch --tags, then look at it"
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main is not in sync with origin/main"
  # Newer than the last release; the version already in version.env is fine when it was never released.
  [[ "$(printf '%s\n%s\n' "$VERSION" "$NEW" | sort -V | tail -1)" == "$NEW" ]] || die "$NEW is older than $VERSION"
  notes="$(awk '/^## \[Unreleased\]/{f=1; next} /^## /{f=0} f' CHANGELOG.md | sed -e '/./,$!d')"
  [[ -n "$notes" ]] || die "CHANGELOG.md has nothing under ## [Unreleased]"

  echo "==> tests"
  swift build --build-tests
  swift test --skip-build
  echo "==> web"
  Scripts/build-review-js.sh
  [[ -z "$(git status --porcelain -- Sources/Pullglance/Resources)" ]] || die "Sources/Pullglance/Resources is out of date with Web/; commit the rebuilt bundle first"

  # From here until the commit, any failure puts the files back.
  trap 'git checkout -q -- version.env CHANGELOG.md "$CASK"' ERR
  echo "==> version $NEW"
  echo "VERSION=$NEW" > version.env
  perl -0pi -e "s/^## \[Unreleased\]\n/## [Unreleased]\n\n## [$NEW] - $(date +%Y-%m-%d)\n/m" CHANGELOG.md

  echo "==> app"
  Scripts/make-app.sh
  lipo -archs build/Pullglance.app/Contents/MacOS/Pullglance | grep -q arm64 || die "the binary is not arm64, which is what the cask promises"
  rm -f "$ZIP"
  ditto -c -k --keepParent build/Pullglance.app "$ZIP"
  sha="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
  perl -pi -e "s/^  version \".*\"/  version \"$NEW\"/; s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$CASK"
  {
    printf '%s\n\n---\n\n' "$notes"
    printf 'Homebrew: `brew upgrade --cask pullglance`, or the first time\n\n'
    printf '```sh\nbrew tap andersonba/pullglance https://github.com/andersonba/pullglance\nbrew install --cask andersonba/pullglance/pullglance\n```\n\n'
    printf 'From a source checkout: `git pull && Scripts/make-app.sh --install`\n'
  } > build/notes.md

  echo "==> commit and tag"
  git add version.env CHANGELOG.md "$CASK"
  git commit -q -m "release: $TAG"
  trap - ERR
  git tag -a "$TAG" -m "$TAG"
fi

echo "==> push"
git push --atomic origin main "$TAG"

echo "==> publish"
if gh release view "$TAG" --json isDraft >/dev/null 2>&1; then
  has_zip="$(gh release view "$TAG" --json assets --jq '[.assets[].name] | index("Pullglance.zip") != null')"
  if [[ "$has_zip" == "true" ]]; then
    echo "    Pullglance.zip is already on the release"
  else
    gh release upload "$TAG" "$ZIP"
  fi
  if [[ "$(gh release view "$TAG" --json isDraft --jq .isDraft)" == "true" ]]; then
    gh release edit "$TAG" --draft=false
  fi
else
  gh release create "$TAG" "$ZIP" --title "$TAG" --notes-file build/notes.md --verify-tag
fi
echo "done: $TAG"
