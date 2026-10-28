# LiquidBird

Theos tweak injected into the NeoFreeBird IPA (Twitter-branded sideload IPA from the latest NeoFreeBird release: BHTwitter, branding already reverted; v7.3.0 = Twitter 12.38.1, built with the iOS 27.1 SDK). Personal sideload only.

## Goals
1. Real iOS 26 Liquid Glass: floating glass pill/rail for the tab bar, glass on nav bars and post-detail buttons.
2. Remove Grok everywhere: tab, per-tweet button, post-detail floating button, "..." menu items.
3. Remove Live / Spaces / broadcasts from timelines and the Spaces bar.
4. Ads, premium upsells and banners: rely on NeoFreeBird's BHTwitter toggles first; hook only what survives.

## Layout
- `Tweak.x`             all hooks (Logos)
- `LiquidBird.plist`    bundle filter (com.atebits.Tweetie2)
- `scripts/patch_glass.sh <in.ipa> <out.ipa>`  strips UIDesignRequiresCompatibility so stock UIKit chrome gets Liquid Glass; raises the Mach-O SDK to 26.0 only if it's older (never lowers it, keeps minos). Needs Xcode `vtool`, macOS only
- `scripts/build.sh`    full pipeline: fetch NeoFreeBird IPA, patch, `make package`, inject with `cyan`
- `.github/workflows/build.yml`  same pipeline on macOS runners, uploads unsigned IPA as a workflow artifact (never a public release)

## Rules
- Class names marked `// placeholder` are unverified. Confirm in FLEX before relying on them: the IPA already ships BHTwitter's FLEX (`libbhFLEX.dylib`, try its toggle in BHTwitter settings first), else inject FLEXing (`scripts/build.sh --flex <FLEXing.deb>`, or run the workflow with `flex`). Placeholder hooks live in their own `%group`, initialised in `%ctor` only if `objc_getClass` finds the class; keep it that way (Logos doesn't check, and a nil class can crash at launch). Prefer matching on accessibilityLabel/identifier over private class names; they survive app updates.
- Guard every iOS 26 API with `if (@available(iOS 26, *))`. Deployment target stays 15.0.
- No global hooks on `UIView -layoutSubviews`; too hot. `UIControl -didMoveToWindow` is the widest acceptable hook.
- Never commit IPAs, decrypted binaries, or signing certs. `.gitignore` covers them.
- Output IPA is unsigned. User signs/installs with SideStore, Sideloadly, or Feather.

## Commands
- `make package FINALPACKAGE=1`  builds `packages/*.deb`
- `./scripts/build.sh`           end to end, output `out/LiquidBird.ipa`
