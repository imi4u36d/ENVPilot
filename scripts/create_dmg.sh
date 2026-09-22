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

# 这里不再复制 SwiftPM 的 `<包名>_<target>.bundle`：Package.swift 已经不声明 `resources:`，
# 代码也从 `Bundle.module` 改成了 `Bundle.main`。原因见 Package.swift 里的注释——
# Bundle.module 的「资源包该放哪」在不同构建工具下不一致，1.0.0 因此启动即崩溃。

echo "Building ENVPilot..."
cd "$ROOT_DIR"
mkdir -p "$MODULE_CACHE_ROOT"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_ROOT/swiftpm"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_ROOT/clang"
swift build -c "$BUILD_CONFIG" --product ENVPilotApp
swift build -c "$BUILD_CONFIG" --product envpilot-helper

for file in "$APP_BIN" "$HELPER_BIN" "$APP_ICON"; do
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
cp -R "$ROOT_DIR/Resources/zh-Hans.lproj" "$APP_BUNDLE/Contents/Resources/zh-Hans.lproj"

chmod +x "$APP_BUNDLE/Contents/MacOS/ENVPilotApp"
chmod +x "$APP_BUNDLE/Contents/Resources/bin/envpilot-helper"

APP_VERSION="${APP_VERSION:-1.0.1}"
APP_BUILD="${APP_BUILD:-11}"

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

# 启动冒烟测试：直接跑 .app 里的可执行文件，等价于用户双击。
#
# 1.0.0 装了打不开就是这里没拦住的：DMG 打得好好的、签名也过、`codesign --verify` 也绿，
# 但应用一渲染侧边栏就因为 `Bundle.module` 找不到资源包 SIGTRAP 崩溃。签名与结构检查
# 都看不出这种问题，只有真的把它启动一次才知道。不需要时设 SKIP_SMOKE_TEST=1 跳过。
if [[ "${SKIP_SMOKE_TEST:-0}" != "1" ]]; then
  echo "Smoke test: launching the packaged app..."
  SMOKE_LOG="$(mktemp -t envpilot-smoke)"
  "$APP_BUNDLE/Contents/MacOS/${APP_NAME}App" >"$SMOKE_LOG" 2>&1 &
  SMOKE_PID=$!
  SMOKE_DIED=0
  for _ in {1..16}; do
    sleep 0.5
    if ! kill -0 "$SMOKE_PID" 2>/dev/null; then
      SMOKE_DIED=1
      break
    fi
  done
  if [[ "$SMOKE_DIED" == "1" ]]; then
    wait "$SMOKE_PID" 2>/dev/null || true
    if grep -qE "Fatal error|fatal error|unable to find|could not load|SIGTRAP|Trace/BPT" "$SMOKE_LOG"; then
      echo "Smoke test FAILED: 应用启动即崩溃，DMG 不生成。" >&2
      cat "$SMOKE_LOG" >&2
      rm -f "$SMOKE_LOG"
      exit 1
    fi
    # 没有致命错误却立刻退出：更可能是这个环境起不了 GUI（比如无窗口会话的 CI），
    # 记为警告而不是失败，免得把发布管线卡在环境问题上。要严格失败就设 STRICT_SMOKE_TEST=1。
    echo "Smoke test WARNING: 应用提前退出但没有致命错误输出（可能是当前环境无 GUI 会话）。" >&2
    cat "$SMOKE_LOG" >&2
    rm -f "$SMOKE_LOG"
    if [[ "${STRICT_SMOKE_TEST:-0}" == "1" ]]; then
      exit 1
    fi
  else
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
    rm -f "$SMOKE_LOG"
    echo "Smoke test passed: 应用启动后持续存活。"
  fi
fi

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
