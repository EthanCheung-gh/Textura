# parity 工具

## 文件

| 文件 | 说明 |
|---|---|
| `workspace.json` | 固定 `updatedAt=2026-03-16T02:00:00.000Z` 的 Web seed；30 items / 3 areas |
| `ref/<route>-<theme>.png` | Web oracle，1440×900，DPR=1，字体 Noto Sans CJK SC |
| `ref/capture-report.json` | 锚点、字体、viewport、workspace sha256 |
| `out/<route>-<theme>.png` | CUI parity 输出（生成物，gitignored） |
| `out/diffs/<name>-side.png` | 左参考、右 CUI |
| `out/diffs/<name>-diff.png` | 暗化参考 + 红色差异放大 |
| `capture_ref.mjs` | CDP 冻结时钟、导出 workspace、截 7 路由 light/dark |
| `diff.py` | 像素/ΔRGB/分块 SSIM；超差非 0 退出 |

## 重新生成参考图

```bash
cd /home/ethan/CodeRepo/sandbox/Textura
npm run build
npx vite preview --port 1430 --strictPort &
node cangjie/tools/parity/capture_ref.mjs
```

固定日期来自 `TEXTURA_PARITY_TODAY`（默认 `2026-03-16`，时区 `+08:00`）。改日期会改 workspace 中所有相对日期，必须同时重跑 CUI 输出。

## 生成 CUI 输出

```bash
cd cangjie
./scripts/build.sh
./scripts/parity.sh
```

## 比对

```bash
python3 tools/parity/diff.py \
  tools/parity/ref/dashboard-light.png \
  tools/parity/out/dashboard-light.png \
  --report-dir tools/parity/out/diffs
```

容差：结构 ≤1px、1px 高斯模糊后 SSIM≥0.95、`ΔRGB<=32` 像素 ≥95%（三段判据见 `docs/PARITY.md §2.1`）。
可用 `--max-delta` 临时覆盖；正式验收不得为通过而放宽阈值。验收门是 `metrics.py`，`diff.py` 负责出图定位。

## 注意

- `out/` 与 `*.bmp` 被 `.gitignore` 忽略；参考图与 workspace 必须提交。
- CUI 快照 PNG 未压缩（约 3.7 MiB/张），这是为了字节级确定性。
- 7 条路由 × light/dark 的实测数字、确定性哈希与残差定位见 `docs/PARITY-RESULTS.md`。
