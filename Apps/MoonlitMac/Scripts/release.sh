#!/bin/bash
# Archives, signs, notarizes, staples, and Sparkle-signs a release build of
# Moonlit for Mac. See docs/updates.md for the one-time setup this depends
# on (Developer ID Application cert, `notarytool store-credentials`).
#
# Usage: Scripts/release.sh <version>
#   e.g. Scripts/release.sh 2.5.0
#
# Ships a .dmg rather than a .zip on purpose. A zip has to be *extracted* by
# whatever the user's browser or unarchiver happens to be, and tools that
# don't understand macOS extended attributes drop AppleDouble (`._Foo`)
# sidecar files into every embedded framework's root. That breaks the code
# signature seal — `codesign` then reports "unsealed contents present in the
# root directory of an embedded framework" and Gatekeeper tells the user
# "Apple could not verify..." even though the build is correctly notarized.
# A disk image is a real filesystem: symlinks, xattrs and the bundle layout
# survive the round trip untouched, and the user gets the familiar
# drag-to-Applications window.
#
# Prints a ready-to-paste <item> block for the appcast at the end.
set -euo pipefail

VERSION="${1:?Usage: Scripts/release.sh <version>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-moonlit-notary}"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Moonlit.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
# Intermediate only — notarytool needs a container to submit the .app in.
ZIP_PATH="$BUILD_DIR/MoonlitMac-notarize.zip"
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/Moonlit-$VERSION.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Archiving (Release, Developer ID signing + Hardened Runtime)"
xcodebuild archive \
  -project MoonlitMac.xcodeproj \
  -scheme MoonlitMac \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS"

echo "==> Exporting signed .app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist docs/ExportOptions-DeveloperID.plist \
  -allowProvisioningUpdates

APP_PATH="$EXPORT_PATH/MoonlitMac.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: expected app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Notarizing the app (this can take a few minutes)"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$ZIP_PATH"

# Staple the app itself as well as the disk image below, so the ticket is
# still present after the user drags it out of the DMG — otherwise a first
# launch with no network can't verify.
echo "==> Stapling the app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Building disk image"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
# ditto (not cp) — it preserves symlinks and extended attributes, which is
# the whole point of shipping a DMG in the first place.
ditto "$APP_PATH" "$DMG_STAGING/MoonlitMac.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "Moonlit" \
  -srcfolder "$DMG_STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "==> Signing the disk image"
codesign --force --sign "Developer ID Application" --timestamp "$DMG_PATH"

echo "==> Notarizing the disk image (this can take a few minutes)"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the disk image"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> Verifying Gatekeeper accepts it"
spctl -a -vvv --type execute "$APP_PATH"

echo "==> Locating Sparkle's sign_update tool"
SIGN_UPDATE="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path "*artifacts/sparkle/Sparkle/bin/sign_update" -print -quit 2>/dev/null)"
if [ -z "$SIGN_UPDATE" ]; then
  echo "error: couldn't find sign_update under DerivedData — build the app in Xcode at least once first" >&2
  exit 1
fi

echo "==> Signing update with Sparkle's EdDSA key"
SIGNATURE_LINE="$("$SIGN_UPDATE" "$DMG_PATH")"

echo
echo "Done: $DMG_PATH"
echo
echo "1. Copy the dmg into the portal repo:"
echo "     cp \"$DMG_PATH\" ../../moonlit-portal/public/downloads/"
echo "2. Add this <item> to moonlit-portal/public/appcast.xml:"
echo
cat <<EOF
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's new</h2>
        <ul>
          <li>TODO — copy from ReleaseNotesCatalog.current in WhatsNewView.swift</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://trymoonlit.app/downloads/Moonlit-$VERSION.dmg"
        $SIGNATURE_LINE
        type="application/x-apple-diskimage" />
    </item>
EOF
echo
echo "3. Point the macOS card in moonlit-portal/src/routes/public/DownloadPage.tsx at the new version"
echo "4. Update ReleaseNotesCatalog.current in Sources/Components/WhatsNewView.swift to match"
echo "5. Commit + push moonlit-portal (Vercel deploys trymoonlit.app)"
