# Dorothy

## Build

- `scripts/bundle.sh`: builds `build/Dorothy.app`, ad-hoc signed. Use it for local runs and testing.
- `scripts/bundle.sh --release`: does the same build, then Developer ID signs, notarizes, staples and verifies it with `notarize-app`. The file to ship is `build/Dorothy.zip`.

## Releasing

- Release with `scripts/release.sh <version>` (e.g. `1.1`) from a clean tree. It runs `VERSION=<version> scripts/bundle.sh --release`, signs `build/Dorothy.zip` for Sparkle, writes `build/appcast.xml`, tags `v<version>` and creates the GitHub release with both files. The app's update feed is the latest release's `appcast.xml`.
- The Sparkle EdDSA private key lives in `~/.sparkle/dorothy_ed25519_private_key` (not the keychain; public key is `SUPublicEDKey` in `scripts/bundle.sh`). Keep a backup of that file. Losing it means installed copies can never update again. Never recreate or replace it, and never use the keychain's default `ed25519` Sparkle key (it belongs to another app).
- `--release` only works on a Mac set up with the `apple-notarize-setup` skill. That Mac has `notarize-app` on PATH, the `Developer ID Application: Brandon Wilcox (99PD7P7558)` identity, and the `apple-signing` notary profile. Elsewhere, ask the user, and never try to recreate signing credentials.
- `Resources/Dorothy.entitlements` holds Dorothy's hardened-runtime entitlements. Keep `com.apple.security.device.audio-input`: without it, the notarized build silently loses the microphone (`Sources/Dorothy/Dictation.swift`). Any new capability that hardened runtime blocks needs its entitlement added here: camera, Apple Events, JIT, unsigned libraries.
- If notarization fails, `notarize-app` saves Apple's log as `build/notarization-<id>.json`. The `apple-notarize-setup` skill maps each issue to a fix.
- A passing notarization doesn't mean the app works. Open the notarized `build/Dorothy.app` and test dictation (⌃⌥D) before shipping.
