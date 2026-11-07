#!/bin/sh
# Builds .build/BateraiSafer.dmg (app + Applications shortcut) for direct download.
set -e
cd "$(dirname "$0")/.."
swift build -c release
scripts/bundle.sh "${1:-dev}"
STAGE=.build/dmg
rm -rf "$STAGE" .build/BateraiSafer.dmg
mkdir -p "$STAGE"
cp -R ".build/Baterai Safer.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Baterai Safer" -srcfolder "$STAGE" -format UDZO -ov .build/BateraiSafer.dmg >/dev/null
echo .build/BateraiSafer.dmg
