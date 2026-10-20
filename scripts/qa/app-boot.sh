#!/usr/bin/env bash
# 真实 Tauri 应用启动期数据保护验证（隔离 HOME + Xvfb + 截图断言）。
#
# 用法：bash scripts/qa/app-boot.sh <label> [workspace.json 源文件]
#
# 可选环境变量：
#   BOOT_WAIT=7                 启动后等待秒数（默认 7）
#   EXPECT_STDERR_REGEX=""      stderr 必须匹配的内容（为空则不检查）
#   EXPECT_COPY=""              期望在数据目录出现的副本文件名（并与主文件逐字节一致）
#   EXPECT_NO_AUTOSAVE=0        1 = 断言没有 .bak / backups（即没有自动保存）
#   EXPECT_ITEMS=""             期望主文件 items 数量
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${TEXTURA_APP_BIN:-$ROOT/src-tauri/target/release/textura}"
LABEL="${1:?用法: app-boot.sh <label> [workspace.json]}"
SRC="${2:-}"
WAIT="${BOOT_WAIT:-7}"

BASE="/tmp/textura-boot-$LABEL"
HOME_DIR="$BASE/home"
SHOT="$BASE/screen.png"
OUT="$BASE/stdout.log"
ERR="$BASE/stderr.log"
DATA_DIR="$HOME_DIR/.local/share/app.textura.desktop"
WS="$DATA_DIR/workspace.json"

for command in xvfb-run import identify node; do
  command -v "$command" >/dev/null 2>&1 || { echo "缺少依赖：$command" >&2; exit 2; }
done
[[ -x "$APP" ]] || { echo "未找到应用二进制：$APP（先 npm run tauri build -- --bundles deb）" >&2; exit 2; }

if [[ "${BOOT_KEEP:-0}" != "1" ]]; then
  rm -rf "$BASE"
fi
mkdir -p "$DATA_DIR"
if [[ -n "$SRC" ]]; then
  cp "$SRC" "$WS"
fi

HASH_BEFORE="$(sha256sum "$WS" 2>/dev/null | cut -d' ' -f1 || echo none)"

echo "==> [$LABEL] 启动真实窗口（HOME=$HOME_DIR）"
set +e
HOME="$HOME_DIR" \
XDG_DATA_HOME="$HOME_DIR/.local/share" \
XDG_CONFIG_HOME="$HOME_DIR/.config" \
XDG_CACHE_HOME="$HOME_DIR/.cache" \
GDK_BACKEND=x11 NO_AT_BRIDGE=1 LIBGL_ALWAYS_SOFTWARE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 \
TEXTURA_BOOT_APP="$APP" TEXTURA_BOOT_OUT="$OUT" TEXTURA_BOOT_ERR="$ERR" \
TEXTURA_BOOT_SHOT="$SHOT" TEXTURA_BOOT_WAIT="$WAIT" \
xvfb-run -a --server-args="-screen 0 1440x900x24" bash -s <<'INNER'
set -uo pipefail
"$TEXTURA_BOOT_APP" >"$TEXTURA_BOOT_OUT" 2>"$TEXTURA_BOOT_ERR" &
PID=$!
sleep "$TEXTURA_BOOT_WAIT"
if ! kill -0 "$PID" 2>/dev/null; then
  echo "APP_EXITED_EARLY=1"
else
  echo "APP_ALIVE_AT_SHOT=1"
  import -window root "$TEXTURA_BOOT_SHOT"
fi
kill -TERM "$PID" 2>/dev/null || true
for _ in $(seq 1 20); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
kill -KILL "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
INNER
INNER_STATUS=$?
set -e

HASH_AFTER="$(sha256sum "$WS" 2>/dev/null | cut -d' ' -f1 || echo none)"
echo
echo "==> [$LABEL] 结果"
echo "INNER_STATUS=$INNER_STATUS"
echo "WS_HASH_BEFORE=$HASH_BEFORE"
echo "WS_HASH_AFTER=$HASH_AFTER"
if [[ "$HASH_BEFORE" == "$HASH_AFTER" ]]; then echo "WS_UNCHANGED=1"; else echo "WS_UNCHANGED=0"; fi
if [[ -f "$SHOT" ]]; then
  read -r WIDTH HEIGHT DEVIATION COLORS < <(identify -format '%w %h %[fx:standard_deviation] %k\n' "$SHOT")
  echo "SHOT=${WIDTH}x${HEIGHT} stddev=$DEVIATION colors=$COLORS"
else
  echo "SHOT=missing"
fi
echo "DATA_DIR_FILES:"
find "$DATA_DIR" -maxdepth 2 -type f -printf '  %f\n' | sort
echo "STDERR_LINES=$(wc -l <"$ERR" 2>/dev/null || echo 0)"
if [[ -s "$ERR" ]]; then sed -n '1,12p' "$ERR" | sed 's/^/  | /'; fi

FAIL=0
if [[ ! -f "$SHOT" ]]; then
  echo "FAIL: 没有截图（应用可能未启动）"; FAIL=1
else
  (( WIDTH >= 1000 && HEIGHT >= 700 )) || { echo "FAIL: 截图尺寸异常 ${WIDTH}x${HEIGHT}"; FAIL=1; }
  awk -v d="$DEVIATION" 'BEGIN { exit !(d > 0.02) }' || { echo "FAIL: 截图疑似空白 stddev=$DEVIATION"; FAIL=1; }
fi
if [[ -n "${EXPECT_STDERR_REGEX:-}" ]]; then
  if grep -Eq "$EXPECT_STDERR_REGEX" "$ERR"; then
    echo "OK: stderr 命中 /$EXPECT_STDERR_REGEX/"
  else
    echo "FAIL: stderr 未命中 /$EXPECT_STDERR_REGEX/"; FAIL=1
  fi
fi
if [[ -n "${EXPECT_COPY:-}" ]]; then
  if [[ -f "$DATA_DIR/$EXPECT_COPY" ]]; then
    echo "OK: 存在副本 $EXPECT_COPY"
    if cmp -s "$DATA_DIR/$EXPECT_COPY" "$WS"; then echo "OK: 副本与主文件内容一致"; else echo "FAIL: 副本内容与主文件不一致"; FAIL=1; fi
  else
    echo "FAIL: 缺少副本 $EXPECT_COPY"; FAIL=1
  fi
fi
if [[ "${EXPECT_NO_AUTOSAVE:-0}" == "1" ]]; then
  BACKUP_JSON="$(find "$DATA_DIR/backups" -maxdepth 1 -name '*.json' -print -quit 2>/dev/null || true)"
  if [[ -f "$WS.bak" || -n "$BACKUP_JSON" ]]; then
    echo "FAIL: 出现了自动保存落盘（.bak=${WS}.bak / backups=${BACKUP_JSON}）"; FAIL=1
  else
    echo "OK: 没有自动保存落盘（no .bak / backups 为空）"
  fi
fi
if [[ -n "${EXPECT_ITEMS:-}" ]]; then
  COUNT="$(node -e 'const fs=require("fs");try{const w=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(String(w.items?.length ?? -1));}catch(e){process.stdout.write("error");}' "$WS" 2>/dev/null || echo error)"
  if [[ "$COUNT" == "$EXPECT_ITEMS" ]]; then
    echo "OK: 主文件 items=$COUNT"
  else
    echo "FAIL: 主文件 items=$COUNT（期望 $EXPECT_ITEMS）"; FAIL=1
  fi
fi

if [[ "$FAIL" -eq 0 ]]; then echo "BOOT_SMOKE_PASS=1"; else echo "BOOT_SMOKE_PASS=0"; fi
exit "$FAIL"
