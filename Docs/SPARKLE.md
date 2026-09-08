# Sparkle 2 updates

Netglass uses [Sparkle 2](https://sparkle-project.org) for non–Mac App Store updates. The feed URL is:

`https://github.com/zachwilke/netglass/releases/latest/download/appcast.xml`

That is the GitHub Releases “latest” asset named `appcast.xml`. Automatic checks stay **off** until you replace the `SUPublicEDKey` placeholder in `Netglass/Info.plist`. The Check for Updates menu item stays disabled until then.

**Never commit the private EdDSA key.**

## One-time key setup (Zach)

1. On a Mac with Xcode 16+, resolve the Sparkle package (open the project once).
2. Find `generate_keys` in the Sparkle artifacts, or download the Sparkle 2 release tools from [sparkle-project/Sparkle releases](https://github.com/sparkle-project/Sparkle/releases).
3. Generate a key pair **outside the repo**:
   ```bash
   mkdir -p "$HOME/.config/netglass"
   generate_keys -p "$HOME/.config/netglass"
   ```
   This prints a public key and writes a private key. Keep the private key in a password manager or that home directory. Add `sparkle-keys/` and `ed25519-priv.key` to `.gitignore` if you ever generate inside a clone.
4. Paste the **public** key into `Netglass/Info.plist` as `SUPublicEDKey`, replacing `REPLACE_ME_RUN_GENERATE_KEYS`.
5. Optionally set `SUEnableAutomaticChecks` to `true` after the first signed release.

## Release workflow

Versioning:

- `MARKETING_VERSION` (`CFBundleShortVersionString`) — user-facing, e.g. `1.0.0`
- `CURRENT_PROJECT_VERSION` (`CFBundleVersion`) — integer Sparkle compares, must increase every published build (`1`, `2`, `3`, …)

Steps:

1. Bump both versions in the Netglass target.
2. Archive in Xcode (Release, Hardened Runtime on, Developer ID).
3. Notarize and staple the app (Apple ID / `notarytool`). Sparkle will not save you from Gatekeeper.
4. Zip the `.app`:
   ```bash
   ditto -c -k --keepParent Netglass.app Netglass.zip
   ```
5. Sign the zip with Sparkle’s `sign_update` and the **private** key:
   ```bash
   sign_update Netglass.zip
   ```
   Copy the `sparkle:edSignature` (and `length`) into `appcast.xml`. Start from `Docs/appcast.example.xml`.
6. Create a GitHub Release tagged with the marketing version (e.g. `1.0.0`).
7. Attach **both** `Netglass.zip` and `appcast.xml` as release assets. The enclosure URL in the appcast must match the zip’s download URL:
   `https://github.com/zachwilke/netglass/releases/download/1.0.0/Netglass.zip`
8. Because the feed is `…/releases/latest/download/appcast.xml`, the newest GitHub Release must include the current `appcast.xml`.

`generate_appcast` can build the XML for a folder of zips if you prefer that over hand-editing.

## What the app does

`UpdateController` starts Sparkle only when `SUPublicEDKey` is not a `REPLACE_…` placeholder. The feed URL is supplied by `SPUUpdaterDelegate` so it does not depend on generated Info.plist key filtering. Settings → Updates shows the feed and whether a real key is configured.
