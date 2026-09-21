#!/usr/bin/env bash
# 折叠动画的测量工具。两件事分清楚：
#
#   * 「卡顿」——单击一次动画里主线程有没有被占住；
#   * 「跳一下」——动画没跑完就再点一次时，AppKit 会把侧边栏一步弹到目标宽度。
#     复现它只要把间隔压到动画时长（~240ms）以内。
#
#   scripts/probe.sh auto [次数] [间隔ms] [页面]
#       全自动：探针自己往标题栏那个按钮投鼠标事件，不需要人去点。跑完打印
#       收起/展开各自的卡顿次数、各栏几何、body 求值次数、被 guard 吞掉的点击。
#         平稳场景：scripts/probe.sh auto 16 700
#         复现「跳」：scripts/probe.sh auto 8 120
#
#   scripts/probe.sh eyeball [sidebar|detail|both]
#       把某一栏换成空壳后启动（窗口结构、折叠动画、那个按钮本身都不变，还是手点）。
#       先原样点几次记住手感，再换空壳点几次：哪一种不卡了，卡顿就跟着哪一栏来。
#
#   scripts/probe.sh sample [秒]
#       启动并记录主线程占用。前 5 秒请什么都别做（当作基线），
#       提示之后再反复点折叠按钮（一秒一次）。结束打印各阶段卡顿次数和主线程热点栈。
#
# 需要已构建的可执行文件：
#   swift build --disable-sandbox --cache-path .build/spm-cache --scratch-path .build
#
# 更多开关见 Sources/NodePilotApp/Probe.swift 顶部注释
# （ENVPILOT_PERF_TRIGGER / SECTION / SIZE / SIMPLE / TRACE 等）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN="${ENVPILOT_BIN:-.build/debug/ENVPilotApp}"
OUT=".build/probe"
mkdir -p "$OUT"

if [[ ! -x "$BIN" ]]; then
  echo "找不到 $BIN，先构建：" >&2
  echo "  swift build --disable-sandbox --cache-path .build/spm-cache --scratch-path .build" >&2
  exit 1
fi

case "${1:-}" in
  ""|eyeball)
    KNOB="${2:-}"
    if [[ -n "$KNOB" ]]; then
      echo "把 $KNOB 那一栏换成空壳（用完按 Cmd+Q 退出）"
      exec env ENVPILOT_SIMPLE="$KNOB" "$BIN"
    else
      echo "原样启动（用完按 Cmd+Q 退出）"
      exec "$BIN"
    fi
    ;;

  auto)
    FLIPS="${2:-16}"
    GAP="${3:-700}"
    SECTION="${4:-}"
    LOG="$OUT/auto.log"
    rm -f "$LOG"
    echo "自动点击折叠按钮：${FLIPS} 次、间隔 ${GAP}ms${SECTION:+、页面 $SECTION}（点折叠按钮不影响鼠标，可以照常干活）"
    env ENVPILOT_PERF_PROBE=1 \
        ENVPILOT_PERF_TRIGGER=click \
        ENVPILOT_PERF_FLIPS="$FLIPS" \
        ENVPILOT_PERF_GAP="$GAP" \
        ${SECTION:+ENVPILOT_PERF_SECTION="$SECTION"} \
        "$BIN" >"$LOG" 2>&1 || true

    echo
    echo "=== 卡顿（收起 / 展开分开看；>20ms 才计数）==="
    grep -E "^\[(收起|展开|别动|点击|idle)" "$LOG" || true
    echo
    grep -E "collapse 期间|结束时各栏|body 求值|flatten 次数" "$LOG" || true
    echo
    echo "完整日志：$LOG"
    ;;

  sample)
    SECONDS_COUNT="${2:-16}"
    LOG="$OUT/manual.log"
    SAMPLE="$OUT/manual-sample.txt"
    rm -f "$SAMPLE"

    echo "启动 app…"
    env ENVPILOT_PERF_PROBE=1 ENVPILOT_PERF_MANUAL=1 "$BIN" >"$LOG" 2>&1 &
    APP_PID=$!
    sleep 3
    if ! kill -0 "$APP_PID" 2>/dev/null; then
      echo "app 没起来，日志：" >&2
      cat "$LOG" >&2
      exit 1
    fi

    echo
    echo ">>> 前 5 秒别动鼠标；之后请反复点红绿灯右边的折叠按钮（一秒一次），共 ${SECONDS_COUNT} 秒"
    sample "$APP_PID" "$SECONDS_COUNT" -f "$SAMPLE" >/dev/null 2>&1 ||
      echo "sample 没跑成（可能要授权），只统计主线程占用。" >&2
    wait "$APP_PID" 2>/dev/null || true

    echo
    echo "=== 主线程卡顿（>20ms 才计数；「别动」那行是基线，用来排除后台刷新的干扰）==="
    grep -E "^\[" "$LOG" || echo "（没有采集到数据，看 $LOG）"
    if [[ -s "$SAMPLE" ]]; then
      echo
      echo "=== 这段时间主线程在干什么（前 25 条，含空闲等待）==="
      sed -n '/Sort by top of stack/,/^$/p' "$SAMPLE" | head -27
      echo
      echo "完整调用树：$SAMPLE"
    fi
    ;;

  *)
    echo "用法：scripts/probe.sh [auto|eyeball|sample] [参数]" >&2
    exit 2
    ;;
esac
