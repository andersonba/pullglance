#!/bin/bash
# Builds Pullglance.app from the SwiftPM release binary. Usage: Scripts/make-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source version.env
APP_NAME="Pullglance"
BUNDLE_ID="com.andersonba.pullglance"
OUT="build/$APP_NAME.app"
RELEASE=".build/release"

echo "==> swift build -c release"
swift build -c release

echo "==> assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$RELEASE/$APP_NAME" "$OUT/Contents/MacOS/$APP_NAME"
cp -R "$RELEASE/${APP_NAME}_${APP_NAME}.bundle" "$OUT/Contents/Resources/"

echo "==> icon"
swift Scripts/make-icon.swift build/AppIcon.iconset
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
</dict>
</plist>
PLIST

echo "==> codesign (ad hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$OUT"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> installing to /Applications"
  osascript -e 'tell application "Pullglance" to quit' >/dev/null 2>&1 || true
  # Give the old instance a moment to exit, otherwise `open` fails with -600.
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.3; done
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$OUT" "/Applications/$APP_NAME.app"
  # LaunchServices can still report the quitting instance for a moment (error -600); retry a few times.
  for _ in 1 2 3 4 5; do open "/Applications/$APP_NAME.app" 2>/dev/null && break; sleep 1; done
fi

echo "done: $OUT (v$VERSION)"
