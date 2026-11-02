#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# WVDH_ARCH and WVDH_BUILD_DIR let the release scripts build one architecture at
# a time into separate directories without changing the local defaults.
ARCH="${WVDH_ARCH:-arm64}"
BUILD_DIR="${WVDH_BUILD_DIR:-$SCRIPT_DIR/.build}"
APP_DIR="$BUILD_DIR/MacVirtualDesktopHelper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
mkdir -p "$RESOURCES_DIR"
cp "$SCRIPT_DIR/LICENSE.md" "$RESOURCES_DIR/LICENSE.md"
cp "$SCRIPT_DIR/Native/YABAI-LICENSE.txt" "$RESOURCES_DIR/YABAI-LICENSE.txt"
cp "$SCRIPT_DIR/Resources/Icons/MacVirtualDesktopHelper.icns" "$RESOURCES_DIR/MacVirtualDesktopHelper.icns"
cp "$SCRIPT_DIR/Resources/Icons/png/icon.png" "$RESOURCES_DIR/MacVirtualDesktopHelper.png"

if xcrun -f swiftc >/dev/null 2>&1; then
	SWIFTC=(xcrun swiftc)
	CLANG=(xcrun clang)
else
	# xcrun refuses to run until the Xcode license is accepted, while the
	# standalone Command Line Tools toolchain remains usable.
	CLT_BIN=/Library/Developer/CommandLineTools/usr/bin
	SWIFTC=("$CLT_BIN/swiftc")
	CLANG=("$CLT_BIN/clang")
fi

"${CLANG[@]}" -target "$ARCH-apple-macos13.0" -fobjc-arc -O2 -c "$SCRIPT_DIR/Native/SkyLightBridge.m" -o "$BUILD_DIR/SkyLightBridge.o"

"${SWIFTC[@]}" -target "$ARCH-apple-macos13.0" \
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
	if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
		codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
	else
		codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
	fi
else
	echo "warning: no code signing identity found, falling back to an ad hoc signature." >&2
	echo "warning: system permissions must be granted again after every rebuild." >&2
	codesign --force --deep --sign - "$APP_DIR"
fi
echo "$APP_DIR"
