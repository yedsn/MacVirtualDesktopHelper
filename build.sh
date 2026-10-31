#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_DIR="$BUILD_DIR/MacVirtualDesktopHelper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

mkdir -p "$MACOS_DIR"
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

xcrun clang -target arm64-apple-macos13.0 -fobjc-arc -O2 -c "$SCRIPT_DIR/Native/SkyLightBridge.m" -o "$BUILD_DIR/SkyLightBridge.o"

xcrun swiftc -target arm64-apple-macos13.0 \
	-swift-version 5 \
	-O \
	-framework AppKit \
	-framework ApplicationServices \
	-framework CoreGraphics \
	"$SCRIPT_DIR"/Sources/MacVirtualDesktopHelper/*.swift \
	"$BUILD_DIR/SkyLightBridge.o" \
	-o "$MACOS_DIR/MacVirtualDesktopHelper"

# Sign with a stable identity when one is available. An ad hoc signature changes
# its hash on every build, which silently invalidates the Accessibility and
# Screen Recording grants the system stores for this bundle.
SIGN_IDENTITY="${WVDH_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
	SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p' | head -n 1)"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
	codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"
else
	echo "warning: no code signing identity found, falling back to an ad hoc signature." >&2
	echo "warning: system permissions must be granted again after every rebuild." >&2
	codesign --force --sign - "$APP_DIR"
fi
echo "$APP_DIR"
