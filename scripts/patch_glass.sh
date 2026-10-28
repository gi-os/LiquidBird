#!/usr/bin/env bash
# Usage: patch_glass.sh <in.ipa> <out.ipa>   (macOS + Xcode 26 required)
set -euo pipefail
IN="$(realpath "$1")"; OUT="$(realpath -m "$2")"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

unzip -q "$IN" -d "$WORK"
APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)"
BIN="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"

/usr/libexec/PlistBuddy -c "Delete :UIDesignRequiresCompatibility" "$APP/Info.plist" 2>/dev/null || true
xcrun vtool -set-build-version ios 15.0 26.0 -replace -output "$BIN" "$BIN"
xcrun vtool -show-build "$BIN" | grep -q "sdk 26.0" && echo "SDK bumped: $BIN"

( cd "$WORK" && zip -qry "$OUT" Payload )
echo "wrote $OUT"
