#!/bin/sh
# Wraps the release binary into "Poni.app" (name + icon in permission dialogs, Finder, Spotlight).
set -e
cd "$(dirname "$0")/.."
APP=".build/Poni.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "${BIN:-.build/release/baterai-safer}" "$APP/Contents/MacOS/baterai-safer" # BIN: the App Store build lives elsewhere
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Indonesian is the source language; macOS picks en.lproj when the system language is English.
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/lottie/lottie_light.min.js "$APP/Contents/Resources/" # Lottie preview in AI → Visual
sed "s/__VERSION__/${1:-dev}/" Resources/Info.plist > "$APP/Contents/Info.plist"
if [ -n "$SIGN_ID" ]; then
  # Only a Developer ID certificate may sign the release; the keychain also holds a company one (docs/signing-plan.md).
  case "$SIGN_ID" in "Developer ID Application:"*) ;; *) echo "SIGN_ID must be a Developer ID Application certificate" >&2; exit 1;; esac
  codesign --force --options runtime --timestamp --entitlements Resources/Poni.entitlements --sign "$SIGN_ID" "$APP"
else
  # Ad-hoc signature binds the bundle id; no Developer ID, so macOS may re-ask permissions after updates.
  codesign --force --sign - "$APP"
fi
echo "$APP"
