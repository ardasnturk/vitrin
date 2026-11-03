#!/usr/bin/env bash
# Builds, signs (Developer ID), notarizes and staples Vitrin for Mac and packages it as a DMG for GitHub Releases and
# Homebrew.
#
# Requirements (see docs/RELEASE.md):
#   * Xcode and XcodeGen, with a "Developer ID Application" certificate of team 5JMD3VSD7N
#   * dmgbuild for the designed DMG window: `pipx install dmgbuild`
#   * notarytool credentials stored once with:
#       xcrun notarytool store-credentials pilothouse-notary \
#         --apple-id <apple-id> --team-id 5JMD3VSD7N --password <app-specific-password>
#     (or set NOTARY_PROFILE to another stored profile)
#
# Output: dist/Vitrin-<version>.dmg (+ .sha256)
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-pilothouse-notary}"
VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*: *"?([0-9.]+)"?.*/\1/')}"
BUILD="build/mac"
DIST="dist"
ARCHIVE="$BUILD/Vitrin.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/Vitrin.app"
DMG="$DIST/Vitrin-$VERSION.dmg"

rm -rf "$BUILD" && mkdir -p "$BUILD" "$DIST"
xcodegen generate >/dev/null

echo "▸ Archiving Vitrin $VERSION"
xcodebuild archive \
  -project VitrinMac.xcodeproj -scheme VitrinMac -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION"

echo "▸ Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/export/ExportOptions-mac.plist \
  -exportPath "$EXPORT"

echo "▸ Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E "^Identifier|^TeamIdentifier|^Authority=Developer ID Application"

echo "▸ Notarizing the app"
ditto -c -k --keepParent "$APP" "$BUILD/Vitrin.zip"
xcrun notarytool submit "$BUILD/Vitrin.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

echo "▸ Building the DMG"
rm -f "$DMG"
DMGBUILD="${DMGBUILD:-$(command -v dmgbuild || true)}"
if [[ -z "$DMGBUILD" ]]; then
  # A release DMG without its designed window is a mistake, not a fallback.
  echo "dmgbuild not found. Install it (pipx install dmgbuild) or point DMGBUILD at it." >&2
  exit 1
fi
"$DMGBUILD" -s scripts/dmg/settings.py -D app="$APP" "Vitrin" "$DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "▸ Checking the app inside the DMG"
CHECK="$BUILD/dmg-check"
rm -rf "$CHECK" && mkdir -p "$CHECK"
MOUNT=$(hdiutil attach -nobrowse -readonly -noautoopen "$DMG" | tail -1 | awk -F'\t' '{print $NF}')
ditto "$MOUNT/Vitrin.app" "$CHECK/Vitrin.app"
hdiutil detach "$MOUNT" -quiet
codesign --verify --deep --strict "$CHECK/Vitrin.app"

echo "▸ Notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

(cd "$DIST" && shasum -a 256 "Vitrin-$VERSION.dmg") | tee "$DMG.sha256"

echo "✔ $DMG"
echo "Next: docs/RELEASE.md"
