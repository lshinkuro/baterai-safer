#!/bin/sh
# Wraps the release binary into "Baterai Safer.app" (name + icon in permission dialogs, Finder, Spotlight).
set -e
cd "$(dirname "$0")/.."
APP=".build/Baterai Safer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/baterai-safer "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
sed "s/__VERSION__/${1:-dev}/" Resources/Info.plist > "$APP/Contents/Info.plist"
# Ad-hoc signature binds the bundle id; no Developer ID, so macOS may re-ask permissions after updates.
codesign --force --sign - "$APP"
echo "$APP"
