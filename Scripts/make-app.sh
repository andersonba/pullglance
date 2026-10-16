#!/bin/bash
# Builds Pullglance.app from the SwiftPM release binary. Usage: Scripts/make-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source version.env
APP_NAME="Pullglance"
BUNDLE_ID="com.andersonba.pullglance"
# Sparkle: where the app looks for releases, and the public half of the key that signs them. The private half
# lives GPG-encrypted outside the repository and is only ever read by Scripts/make-appcast.sh.
SPARKLE_FEED_URL="https://github.com/andersonba/pullglance/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="REPLACE-WITH-THE-PRODUCTION-PUBLIC-KEY"
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
# A rehearsal runs beside the installed app, under its own identity, against a local feed signed with a
# throwaway key. Read here only; the app never sees these.
VERSION="${PULLGLANCE_REHEARSAL_VERSION:-$VERSION}"
BUNDLE_ID="${PULLGLANCE_REHEARSAL_BUNDLE_ID:-$BUNDLE_ID}"
SPARKLE_FEED_URL="${PULLGLANCE_REHEARSAL_FEED_URL:-$SPARKLE_FEED_URL}"
SPARKLE_PUBLIC_KEY="${PULLGLANCE_REHEARSAL_PUBLIC_KEY:-$SPARKLE_PUBLIC_KEY}"
[[ "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "make-app: SPARKLE_PUBLIC_KEY is not an EdDSA public key; an app built with it could never update" >&2; exit 1; }
ATS=""
[[ -n "${PULLGLANCE_REHEARSAL_FEED_URL:-}" ]] && ATS='<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>'
OUT="build/$APP_NAME.app"
RELEASE=".build/release"

echo "==> swift build -c release"
swift build -c release

echo "==> assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$RELEASE/$APP_NAME" "$OUT/Contents/MacOS/$APP_NAME"
cp -R "$RELEASE/${APP_NAME}_${APP_NAME}.bundle" "$OUT/Contents/Resources/"

echo "==> Sparkle.framework"
mkdir -p "$OUT/Contents/Frameworks"
cp -R "$SPARKLE_FRAMEWORK" "$OUT/Contents/Frameworks/"

echo "==> icon"
swift Scripts/make-icon.swift Assets/mascot.png build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>pt-BR</string></array>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSFileQuarantineEnabled</key><true/>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 andersonba</string>
  <key>SUFeedURL</key><string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUAllowsAutomaticUpdates</key><false/>
  $ATS
</dict>
</plist>
PLIST

echo "==> codesign (ad hoc)"
# Sparkle's helpers ship ad-hoc signed; re-sign them here as its documentation prescribes for a bundle
# assembled outside Xcode: inside out, never --deep, hardened runtime kept.
FW="$OUT/Contents/Frameworks/Sparkle.framework"
codesign -f -s - -o runtime "$FW/Versions/B/XPCServices/Installer.xpc"
codesign -f -s - -o runtime --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
codesign -f -s - -o runtime "$FW/Versions/B/Autoupdate"
codesign -f -s - -o runtime "$FW/Versions/B/Updater.app"
codesign -f -s - -o runtime "$FW"
codesign --force --sign - --identifier "$BUNDLE_ID" "$OUT"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> installing to /Applications"
  osascript -e 'tell application "Pullglance" to quit' >/dev/null 2>&1 || true
  # Give the old instance a moment to exit, otherwise `open` fails with -600.
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.3; done
  if pgrep -x "$APP_NAME" >/dev/null; then
    echo "$APP_NAME is still running; quit it and run again" >&2
    exit 1
  fi
  # Copy next to the destination, then swap by renaming, so the installed app is whole until the new one is.
  STAGING="$(mktemp -d "/Applications/.$APP_NAME.XXXXXX")"
  cp -R "$OUT" "$STAGING/$APP_NAME.app"
  [[ -d "/Applications/$APP_NAME.app" ]] && mv "/Applications/$APP_NAME.app" "$STAGING/old.app"
  mv "$STAGING/$APP_NAME.app" "/Applications/$APP_NAME.app"
  rm -rf "$STAGING"
  # LaunchServices can still report the quitting instance for a moment (error -600); retry a few times.
  opened=0
  for _ in 1 2 3 4 5; do
    if open "/Applications/$APP_NAME.app" 2>/dev/null; then opened=1; break; fi
    sleep 1
  done
  if [[ $opened == 0 ]]; then
    echo "installed, but could not open /Applications/$APP_NAME.app" >&2
    exit 1
  fi
fi

echo "done: $OUT (v$VERSION)"
