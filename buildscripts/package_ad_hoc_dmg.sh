#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$(mktemp -d /tmp/NetNewsWire-release.XXXXXX)}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Downloads}"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
APP_PATH="$BUILD_DIR/Build/Products/Release/NetNewsWire.app"
MOUNT_DIR=""

cleanup() {
	if [ -n "$MOUNT_DIR" ]; then
		hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
	fi
}

trap cleanup EXIT

# The local DeveloperSettings file is allowed to override project settings. Override it
# here so the package uses the production bundle identifier and no development entitlements.
if ! xcodebuild \
	-project "$ROOT_DIR/NetNewsWire.xcodeproj" \
	-scheme NetNewsWire \
	-configuration Release \
	-destination 'platform=macOS,arch=arm64' \
	-derivedDataPath "$BUILD_DIR" \
	build \
	CODE_SIGN_IDENTITY=- \
	DEVELOPMENT_TEAM= \
	CODE_SIGN_STYLE=Manual \
	ORGANIZATION_IDENTIFIER=com.ranchero \
	DEVELOPER_ENTITLEMENTS= \
	CODE_SIGN_ENTITLEMENTS= \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGNING_ALLOWED=YES \
	CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
	ENABLE_HARDENED_RUNTIME=NO \
	>"$BUILD_LOG" 2>&1; then
	tail -80 "$BUILD_LOG"
	exit 1
fi

if ! grep -q '\*\* BUILD SUCCEEDED \*\*' "$BUILD_LOG"; then
	tail -80 "$BUILD_LOG"
	exit 1
fi

test -d "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARCHITECTURES="$(lipo -info "$APP_PATH/Contents/MacOS/NetNewsWire")"
case "$ARCHITECTURES" in
*arm64*x86_64*|*x86_64*arm64*) ;;
*)
	echo "Expected a universal app, got: $ARCHITECTURES" >&2
	exit 1
	;;
esac

if codesign -dvv "$APP_PATH" 2>&1 | grep -q 'flags=.*runtime'; then
	echo "Ad-hoc package must not use hardened runtime" >&2
	exit 1
fi

codesign --verify --deep --strict "$APP_PATH"

STAGING_DIR="$(mktemp -d /tmp/NetNewsWire-dmg.XXXXXX)"
MOUNT_DIR="$(mktemp -d /tmp/NetNewsWire-dmg-mount.XXXXXX)"
DMG_PATH="$OUTPUT_DIR/NetNewsWire-$VERSION.dmg"

mkdir -p "$OUTPUT_DIR"
ditto "$APP_PATH" "$STAGING_DIR/NetNewsWire.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "NetNewsWire $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

# Exercise the exact artifact users will mount, catching dyld failures that codesign
# verification alone does not report.
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
LAUNCH_LOG="$BUILD_DIR/dmg-launch.log"
"$MOUNT_DIR/NetNewsWire.app/Contents/MacOS/NetNewsWire" >"$LAUNCH_LOG" 2>&1 &
PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
	if ! kill -0 "$PID" 2>/dev/null; then
		wait "$PID" || true
		cat "$LAUNCH_LOG"
		exit 1
	fi
	sleep 1
done

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo "DMG: $DMG_PATH"
echo "Version: $VERSION"
echo "Architectures: $ARCHITECTURES"
shasum -a 256 "$DMG_PATH"
