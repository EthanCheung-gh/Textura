#!/usr/bin/env bash
# Textura 端到端冒烟：真实 Tauri 窗口 + Xvfb + 截图 + 文件持久化断言。
#
# 前置：npm run build && npm run tauri build -- --bundles deb
# 运行：bash scripts/tauri-smoke.sh
#
# 可用环境变量：
#   TEXTURA_APP_BIN       默认 src-tauri/target/release/textura
#   TEXTURA_SMOKE_HOME    默认 /tmp/textura-smoke-home（隔离 HOME，保证首次播种）
#   TEXTURA_SMOKE_SHOT    默认 /tmp/textura-app.png
#   TEXTURA_SMOKE_WAIT    截图前等待秒数，默认 9
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="${TEXTURA_APP_BIN:-$ROOT/src-tauri/target/release/textura}"
SMOKE_HOME="${TEXTURA_SMOKE_HOME:-/tmp/textura-smoke-home}"
SHOT="${TEXTURA_SMOKE_SHOT:-/tmp/textura-app.png}"
STDOUT_LOG="${TEXTURA_SMOKE_STDOUT:-/tmp/textura-smoke-stdout.log}"
STDERR_LOG="${TEXTURA_SMOKE_STDERR:-/tmp/textura-smoke-stderr.log}"
WAIT_SECONDS="${TEXTURA_SMOKE_WAIT:-9}"
AUTOSAVE="${TEXTURA_SMOKE_AUTOSAVE:-1}"
WORKSPACE="$SMOKE_HOME/.local/share/app.textura.desktop/workspace.json"

for command in xvfb-run import identify node; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "缺少依赖命令：$command" >&2
    exit 2
  }
done
if [[ "$AUTOSAVE" == "1" ]]; then
  command -v python3 >/dev/null 2>&1 || {
    echo "自动保存冒烟需要 python3（用于 XTest 输入）" >&2
    exit 2
  }
fi
if [[ "$SMOKE_HOME" == "/" || "$SMOKE_HOME" == "$HOME" ]]; then
  echo "拒绝清理不安全的 SMOKE_HOME：$SMOKE_HOME" >&2
  exit 2
fi

if [[ ! -x "$APP_BIN" ]]; then
  echo "未找到可执行文件：$APP_BIN" >&2
  echo "请先运行：npm run build && npm run tauri build -- --bundles deb" >&2
  exit 2
fi

rm -rf "$SMOKE_HOME"
mkdir -p "$SMOKE_HOME"
: >"$STDOUT_LOG"
: >"$STDERR_LOG"

export TEXTURA_SMOKE_APP_BIN="$APP_BIN"
export TEXTURA_SMOKE_HOME_DIR="$SMOKE_HOME"
export TEXTURA_SMOKE_WORKSPACE="$WORKSPACE"
export TEXTURA_SMOKE_SHOT_PATH="$SHOT"
export TEXTURA_SMOKE_STDOUT_PATH="$STDOUT_LOG"
export TEXTURA_SMOKE_STDERR_PATH="$STDERR_LOG"
export TEXTURA_SMOKE_WAIT_SECONDS="$WAIT_SECONDS"
export TEXTURA_SMOKE_AUTOSAVE_ENABLED="$AUTOSAVE"

echo "==> 启动 Xvfb（1440x900x24）与 Tauri 应用"
echo "    HOME=$SMOKE_HOME"
echo "    workspace=$WORKSPACE"

set +e
XDG_DATA_HOME="$SMOKE_HOME/.local/share" \
HOME="$SMOKE_HOME" \
GDK_BACKEND=x11 \
NO_AT_BRIDGE=1 \
LIBGL_ALWAYS_SOFTWARE=1 \
WEBKIT_DISABLE_DMABUF_RENDERER=1 \
xvfb-run -a --server-args="-screen 0 1440x900x24" \
  bash -s <<'INNER'
set -euo pipefail
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$APP_PID" 2>/dev/null || break
      sleep 0.25
    done
    if kill -0 "$APP_PID" 2>/dev/null; then
      kill -KILL "$APP_PID" 2>/dev/null || true
    fi
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

"$TEXTURA_SMOKE_APP_BIN" \
  >"$TEXTURA_SMOKE_STDOUT_PATH" 2>"$TEXTURA_SMOKE_STDERR_PATH" &
APP_PID=$!

# 给 WebView 加载、fixtures 播种、IPC 原子写留出时间。
sleep "$TEXTURA_SMOKE_WAIT_SECONDS"

if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "应用在截图前已退出" >&2
  exit 1
fi

import -window root "$TEXTURA_SMOKE_SHOT_PATH"
identify "$TEXTURA_SMOKE_SHOT_PATH" >/dev/null

# 通过 XTest 触发一次真实写入（Ctrl+N 快速收集 + Enter），再用 Ctrl+Z 撤销。
# 最终 workspace 应回到 30 条，而 .bak 保留 31 条，证明防抖自动保存与原子写都经过 IPC。
if [[ "${TEXTURA_SMOKE_AUTOSAVE_ENABLED:-1}" == "1" ]]; then
  echo "==> 自动保存冒烟：Ctrl+N 创建 -> 等待保存 -> Ctrl+Z 撤销"
  python3 - <<'PY'
import ctypes
import time

x11 = ctypes.CDLL('libX11.so.6')
xtst = ctypes.CDLL('libXtst.so.6')
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XStringToKeysym.restype = ctypes.c_ulong
x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XKeysymToKeycode.restype = ctypes.c_uint
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]

display = x11.XOpenDisplay(None)
if not display:
    raise SystemExit('无法连接 Xvfb DISPLAY')
display = ctypes.c_void_p(display)

def flush():
    x11.XFlush(display)

def key(name, down):
    keysym = x11.XStringToKeysym(name.encode())
    keycode = x11.XKeysymToKeycode(display, ctypes.c_ulong(keysym))
    if not keycode:
        raise SystemExit(f'未知按键：{name}')
    xtst.XTestFakeKeyEvent(display, keycode, 1 if down else 0, 0)
    flush()

def tap(name):
    key(name, True)
    key(name, False)

def chord(*names):
    for name in names:
        key(name, True)
    for name in reversed(names):
        key(name, False)

def click(x, y):
    xtst.XTestFakeMotionEvent(display, -1, x, y, 0)
    flush()
    time.sleep(0.2)
    xtst.XTestFakeButtonEvent(display, 1, 1, 0)
    xtst.XTestFakeButtonEvent(display, 1, 0, 0)
    flush()

# 聚焦窗口空白区，避免事件落到 root。
click(900, 80)
chord('Control_L', 'n')
time.sleep(0.9)
for character in 'smoke':
    tap(character)
    time.sleep(0.05)
tap('Return')
time.sleep(2.2)

# 关闭弹窗后点击空白区恢复焦点，再撤销。
click(900, 80)
time.sleep(0.4)
chord('Control_L', 'z')
time.sleep(2.2)
PY
fi

cleanup
trap - EXIT
echo "应用已优雅结束"
INNER
INNER_STATUS=$?
set -e

if [[ "$INNER_STATUS" -ne 0 ]]; then
  echo "Xvfb/应用阶段失败（exit $INNER_STATUS）" >&2
  sed -n '1,80p' "$STDERR_LOG" >&2 || true
  exit "$INNER_STATUS"
fi

echo
echo "==> 断言截图"
identify -format '    截图：%f %wx%h\n' "$SHOT"
read -r WIDTH HEIGHT MEAN_DEVIATION < <(
  identify -format '%w %h %[fx:standard_deviation]\n' "$SHOT"
)
if [[ "$WIDTH" -lt 1000 || "$HEIGHT" -lt 700 ]]; then
  echo "截图尺寸异常：${WIDTH}x${HEIGHT}" >&2
  exit 1
fi
if ! awk -v deviation="$MEAN_DEVIATION" 'BEGIN { exit !(deviation > 0.02) }'; then
  echo "截图疑似空白（standard deviation=${MEAN_DEVIATION}）" >&2
  exit 1
fi
echo "    截图非空白（standard deviation=${MEAN_DEVIATION}）"

echo
echo "==> 断言 workspace.json"
if [[ ! -f "$WORKSPACE" ]]; then
  echo "缺少工作区文件：$WORKSPACE" >&2
  find "$SMOKE_HOME" -maxdepth 5 -type f -print >&2 || true
  exit 1
fi
node - "$WORKSPACE" <<'NODE'
const fs = require('node:fs');
const path = process.argv[2];
const workspace = JSON.parse(fs.readFileSync(path, 'utf8'));
const count = Array.isArray(workspace.items) ? workspace.items.length : -1;
console.log(`    路径：${path}`);
console.log(`    version=${workspace.version} items=${count} areas=${workspace.areas?.length ?? 0} runs=${workspace.runs?.length ?? 0}`);
if (count !== 30) {
  console.error(`期望 items=30，实际 ${count}`);
  process.exit(1);
}
if ((workspace.areas?.length ?? 0) !== 3) {
  console.error(`期望 areas=3，实际 ${workspace.areas?.length ?? 0}`);
  process.exit(1);
}
NODE

if [[ "$AUTOSAVE" == "1" ]]; then
  echo
  echo "==> 断言自动保存 / 撤销"
  if [[ ! -f "$WORKSPACE.bak" ]]; then
    echo "缺少 workspace.json.bak，自动保存未被验证" >&2
    exit 1
  fi
  node - "$WORKSPACE" "$WORKSPACE.bak" <<'NODE'
const fs = require('node:fs');
const [mainPath, bakPath] = process.argv.slice(2);
const main = JSON.parse(fs.readFileSync(mainPath, 'utf8'));
const bak = JSON.parse(fs.readFileSync(bakPath, 'utf8'));
const mainCount = main.items.length;
const bakCount = bak.items.length;
console.log(`    main items=${mainCount}（撤销后的最终状态）`);
console.log(`    .bak items=${bakCount}（自动保存的中间状态）`);
if (mainCount !== 30 || bakCount !== 31) {
  console.error(`期望 main=30 / .bak=31，实际 main=${mainCount} / .bak=${bakCount}`);
  process.exit(1);
}
NODE
  BACKUP_COUNT="$(find "$SMOKE_HOME/.local/share/app.textura.desktop/backups" -maxdepth 1 -name 'textura-*.json' | wc -l)"
  echo "    轮换备份：${BACKUP_COUNT} 份"
  if [[ "$BACKUP_COUNT" -lt 2 ]]; then
    echo "轮换备份不足（${BACKUP_COUNT}），原子写链路存疑" >&2
    exit 1
  fi
fi

echo
echo "==> 检查 stderr 中的 CSP / IPC 错误"
if grep -Eiq 'content security policy|csp violation|refused to (load|execute|connect|display)|ipc (error|failed|not allowed)|failed to invoke|ipc:.*refused' "$STDERR_LOG"; then
  echo "发现 CSP / IPC 相关错误：" >&2
  grep -Ein 'content security policy|csp violation|refused to (load|execute|connect|display)|ipc (error|failed|not allowed)|failed to invoke|ipc:.*refused' "$STDERR_LOG" >&2 || true
  exit 1
fi
echo "    未发现 CSP / IPC 错误"
if [[ -s "$STDERR_LOG" ]]; then
  echo "    stderr 摘要（末尾 8 行）："
  tail -n 8 "$STDERR_LOG" | sed 's/^/      /'
else
  echo "    stderr 为空"
fi

echo
echo "==> SMOKE PASS"
echo "    screenshot: $SHOT"
echo "    workspace:  $WORKSPACE"
echo "    stdout:     $STDOUT_LOG"
echo "    stderr:     $STDERR_LOG"
