#!/usr/bin/env bash
# Usage: build.sh [--ipa NeoFreeBird.ipa] [--flex FLEXing.deb]
set -euo pipefail
cd "$(dirname "$0")/.."
IPA=""; FLEX=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ipa)  IPA="$2"; shift 2 ;;
    --flex) FLEX="$2"; shift 2 ;;
    *) echo "unknown arg $1"; exit 1 ;;
  esac
done

mkdir -p out
if [[ -z "$IPA" ]]; then
  # The release also has an X-branded IPA and TrollStore .tipa files; take the Twitter-branded sideload one.
  gh release download -R NeoFreeBird/app -p 'NeoFreeBird-sideloaded-Twitter_*.ipa' -D out --clobber
  IPA="$(ls -t out/NeoFreeBird-sideloaded-Twitter_*.ipa | head -1)"
fi

./scripts/patch_glass.sh "$IPA" out/glass.ipa
rm -rf packages   # make clean keeps old debs, and every deb here gets injected
make clean package FINALPACKAGE=1

DEBS=(packages/*.deb)
[[ -n "$FLEX" ]] && DEBS+=("$FLEX")
cyan -i out/glass.ipa -o out/LiquidBird.ipa -f "${DEBS[@]}" -s --overwrite
echo "done: out/LiquidBird.ipa (unsigned, sign with SideStore/Sideloadly/Feather)"
