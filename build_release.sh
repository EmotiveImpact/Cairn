#!/bin/bash
# Universal build → Developer ID sign → notarize → staple → shippable zip.
# See ../mac-apps/SIGNING.md. Studio prereqs already set up: Developer ID cert
# (Team FC88M2P4F9) + notary keychain profile "vlume-notary".
# Run: ./build_release.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Cairn"
CONFIG="release"
# Each invocation owns a new directory. Never replace an installed/running
# executable or the last successful build, including on signing failure.
mkdir -p dist
BUILD_DIR="$(mktemp -d "dist/release.XXXXXX")"
APP="$BUILD_DIR/${APP_NAME}.app"
touch "$BUILD_DIR/INCOMPLETE"
trap 'status=$?; if [ "$status" -ne 0 ]; then echo "Build failed; incomplete artifacts retained at $BUILD_DIR" >&2; fi' EXIT
ZIP="$BUILD_DIR/${APP_NAME}.zip"
ENTITLEMENTS="${APP_NAME}/${APP_NAME}-dist.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-vlume-notary}"

IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/')"
if [ -z "${IDENTITY:-}" ]; then
  echo "✗ No 'Developer ID Application' certificate."
  exit 1
fi
echo "▸ Signing as: $IDENTITY"

echo "▸ swift build -c $CONFIG --arch arm64 --arch x86_64"
swift build -c "$CONFIG" -j "${BUILD_JOBS:-2}" --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/${APP_NAME}"
BUNDLE=".build/apple/Products/Release/${APP_NAME}_${APP_NAME}.bundle"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp "${APP_NAME}/Info.plist" "$APP/Contents/Info.plist"
[ -d "$BUNDLE" ] && cp -R "$BUNDLE" "$APP/Contents/Resources/"
cp "${APP_NAME}/Resources/${APP_NAME}.icns" "$APP/Contents/Resources/"
cp "${APP_NAME}/Resources/CairnMark.png" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/hero.png" ] && cp "${APP_NAME}/Resources/hero.png" "$APP/Contents/Resources/"
for m in "${APP_NAME}"/Resources/logo-*.svg; do [ -f "$m" ] && cp "$m" "$APP/Contents/Resources/"; done

# Sign nested Mach-O first (NOT resource bundles), then the app.
while IFS= read -r nested; do
  [ -n "$nested" ] && codesign --force --options runtime --timestamp --sign "$IDENTITY" "$nested"
done < <(find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" \) 2>/dev/null)
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
# The hardened runtime must be on, and none of the entitlements that would let
# other code be loaded into Cairn, or a debugger attach to it, may ship.
SIGNING="$(codesign -d --verbose=2 "$APP" 2>&1)"
if ! grep -q "flags=.*runtime" <<<"$SIGNING"; then
  echo "✗ The hardened runtime is not on."
  exit 1
fi
if ! ENTS="$(codesign -d --entitlements - "$APP")"; then
  echo "✗ Could not inspect signed entitlements; release stopped before notarization." >&2
  exit 1
fi
for bad in disable-library-validation allow-dyld-environment-variables allow-unsigned-executable-memory \
           allow-jit disable-executable-page-protection get-task-allow; do
  if grep -q "$bad" <<<"$ENTS"; then
    echo "✗ The entitlement $bad must not ship."
    exit 1
  fi
done
echo "▸ Signed and verified (hardened runtime on, no unsafe entitlements)."

TMPZIP="$BUILD_DIR/${APP_NAME}-notarize.zip"
ditto -c -k --keepParent "$APP" "$TMPZIP"
echo "▸ Submitting to Apple for notarization (a few minutes)…"
xcrun notarytool submit "$TMPZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$TMPZIP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
spctl -a -vvv -t execute "$APP" 2>&1 | sed 's/^/   /'
echo ""
rm "$BUILD_DIR/INCOMPLETE"
echo "✅ $ZIP — signed, notarized, stapled, universal. Requires macOS 14 or later."
