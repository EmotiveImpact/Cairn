#!/bin/bash
# Fast LOCAL build → assemble Cairn.app → Developer ID sign (hardened runtime,
# entitlements) — NOT notarized. A Developer-ID-signed local build runs with a
# stable identity (so TCC / Full Disk Access is attributed correctly). For
# distribution use build_release.sh (universal + notarized). See ../mac-apps/SIGNING.md.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Cairn"
ARCH="${ARCH:-$(uname -m)}"
# Each invocation owns a new directory. Never replace an installed/running
# executable or the last successful build, including on signing failure.
mkdir -p dist
BUILD_DIR="$(mktemp -d "dist/local.XXXXXX")"
APP="$BUILD_DIR/${APP_NAME}.app"
touch "$BUILD_DIR/INCOMPLETE"
trap 'status=$?; if [ "$status" -ne 0 ]; then echo "Build failed; incomplete artifacts retained at $BUILD_DIR" >&2; fi' EXIT

# Keep the newest few finished builds (KEEP_BUILDS, 3 by default, counting this
# one) so dist/ stops growing by a full app on every run. A failed build is
# kept for a day so its error can be looked at. A build whose app is running is
# never touched, and nothing outside dist/PREFIX.* is ever removed.
prune_old_builds() {
  local prefix="$1" keep="${KEEP_BUILDS:-3}" kept=0 dir
  case "$keep" in ''|*[!0-9]*) keep=3 ;; esac
  [ "$keep" -ge 1 ] || keep=1
  while IFS= read -r dir; do
    case "$dir" in "dist/$prefix."?*) ;; *) continue ;; esac
    [ -d "$dir" ] && [ ! -L "$dir" ] || continue
    if [ "$dir" = "$BUILD_DIR" ]; then kept=$((kept + 1)); continue; fi
    if [ -e "$dir/INCOMPLETE" ]; then
      [ -n "$(find "$dir/INCOMPLETE" -mmin +1440 2>/dev/null)" ] || continue
    elif [ "$kept" -lt "$keep" ]; then
      kept=$((kept + 1)); continue
    fi
    if pgrep -f "/$dir/" >/dev/null 2>&1; then
      echo "▸ Keeping $dir: its app is running."
      continue
    fi
    rm -rf "$dir"
    echo "▸ Removed old build $dir"
  done < <(ls -1dt "dist/$prefix."* 2>/dev/null)
}
ENTITLEMENTS="${APP_NAME}/${APP_NAME}-dist.entitlements"

IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/')"
[ -z "${IDENTITY:-}" ] && { echo "✗ No Developer ID Application certificate."; exit 1; }
echo "▸ Signing as: $IDENTITY"

echo "▸ swift build -c release --arch $ARCH"
swift build -c release -j "${BUILD_JOBS:-2}" --arch "$ARCH"
BIN=".build/${ARCH}-apple-macosx/release/${APP_NAME}"
BUNDLE=".build/${ARCH}-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp "${APP_NAME}/Info.plist" "$APP/Contents/Info.plist"
[ -d "$BUNDLE" ] && cp -R "$BUNDLE" "$APP/Contents/Resources/"
cp "${APP_NAME}/Resources/${APP_NAME}.icns" "$APP/Contents/Resources/"
cp "${APP_NAME}/Resources/CairnMark.png" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/hero.png" ] && cp "${APP_NAME}/Resources/hero.png" "$APP/Contents/Resources/"
[ -f "${APP_NAME}/Resources/SampleCoastFilm.png" ] && cp "${APP_NAME}/Resources/SampleCoastFilm.png" "$APP/Contents/Resources/"
for m in "${APP_NAME}"/Resources/logo-*.svg; do [ -f "$m" ] && cp "$m" "$APP/Contents/Resources/"; done

codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
rm "$BUILD_DIR/INCOMPLETE"
prune_old_builds local
echo "✅ $APP — signed (Developer ID, not notarized). Launch: open -n $APP"
