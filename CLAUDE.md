# LiquidBird

Theos tweak injected into the NeoFreeBird IPA (Twitter 11.33 + BHTwitter, branding already reverted). Personal sideload only.

## Goals
1. Real iOS 26 Liquid Glass: floating glass pill/rail for the tab bar, glass on nav bars and post-detail buttons.
2. Remove Grok everywhere: tab, per-tweet button, post-detail floating button, "..." menu items.
3. Remove Live / Spaces / broadcasts from timelines and the Spaces bar.
4. Ads, premium upsells and banners: rely on NeoFreeBird's BHTwitter toggles first; hook only what survives.

## Layout
- `Tweak.x`             all hooks (Logos)
- `LiquidBird.plist`    bundle filter (com.atebits.Tweetie2)
- `scripts/patch_glass.sh <in.ipa> <out.ipa>`  strips UIDesignRequiresCompatibility, bumps Mach-O SDK to 26.0 so stock UIKit chrome gets Liquid Glass (needs Xcode `vtool`, macOS only)
- `scripts/build.sh`    full pipeline: fetch NeoFreeBird IPA, patch, `make package`, inject with `cyan`
- `.github/workflows/build.yml`  same pipeline on macOS runners, uploads unsigned IPA as a workflow artifact (never a public release)

## Rules
- Class names marked `// placeholder` are unverified. Confirm in FLEX (inject FLEXing via `scripts/build.sh --flex <FLEXing.deb>`) before relying on them. Prefer matching on accessibilityLabel/identifier over private class names; they survive app updates.
- Guard every iOS 26 API with `if (@available(iOS 26, *))`. Deployment target stays 15.0.
- No global hooks on `UIView -layoutSubviews`; too hot. `UIControl -didMoveToWindow` is the widest acceptable hook.
- Never commit IPAs, decrypted binaries, or signing certs. `.gitignore` covers them.
- Output IPA is unsigned. User signs/installs with SideStore, Sideloadly, or Feather.

## Commands
- `make package FINALPACKAGE=1`  builds `packages/*.deb`
- `./scripts/build.sh`           end to end, output `out/LiquidBird.ipa`
