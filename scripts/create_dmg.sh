#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE_ROOT="${TMPDIR:-/tmp}/envpilot-swiftpm-cache"

APP_NAME="ENVPilot"
BUILD_CONFIG="release"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
DMG_STAGE_DIR="$ROOT_DIR/dist/${APP_NAME}-dmg"
DMG_PATH="$ROOT_DIR/dist/${APP_NAME}.dmg"
BIN_DIR="$ROOT_DIR/.build/${BUILD_CONFIG}"
APP_BIN="$BIN_DIR/ENVPilotApp"
HELPER_BIN="$BIN_DIR/envpilot-helper"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
APP_RESOURCE_BUNDLE="$BIN_DIR/ENVPilot_ENVPilotApp.bundle"

echo "Building ENVPilot..."
cd "$ROOT_DIR"
mkdir -p "$MODULE_CACHE_ROOT"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_ROOT/swiftpm"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_ROOT/clang"
swift build -c "$BUILD_CONFIG" --product ENVPilotApp
swift build -c "$BUILD_CONFIG" --product envpilot-helper

for file in "$APP_BIN" "$HELPER_BIN" "$APP_ICON" "$APP_RESOURCE_BUNDLE"; do
  if [[ ! -e "$file" ]]; then
    echo "Missing build input: $file" >&2
    exit 1
  fi
done

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/bin"

cp "$APP_BIN" "$APP_BUNDLE/Contents/MacOS/ENVPilotApp"
cp "$HELPER_BIN" "$APP_BUNDLE/Contents/Resources/bin/envpilot-helper"
cp "$APP_ICON" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp -R "$APP_RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/ENVPilot_ENVPilotApp.bundle"
cp -R "$ROOT_DIR/Resources/zh-Hans.lproj" "$APP_BUNDLE/Contents/Resources/zh-Hans.lproj"

chmod +x "$APP_BUNDLE/Contents/MacOS/ENVPilotApp"
chmod +x "$APP_BUNDLE/Contents/Resources/bin/envpilot-helper"

APP_VERSION="${APP_VERSION:-0.6.7}"
APP_BUILD="${APP_BUILD:-9}"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>ENVPilotApp</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.envpilot.app</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>zh_CN</string>
    <string>en</string>
  </array>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ENVPilot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/^ *[0-9]*) [A-F0-9]* "\([^"]*\)".*$/\1/p' | head -1)}"
if [[ "$SIGN_IDENTITY" == "adhoc" || -z "$SIGN_IDENTITY" ]]; then
  SIGNER="-"
  TIMESTAMP_FLAG=()
else
  SIGNER="$SIGN_IDENTITY"
  TIMESTAMP_FLAG=(--timestamp)
fi

echo "Signing with: ${SIGNER}"
codesign --force --sign "$SIGNER" ${TIMESTAMP_FLAG[@]} "$APP_BUNDLE/Contents/Resources/bin/envpilot-helper"
codesign --force --sign "$SIGNER" ${TIMESTAMP_FLAG[@]} "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

rm -rf "$DMG_STAGE_DIR"
mkdir -p "$DMG_STAGE_DIR"
cp -R "$APP_BUNDLE" "$DMG_STAGE_DIR/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "Created:"
echo "  $DMG_PATH"
echo "  $DMG_PATH.sha256"
