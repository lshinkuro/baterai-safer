#!/bin/sh
# Renders every popover tab (light + dark), every notch tab and the games page to PNGs.
# Usage: snap.sh <out-dir> [en]     ("en" renders in English and shows untranslated text in CAPITALS)
# Works on a scratch copy of the repo so Sources/ never gets the harness.
set -e
OUT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
LANG_MODE=$2
SKILL=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SKILL/../../.." && pwd)
WORK=${TMPDIR:-/tmp}/poni-snap
mkdir -p "$WORK" "$OUT"
rsync -a --delete --exclude .build --exclude .git "$REPO/" "$WORK/repo/"
cp "$SKILL/Snap.swift" "$WORK/repo/Sources/baterai-safer/"
# Add a `snap <dir>` command next to the app's normal entry point.
sed -i '' 's/^case nil: BateraiApp.main()/case "snap": MainActor.assumeIsolated { snap(args.dropFirst().first ?? ".") }\ncase nil: BateraiApp.main()/' "$WORK/repo/Sources/baterai-safer/main.swift"
cd "$WORK/repo"
swift build -c release 2>&1 | grep -E "error:|Build complete" || true
BIN=.build/release/baterai-safer
rm -rf .build/release/*.lproj
EXTRA=""
if [ "$LANG_MODE" = en ]; then
    cp -R Resources/*.lproj .build/release/   # Bundle.main of a bare binary is its folder
    EXTRA="-AppleLanguages (en) -NSShowNonLocalizedStrings YES"
fi
# The harness renders, then idles on the models' timers; stop it after it's had time to write.
$BIN snap "$OUT" $EXTRA >/dev/null 2>&1 &
PID=$!
sleep 35
kill $PID 2>/dev/null || true
ls "$OUT"
