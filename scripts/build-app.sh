#!/bin/sh
# Builds the menu bar app and wraps it in build/1more-mac.app.
#
#   scripts/build-app.sh                       # release build, ad-hoc signed
#   SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh
#
# Ad-hoc signing gives every build a new code identity, so macOS may ask for Bluetooth permission
# again after a rebuild. Signing with a stable identity avoids that.
set -eu

cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-release}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
APP=build/1more-mac.app

swift build -c "$CONFIG" --product OneMoreMac
BIN="$(swift build -c "$CONFIG" --show-bin-path)/OneMoreMac"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OneMoreMac"
cp Support/OneMoreMac/Info.plist "$APP/Contents/Info.plist"
# The Icon Composer icon (from scripts/make-icon.swift) compiles to Assets.car, which macOS 26 and
# later draw from, and AppIcon.icns for earlier versions. actool comes with Xcode.
xcrun actool Support/OneMoreMac/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist "build/AppIcon-partial.plist" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP"
