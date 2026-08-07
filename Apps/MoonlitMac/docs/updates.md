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
   archives with the Developer ID identity, exports, submits to
   `notarytool` and waits, staples the ticket, re-zips, signs the zip with
   Sparkle's key, and prints a ready-to-paste `<item>` block with the
   `sparkle:edSignature` and `length` already filled in.
3. Paste that `<item>` into `moonlit-web/public/appcast.xml` (see the
   template below) and upload the printed zip path as a release asset on
   `zainalabidinaa/moonlit-web` under a matching version tag.
4. Update `ReleaseNotesCatalog.current` in `WhatsNewView.swift` to match —
   this is what users see in-app, independent of the appcast's own
   `<description>`.
5. Deploy `moonlit-web` (picks up the new `appcast.xml`) and push the
   Moonlit for Mac commit. Existing installs pick up the update on their
   next automatic check (or immediately via Settings → Account → Software
   Update → Check Now).

## appcast.xml template

See `appcast.example.xml` in this folder. `<description>` accepts HTML —
keep it short, it's shown inside Sparkle's own update-available dialog.
