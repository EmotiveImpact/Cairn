#!/bin/bash
# Fast LOCAL build → assemble Cairn.app → Developer ID sign (hardened runtime,
# entitlements) — NOT notarized. A Developer-ID-signed local build runs with a
# stable identity (so TCC / Full Disk Access is attributed correctly). For
# distribution use build_release.sh (universal + notarized). See ../mac-apps/SIGNING.md.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Cairn"
ARCH="${ARCH:-$(uname -m)}"
APP="dist/${APP_NAME}.app"
ENTITLEMENTS="${APP_NAME}/${APP_NAME}-dist.entitlements"

IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/')"
[ -z "${IDENTITY:-}" ] && { echo "✗ No Developer ID Application certificate."; exit 1; }
echo "▸ Signing as: $IDENTITY"

echo "▸ swift build -c release --arch $ARCH"
swift build -c release --arch "$ARCH"
BIN=".build/${ARCH}-apple-macosx/release/${APP_NAME}"
BUNDLE=".build/${ARCH}-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp "${APP_NAME}/Info.plist" "$APP/Contents/Info.plist"
[ -d "$BUNDLE" ] && cp -R "$BUNDLE" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/${APP_NAME}.icns" ] && cp "${APP_NAME}/Resources/${APP_NAME}.icns" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/CairnMark.png" ] && cp "${APP_NAME}/Resources/CairnMark.png" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/hero.png" ] && cp "${APP_NAME}/Resources/hero.png" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/SampleCoastFilm.png" ] && cp "${APP_NAME}/Resources/SampleCoastFilm.png" "$APP/Contents/Resources/"
for m in "${APP_NAME}"/Resources/logo-*.svg; do [ -f "$m" ] && cp "$m" "$APP/Contents/Resources/"; done

codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "✅ $APP — signed (Developer ID, not notarized). Launch: open -n $APP"
