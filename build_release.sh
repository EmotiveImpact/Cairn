#!/bin/bash
# Universal build → Developer ID sign → notarize → staple → shippable zip.
# See ../mac-apps/SIGNING.md. Studio prereqs already set up: Developer ID cert
# (Team FC88M2P4F9) + notary keychain profile "vlume-notary".
# Run: ./build_release.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Cairn"
CONFIG="release"
APP="dist/${APP_NAME}.app"
ZIP="dist/${APP_NAME}.zip"
ENTITLEMENTS="${APP_NAME}/${APP_NAME}-dist.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-vlume-notary}"

IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/')"
if [ -z "${IDENTITY:-}" ]; then
  echo "✗ No 'Developer ID Application' certificate."
  exit 1
fi
echo "▸ Signing as: $IDENTITY"

echo "▸ swift build -c $CONFIG --arch arm64 --arch x86_64"
swift build -c "$CONFIG" --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/${APP_NAME}"
BUNDLE=".build/apple/Products/Release/${APP_NAME}_${APP_NAME}.bundle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp "${APP_NAME}/Info.plist" "$APP/Contents/Info.plist"
[ -d "$BUNDLE" ] && cp -R "$BUNDLE" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/${APP_NAME}.icns" ] && cp "${APP_NAME}/Resources/${APP_NAME}.icns" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/CairnMark.png" ] && cp "${APP_NAME}/Resources/CairnMark.png" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/hero.png" ] && cp "${APP_NAME}/Resources/hero.png" "$APP/Contents/Resources/"
for m in "${APP_NAME}"/Resources/mac-*.png; do [ -f "$m" ] && cp "$m" "$APP/Contents/Resources/"; done

# Sign nested Mach-O first (NOT resource bundles), then the app.
while IFS= read -r nested; do
  [ -n "$nested" ] && codesign --force --options runtime --timestamp --sign "$IDENTITY" "$nested"
done < <(find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" \) 2>/dev/null)
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "▸ Signed and verified."

TMPZIP="dist/${APP_NAME}-notarize.zip"
ditto -c -k --keepParent "$APP" "$TMPZIP"
echo "▸ Submitting to Apple for notarization (a few minutes)…"
xcrun notarytool submit "$TMPZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$TMPZIP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl -a -vvv -t execute "$APP" 2>&1 | sed 's/^/   /'
echo ""
echo "✅ $ZIP — signed, notarized, stapled, universal. Opens cleanly on any Mac."
