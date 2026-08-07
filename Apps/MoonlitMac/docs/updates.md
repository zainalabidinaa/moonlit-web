# Shipping updates outside the Mac App Store

Moonlit for Mac uses [Sparkle](https://sparkle-project.org) for updates
instead of App Store distribution. Sparkle handles checking, downloading,
signature verification, and installing; the app's own `WhatsNewView`
(`Sources/Components/WhatsNewView.swift`) handles the announcement, shown
once per version on first launch after an update lands.

## One-time setup

1. **Generate a signing key.** Done — the keypair lives in this machine's
   Keychain, and the public half is already in `project.yml` →
   `INFOPLIST_KEY_SUPublicEDKey`. To regenerate or sign from another
   machine, the Sparkle SPM package's `generate_keys` / `sign_update` tools
   are available under DerivedData (`SourcePackages/artifacts/sparkle/Sparkle/bin/`).

2. **Feed + build hosting.** `appcast.xml` is served as a static file from
   `moonlit-web/public/appcast.xml`, deployed to `trymoonlit.app` (same repo
   as the marketing site). `UpdaterService.feedURLString(for:)` points at
   `https://trymoonlit.app/appcast.xml`. Release `.zip` builds are uploaded
   as GitHub Releases assets on that repo (`zainalabidinaa/moonlit-web`).

3. **Developer ID Application certificate.** Required to sign a build for
   distribution outside the App Store (separate from the automatic "Apple
   Development" cert Xcode uses for local runs). One-time, needs a paid
   Apple Developer Program membership:
   - Apple Developer site → Certificates → **Developer ID Application** →
     upload a CSR → download and double-click the `.cer` to install (or
     Xcode → Settings → Accounts → Manage Certificates → `+` →
     Developer ID Application, which generates the CSR for you).
   - Verify it landed: `security find-identity -v -p codesigning | grep "Developer ID"`.
   - `project.yml`'s `Release` config (see `targets.MoonlitMac.settings.configs.Release`)
     already points at this identity by name and turns on Hardened Runtime,
     which notarization requires.

4. **Notarization credentials.** `notarytool` needs an API key or an
   app-specific password, stored once in Keychain under a profile name:
   ```bash
   xcrun notarytool store-credentials "moonlit-notary" \
     --apple-id "<your Apple ID email>" \
     --team-id 5TWS8P597N \
     --password "<app-specific password>"
   ```
   Generate the app-specific password at
   [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security →
   App-Specific Passwords. `Scripts/release.sh` expects the profile to be
   named `moonlit-notary` (override with the `NOTARY_PROFILE` env var).

## Per-release checklist

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Run `Scripts/release.sh <version>` (e.g. `Scripts/release.sh 2.5.0`). It
   archives with the Developer ID identity, exports, notarizes and staples
   the app, builds a signed + notarized + stapled `.dmg`, signs that dmg
   with Sparkle's key, and prints a ready-to-paste `<item>` block with the
   `sparkle:edSignature` and `length` already filled in.
3. Copy the printed dmg into `moonlit-portal/public/downloads/` and paste
   the `<item>` into `moonlit-portal/public/appcast.xml` (see the template
   below).
4. Point the macOS card in `moonlit-portal/src/routes/public/DownloadPage.tsx`
   at the new version.
5. Update `ReleaseNotesCatalog.current` in `WhatsNewView.swift` to match —
   this is what users see in-app, independent of the appcast's own
   `<description>`.
6. Commit + push `moonlit-portal` (Vercel deploys `trymoonlit.app`, which
   serves both the appcast and the download) and push the Moonlit for Mac
   commit. Existing installs pick up the update on their next automatic
   check (or immediately via Settings → Account → Software Update → Check
   Now).

## Why a .dmg and not a .zip

Ship the disk image. A zip has to be *extracted* by whatever the user's
browser or unarchiver happens to be, and tools that don't preserve macOS
extended attributes drop AppleDouble (`._Foo`) sidecar files into the root
of every embedded framework. That breaks the code signature seal:

```
codesign --verify --deep --strict /Applications/MoonlitMac.app
  → unsealed contents present in the root directory of an embedded framework
```

Gatekeeper then tells the user *"Apple could not verify 'MoonlitMac' is free
of malware..."* even though the build is correctly signed, notarized and
stapled. (`ditto -x -k` extracts the same zip perfectly — the corruption
comes from the user's unarchiver, so it isn't reproducible locally.)

A dmg is a real filesystem, so symlinks, xattrs and the bundle layout
survive untouched, and the user gets the standard drag-to-Applications
window. If a user already has a broken install, `find /Applications/MoonlitMac.app
-name "._*" -delete` restores the signature.

## appcast.xml template

See `appcast.example.xml` in this folder. `<description>` accepts HTML —
keep it short, it's shown inside Sparkle's own update-available dialog.
