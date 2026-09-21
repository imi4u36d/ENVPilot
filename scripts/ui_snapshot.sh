#!/usr/bin/env bash
# 渲染主窗口各页面的离屏快照，用于设计评审与回归比对。
#
#   scripts/ui_snapshot.sh artifacts/ui-before
#   scripts/ui_snapshot.sh artifacts/ui-after dark
#
# 依赖已构建的 .build/debug/ENVPilotApp；不会请求任何系统权限。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${1:-artifacts/ui}"
SCHEME="${2:-light}"
BIN="${ENVPILOT_BIN:-.build/debug/ENVPilotApp}"
SIZE="${ENVPILOT_SIZE:-1240x820}"

if [[ ! -x "$BIN" ]]; then
  echo "找不到可执行文件 $BIN，请先运行：" >&2
  echo "  swift build --disable-sandbox --cache-path .build/spm-cache --scratch-path .build" >&2
  exit 1
fi

mkdir -p "$OUT"

for section in overview runtimes; do
  ENVPILOT_WINDOW_SNAPSHOT="$OUT/$section-$SCHEME.png" \
  ENVPILOT_WINDOW_SNAPSHOT_SECTION="$section" \
  ENVPILOT_WINDOW_SNAPSHOT_SCHEME="$SCHEME" \
  ENVPILOT_WINDOW_SNAPSHOT_SIZE="$SIZE" \
    "$BIN" >/dev/null
done

# 菜单栏面板有独立的快照通道（它不在窗口系统里）。
ENVPILOT_MENUBAR_SNAPSHOT="$OUT/menubar-$SCHEME.png" "$BIN" >/dev/null

echo "快照已写入 $OUT"
