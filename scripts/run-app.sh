#!/bin/bash
# Build and launch ADV Downloader as a real .app bundle (keyboard shortcuts, notifications, Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN=".build/out/Products/Debug/Y-Downloader"
[ -x "$BIN" ] || BIN=".build/debug/Y-Downloader"
APP=".build/ADV Downloader.app"
rm -rf ".build/Y-Downloader.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Y-Downloader"
# SwiftPM resource bundles (e.g. the public-suffix list used by the ad-block converter) must sit in Resources,
# otherwise Bundle.module traps at launch.
mkdir -p "$APP/Contents/Resources"
cp Y-Downloader/Resources/AppIcon.icns "$APP/Contents/Resources/"
for b in "$(dirname "$BIN")"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done
sed -e 's/$(DEVELOPMENT_LANGUAGE)/en/' -e 's/$(EXECUTABLE_NAME)/Y-Downloader/' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.ydownloader.Y-Downloader/' -e 's/$(PRODUCT_NAME)/ADV Downloader/' \
    Y-Downloader/Resources/Info.plist > "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
pkill -f "Contents/MacOS/Y-Downloader" 2>/dev/null || true
open "$APP"
