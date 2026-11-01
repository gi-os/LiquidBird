#!/bin/bash
# syntax_check.sh: a fast stand-in for the Theos build's compile step (macOS, Xcode). Each .x file is turned
# into plain Objective-C by delogos.py and checked with clang -fsyntax-only -fobjc-arc -Wall -Werror against
# the iOS SDK, as Theos builds it. Catches -Werror failures in seconds; the Actions build stays the real check.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
status=0
for f in *.x; do
  # A group set up twice hooks its methods twice (each hook then runs on top of itself).
  dup="$(grep -oE '%init\([A-Za-z0-9_]+\)' "$f" | sort | uniq -d)"
  if [ -n "$dup" ]; then echo "$f: initialised more than once: $dup"; status=1; fi
  python3 -I scripts/delogos.py "$f" "$OUT/${f%.x}.m"
  # Two warnings only the stand-in trips: hooks become categories, and %orig isn't a [super ...] call.
  if ! xcrun --sdk iphoneos clang -fsyntax-only -fobjc-arc -Wall -Werror -Wno-objc-protocol-method-implementation \
       -Wno-objc-missing-super-calls -target arm64-apple-ios15.0 -isysroot "$SDK" "$OUT/${f%.x}.m"; then
    echo "$f: errors above (line numbers are close to the .x file's)"; status=1
  fi
done
[ $status -eq 0 ] && echo "all .x files pass"
exit $status
