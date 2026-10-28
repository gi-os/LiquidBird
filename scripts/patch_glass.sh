#!/usr/bin/env bash
# Usage: patch_glass.sh <in.ipa> <out.ipa>   (macOS + Xcode 26 required)
# Turns Liquid Glass on for stock UIKit chrome: drops UIDesignRequiresCompatibility and, only if the
# binary was linked against an SDK older than 26, raises its SDK to 26.0 (never lowers it; minos kept).
set -euo pipefail
IN="$(realpath "$1")"
mkdir -p "$(dirname "$2")"
OUT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

unzip -q "$IN" -d "$WORK"
APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)"
BIN="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"

/usr/libexec/PlistBuddy -c "Delete :UIDesignRequiresCompatibility" "$APP/Info.plist" 2>/dev/null || true

BUILD="$(xcrun vtool -show-build "$BIN")"
MINOS="$(awk '$1 == "minos" { print $2; exit }' <<<"$BUILD")"
SDK="$(awk '$1 == "sdk" { print $2; exit }' <<<"$BUILD")"
if [[ -z "$MINOS" || -z "$SDK" ]]; then echo "no LC_BUILD_VERSION in $BIN" >&2; exit 1; fi
if (( ${SDK%%.*} < 26 )); then
  xcrun vtool -set-build-version ios "$MINOS" 26.0 -replace -output "$BIN.new" "$BIN"
  mv "$BIN.new" "$BIN"
  xcrun vtool -show-build "$BIN" | grep -q "sdk 26.0" || { echo "SDK bump failed: $BIN" >&2; exit 1; }
  echo "SDK $SDK -> 26.0 (minos $MINOS): $BIN"
else
  echo "SDK $SDK already >= 26, left as is: $BIN"
fi

rm -f "$OUT"
( cd "$WORK" && zip -qry "$OUT" Payload )
echo "wrote $OUT"
