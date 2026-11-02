#!/bin/zsh
# Build one architecture and produce distributable DMG and ZIP files.
#
#   ./scripts/release/package.sh arm64
#   ./scripts/release/package.sh x86_64 --output dist
#
# Optional notarization (CI or local):
#   WVDH_NOTARIZE=1 APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... \
#     WVDH_SIGN_IDENTITY='Developer ID Application: ...' ./scripts/release/package.sh arm64
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

ARCH=""
OUTPUT_DIR="$ROOT_DIR/dist"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--output) OUTPUT_DIR="${2:-}"; shift ;;
	-h|--help) sed -n '2,12p' "$0"; exit 0 ;;
	-*) echo "unknown option: $1" >&2; exit 2 ;;
	*) ARCH="$1" ;;
	esac
	shift
done

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
	echo "usage: $0 <arm64|x86_64> [--output DIR]" >&2
	exit 2
fi

if [[ "$OUTPUT_DIR" != /* ]]; then
	OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"

BUILD_DIR="$ROOT_DIR/.build/$ARCH"
rm -rf "$BUILD_DIR"
WVDH_ARCH="$ARCH" WVDH_BUILD_DIR="$BUILD_DIR" ./build.sh

APP_DIR="$BUILD_DIR/MacVirtualDesktopHelper.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
APP_ARCHS="$(lipo -archs "$APP_DIR/Contents/MacOS/MacVirtualDesktopHelper")"
if [[ "$APP_ARCHS" != "$ARCH" ]]; then
	echo "error: expected a $ARCH binary, got '$APP_ARCHS'" >&2
	exit 1
fi
codesign --verify --strict --verbose=2 "$APP_DIR"

if [[ "${WVDH_NOTARIZE:-0}" == "1" ]]; then
	: "${APPLE_ID:?APPLE_ID is required for notarization}"
	: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for notarization}"
	: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required for notarization}"
	if ! codesign -dv "$APP_DIR" 2>&1 | grep -q 'Developer ID Application'; then
		echo "error: notarization needs a Developer ID Application signature" >&2
		codesign -dv "$APP_DIR" 2>&1 | sed -n 's/^Authority=/Authority=/p' >&2
		exit 1
	fi
fi

STAGE_DIR="$(mktemp -d "$BUILD_DIR/dmg.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -R "$APP_DIR" "$STAGE_DIR/MacVirtualDesktopHelper.app"
ln -s /Applications "$STAGE_DIR/Applications"

BASENAME="MacVirtualDesktopHelper_${VERSION}_${ARCH}"
DMG_PATH="$OUTPUT_DIR/$BASENAME.dmg"
ZIP_PATH="$OUTPUT_DIR/$BASENAME.zip"
rm -f "$DMG_PATH" "$ZIP_PATH"

hdiutil create -volname "MacVirtualDesktopHelper" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if [[ "${WVDH_NOTARIZE:-0}" == "1" ]]; then
	xcrun notarytool submit "$DMG_PATH" \
		--apple-id "$APPLE_ID" \
		--team-id "$APPLE_TEAM_ID" \
		--password "$APPLE_APP_PASSWORD" \
		--wait
	xcrun stapler staple "$DMG_PATH"
	xcrun stapler validate "$DMG_PATH"
fi

# Keep one checksum file per architecture so parallel CI jobs do not overwrite
# each other; the release job merges them into a single SHA256SUMS asset.
shasum -a 256 "$DMG_PATH" "$ZIP_PATH" | sed "s|$OUTPUT_DIR/||" > "$OUTPUT_DIR/SHA256SUMS.$ARCH"

echo "$DMG_PATH"
echo "$ZIP_PATH"
