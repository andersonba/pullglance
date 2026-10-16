#!/bin/bash
# The bundle a release ships must be the production one: Scripts/check-app.sh <app> <version> <public-key>
#
# Scripts/make-app.sh takes rehearsal overrides from the environment. A release cut from a shell that still
# exports them would ship an app polling 127.0.0.1 with a throwaway key, every check in release.sh would
# still pass, and every copy that installed it would never see another update. So the built Info.plist is
# read back and compared with what a release promises, before anything is committed or tagged.
set -euo pipefail

app="${1:-}"; version="${2:-}"; public_key="${3:-}"
[[ -n "$app" && -n "$version" && -n "$public_key" ]] || { echo "usage: Scripts/check-app.sh <app> <version> <public-key>" >&2; exit 2; }
die() { echo "check-app: $*" >&2; exit 1; }
plist="$app/Contents/Info.plist"
[[ -f "$plist" ]] || die "$plist is missing"

value() { plutil -extract "$1" raw -o - "$plist" 2>/dev/null || true; }
expect() {
  local got; got="$(value "$1")"
  [[ "$got" == "$2" ]] || die "$1 is '$got', expected '$2'"
}
expect CFBundleIdentifier "com.andersonba.pullglance"
expect CFBundleShortVersionString "$version"
expect CFBundleVersion "$version"
expect SUFeedURL "https://github.com/andersonba/pullglance/releases/latest/download/appcast.xml"
expect SUPublicEDKey "$public_key"
[[ -z "$(value NSAppTransportSecurity)" ]] || die "NSAppTransportSecurity is set: this is a rehearsal build"
echo "check-app: $app is the production bundle, v$version"
