#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${1:-debug}"
HELPER_PATH_OVERRIDE="${2:-}"
ZSHRC_PATH="${3:-${HOME}/.zshrc}"

HELPER_BIN="$ROOT_DIR/.build/${BUILD_CONFIG}/envpilot-helper"
if [[ -n "$HELPER_PATH_OVERRIDE" ]]; then
  HELPER_BIN="$HELPER_PATH_OVERRIDE"
fi

if [[ ! -x "$HELPER_BIN" ]]; then
  echo "Helper not found, building helper in $BUILD_CONFIG mode..."
  cd "$ROOT_DIR"
  swift build -c "$BUILD_CONFIG" --product envpilot-helper
fi

if [[ ! -x "$HELPER_BIN" ]]; then
  echo "Cannot find helper executable: $HELPER_BIN" >&2
  exit 1
fi

SNIPPET="$("$HELPER_BIN" install-snippet --helper-path "$HELPER_BIN")"

BEGIN_MARKER="# >>> ENVPilot >>>"
END_MARKER="# <<< ENVPilot <<<"
OLD_BEGIN_MARKER="# >>> NodePilot >>>"
OLD_END_MARKER="# <<< NodePilot <<<"

mkdir -p "$(dirname "$ZSHRC_PATH")"
touch "$ZSHRC_PATH"

TMP_FILE="$(mktemp)"
awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v old_begin="$OLD_BEGIN_MARKER" -v old_end="$OLD_END_MARKER" '
  $0 == begin || $0 == old_begin { skip = 1; next }
  $0 == end || $0 == old_end { skip = 0; next }
  !skip { print }
' "$ZSHRC_PATH" > "$TMP_FILE"

{
  cat "$TMP_FILE"
  echo ""
  echo "$SNIPPET"
} > "$ZSHRC_PATH"

rm -f "$TMP_FILE"

echo "Installed ENVPilot zsh integration into:"
echo "  $ZSHRC_PATH"
echo ""
echo "Please restart terminal or run:"
echo "  source \"$ZSHRC_PATH\""
