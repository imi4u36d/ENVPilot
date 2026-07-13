#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${1:-release}"
MODULE_CACHE_ROOT="${TMPDIR:-/tmp}/envpilot-swiftpm-cache"

APP_NAME="ENVPilot"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
DMG_STAGE_DIR="$ROOT_DIR/dist/${APP_NAME}-dmg"
DMG_PATH="$ROOT_DIR/dist/${APP_NAME}.dmg"
BIN_DIR="$ROOT_DIR/.build/${BUILD_CONFIG}"
APP_BIN="$BIN_DIR/ENVPilotApp"
HELPER_BIN="$BIN_DIR/envpilot-helper"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"

echo "Building ENVPilot ($BUILD_CONFIG)..."
cd "$ROOT_DIR"
mkdir -p "$MODULE_CACHE_ROOT"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_ROOT/swiftpm"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_ROOT/clang"
swift build -c "$BUILD_CONFIG" --product ENVPilotApp
swift build -c "$BUILD_CONFIG" --product envpilot-helper

if [[ ! -x "$APP_BIN" ]]; then
  echo "Missing app binary: $APP_BIN" >&2
  exit 1
fi

if [[ ! -x "$HELPER_BIN" ]]; then
  echo "Missing helper binary: $HELPER_BIN" >&2
  exit 1
fi

if [[ ! -f "$APP_ICON" ]]; then
  echo "Missing app icon: $APP_ICON" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"

cp "$APP_BIN" "$APP_BUNDLE/Contents/MacOS/ENVPilotApp"
cp "$HELPER_BIN" "$APP_BUNDLE/Contents/Resources/bin/envpilot-helper"
cp "$APP_ICON" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
chmod +x "$APP_BUNDLE/Contents/MacOS/ENVPilotApp"
chmod +x "$APP_BUNDLE/Contents/Resources/bin/envpilot-helper"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ENVPilotApp</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.envpilot.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ENVPilot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.5.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_BUNDLE/Contents/Resources/bin/envpilot-helper"
codesign --force --sign - "$APP_BUNDLE"

rm -rf "$DMG_STAGE_DIR"
mkdir -p "$DMG_STAGE_DIR"
cp -R "$APP_BUNDLE" "$DMG_STAGE_DIR/${APP_NAME}.app"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Packaged app:"
echo "  $APP_BUNDLE"
echo "Packaged dmg:"
echo "  $DMG_PATH"
