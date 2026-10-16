#!/bin/bash
# Signs a release zip into a Sparkle appcast and verifies it against the public key the app embeds.
#   Scripts/make-appcast.sh --version X.Y.Z --zip <zip> --notes <notes.md> --out <appcast.xml> --public-key <b64> \
#       [--key-file <plain-key>] [--download-url-prefix <url>]
#
# The private EdDSA key is `gpg --decrypt`ed from ${PULLGLANCE_SPARKLE_KEY:-~/.config/pullglance/sparkle-ed25519.key.gpg}
# (the author's YubiKey does the decrypting) and piped straight into generate_appcast: it never lands on disk
# in plaintext. --key-file takes a plaintext key instead, for a rehearsal with a throwaway pair, and
# --download-url-prefix points the rehearsal at a local server instead of the release's assets on GitHub.
# The appcast holds one item, this release, with the notes embedded; the app reads the one on the latest release.
# Sparkle's tools come from the distribution archive of the version Package.resolved pins, cached under build/.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "make-appcast: $*" >&2; exit 1; }

version="" zip="" notes="" out="" public_key="" key_file="" prefix=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --zip) zip="$2"; shift 2 ;;
    --notes) notes="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --public-key) public_key="$2"; shift 2 ;;
    --key-file) key_file="$2"; shift 2 ;;
    --download-url-prefix) prefix="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ -n "$version" && -n "$zip" && -n "$notes" && -n "$out" && -n "$public_key" ]] || die "usage: Scripts/make-appcast.sh --version X.Y.Z --zip <zip> --notes <md> --out <xml> --public-key <b64> [--key-file <key>] [--download-url-prefix <url>]"
prefix="${prefix:-https://github.com/andersonba/pullglance/releases/download/v$version/}"
[[ -f "$zip" ]] || die "$zip is missing"
[[ -f "$notes" ]] || die "$notes is missing"
[[ -z "$key_file" || -f "$key_file" ]] || die "$key_file is missing"

# The tools, pinned to the framework the app embeds.
sparkle_version="$(grep -A6 '"identity" : "sparkle"' Package.resolved | sed -n 's/.*"version" : "\(.*\)".*/\1/p')"
[[ -n "$sparkle_version" ]] || die "cannot read the Sparkle version from Package.resolved"
case "$sparkle_version" in
  2.10.0) sha="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c" ;;
  *) die "Sparkle $sparkle_version: add the sha256 of Sparkle-$sparkle_version.tar.xz to this script" ;;
esac
tools="build/sparkle-tools/$sparkle_version"
if [[ ! -x "$tools/bin/generate_appcast" ]]; then
  echo "==> Sparkle $sparkle_version tools"
  mkdir -p "$tools"
  curl -fsSL -o "$tools/Sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz"
  [[ "$(shasum -a 256 "$tools/Sparkle.tar.xz" | cut -d' ' -f1)" == "$sha" ]] || die "Sparkle-$sparkle_version.tar.xz does not match its sha256"
  tar -xJf "$tools/Sparkle.tar.xz" -C "$tools" bin
  rm "$tools/Sparkle.tar.xz"
fi

# generate_appcast reads a folder: the zip and, under the archive's name, the notes it embeds. Nothing else.
stage="build/appcast"
rm -rf "$stage"
mkdir -p "$stage"
cp "$zip" "$stage/Pullglance.zip"
cp "$notes" "$stage/Pullglance.md"

private_key() {
  if [[ -n "$key_file" ]]; then
    cat "$key_file"
  else
    gpg --quiet --decrypt "${PULLGLANCE_SPARKLE_KEY:-$HOME/.config/pullglance/sparkle-ed25519.key.gpg}"
  fi
}

echo "==> appcast for $version"
rm -f "$out"   # generate_appcast would "update" an item left over from an earlier run instead of writing this one
private_key | "$tools/bin/generate_appcast" --ed-key-file - \
  --download-url-prefix "$prefix" \
  --embed-release-notes -o "$out" "$stage"

# The key that signed must be the key the app carries, or every installed copy refuses the update.
swift Scripts/verify-appcast.swift "$out" "$zip" "$public_key"
