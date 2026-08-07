#!/bin/bash
# Archives, signs, notarizes, staples, and Sparkle-signs a release build of
# Moonlit for Mac. See docs/updates.md for the one-time setup this depends
# on (Developer ID Application cert, `notarytool store-credentials`).
#
# Usage: Scripts/release.sh <version>
#   e.g. Scripts/release.sh 2.5.0
#
# Prints a ready-to-paste <item> block for moonlit-web/public/appcast.xml
# at the end.
set -euo pipefail

VERSION="${1:?Usage: Scripts/release.sh <version>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-moonlit-notary}"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Moonlit.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
ZIP_PATH="$BUILD_DIR/Moonlit-$VERSION.zip"

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

echo "==> Zipping for notarization"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting to notarytool (this can take a few minutes)"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Re-zipping stapled app (the ticket has to be inside what users download)"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Locating Sparkle's sign_update tool"
SIGN_UPDATE="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path "*artifacts/sparkle/Sparkle/bin/sign_update" -print -quit 2>/dev/null)"
if [ -z "$SIGN_UPDATE" ]; then
  echo "error: couldn't find sign_update under DerivedData — build the app in Xcode at least once first" >&2
  exit 1
fi

echo "==> Signing update with Sparkle's EdDSA key"
SIGNATURE_LINE="$("$SIGN_UPDATE" "$ZIP_PATH")"

echo
echo "Done: $ZIP_PATH"
echo
echo "1. Upload $ZIP_PATH as a release asset on zainalabidinaa/moonlit-web (tag: $VERSION)"
echo "2. Add this <item> to moonlit-web/public/appcast.xml:"
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
        url="https://github.com/zainalabidinaa/moonlit-web/releases/download/$VERSION/Moonlit-$VERSION.zip"
        $SIGNATURE_LINE
        type="application/octet-stream" />
    </item>
EOF
echo
echo "3. Update ReleaseNotesCatalog.current in Sources/Components/WhatsNewView.swift to match"
echo "4. Deploy moonlit-web and push"
