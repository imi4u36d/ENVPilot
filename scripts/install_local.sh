#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_TARGET_DIR="${HOME}/Applications"
APP_BUNDLE="${ROOT_DIR}/dist/ENVPilot.app"
LOCAL_BIN_DIR="${HOME}/.local/bin"
HELPER_DEST="${LOCAL_BIN_DIR}/envpilot-helper"
EP_DEST="${LOCAL_BIN_DIR}/ep"

"$ROOT_DIR/scripts/package_app.sh" release

mkdir -p "$APP_TARGET_DIR"
rm -rf "${APP_TARGET_DIR}/ENVPilot.app"
cp -R "$APP_BUNDLE" "${APP_TARGET_DIR}/ENVPilot.app"

mkdir -p "$LOCAL_BIN_DIR"
cp "${ROOT_DIR}/.build/release/envpilot-helper" "$HELPER_DEST"
chmod +x "$HELPER_DEST"
ln -sf "$HELPER_DEST" "$EP_DEST"

"$ROOT_DIR/scripts/install_zsh_integration.sh" debug "$HELPER_DEST"

echo ""
echo "ENVPilot installed:"
echo "  App: ${APP_TARGET_DIR}/ENVPilot.app"
echo "  Helper: ${HELPER_DEST}"
echo "  CLI: ${EP_DEST}"
echo ""
echo "Open app:"
echo "  open \"${APP_TARGET_DIR}/ENVPilot.app\""
