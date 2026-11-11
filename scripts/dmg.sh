#!/bin/sh
# Builds .build/Poni.dmg (app + Applications shortcut) for direct download.
set -e
cd "$(dirname "$0")/.."
swift build -c release
scripts/bundle.sh "${1:-dev}"
STAGE=.build/dmg
rm -rf "$STAGE" .build/Poni.dmg
mkdir -p "$STAGE"
cp -R .build/Poni.app "$STAGE/"
# Hidden copy under the old name: v0.6.10 (Baterai Safer) auto-updates by copying "Baterai Safer.app" out of the DMG.
cp -R .build/Poni.app "$STAGE/Baterai Safer.app"
chflags hidden "$STAGE/Baterai Safer.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Poni" -srcfolder "$STAGE" -format UDZO -ov .build/Poni.dmg >/dev/null
if [ -n "$SIGN_ID" ]; then
  # Gatekeeper opens a notarized, stapled DMG without "Open Anyway", even offline.
  codesign --sign "$SIGN_ID" --timestamp .build/Poni.dmg
  xcrun notarytool submit .build/Poni.dmg --keychain-profile poni --wait
  xcrun stapler staple .build/Poni.dmg
fi
echo .build/Poni.dmg
