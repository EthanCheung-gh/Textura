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
| `metrics.py` | 原始层 + 1px 高斯层 + 结构层指标（`gate.py` 的度量来源） |
| `gate.py` | 三层验收门：判据、表格、JSON、退出码 |
| `diff.py` | 出图定位（side-by-side / 热力图）；判定不用它 |

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
./scripts/parity.sh --theme both              # 7 路由 × light/dark = 14 张
./scripts/parity.sh --theme dark --route settings
./scripts/parity.sh --route dashboard,gantt --theme light
```

也支持环境变量：`TEXTURA_PARITY_THEMES="light dark"`、`TEXTURA_PARITY_ROUTES="dashboard gantt"`。
输出固定为 `tools/parity/out/<route>-<theme>.png`。

`settings` 视图的「工作区文件 / 数据目录」行把 `--workspace` 路径单行显示、超长时中间省略
（commit `a0c7a81` 起；悬停可看全文），因此 14 张截图不再依赖构建目录的路径长度：仓库内
72 字符路径与 28 字符短路径给出同一套版式（`docs/SETTINGS-VIEW.md §2`）。

## 验收门（三层，退出码 0 才算过）

```bash
cd cangjie

./scripts/diff.sh                                  # 默认：ref/ vs out/，双主题、7 路由
./scripts/diff.sh --theme light                    # 只比 light
./scripts/diff.sh --route settings --theme dark    # 单条路由
./scripts/diff.sh --route dashboard,gantt          # 多条路由
./scripts/diff.sh --ref path/ref --out path/out --json ~/.cache/gate.json
```

默认约定：参考目录 `tools/parity/ref`、候选目录 `tools/parity/out`、JSON 报告写入
`tools/parity/out/gate-report.json`。也可以用位置参数直接比两张图：
`python3 tools/parity/gate.py ref/a.png out/a.png`。

判据（`docs/PARITY.md §2.1`，三档全部是硬门槛）：

| 档位 | 表头字段 | 判据 |
|---|---|---|
| 结构 | `ruleΔpx`（≥300px 长直线配准最大偏差） | ≤ 1.5px |
| 结构 | `shift`（全局最佳整像素平移） | 必须是 `(0,0)` |
| 结构 | `edge ref%` / `edge out%`（双向 1px 边缘覆盖） | 两者都 ≥ 90% |
| 视觉 | `blurSSIM`（σ=1.0 高斯模糊后 SSIM） | ≥ 0.95 |
| 原始 | `raw≤32%`（`ΔRGB ≤ 32` 的像素占比） | ≥ 95% |

表格其余列：`pair` = `<route>-<theme>`，`diff%` = 任一通道变化的像素占比，
`meanΔ` = 逐像素 `max(|ΔR|,|ΔG|,|ΔB|)` 的均值。`verdict` 为 `PASS` 时三档全过；
`FAIL` 行会在表格下方打印每个失败档位的具体原因。

JSON 报告字段（默认 `tools/parity/out/gate-report.json`）：

| 字段 | 含义 |
|---|---|
| `tool` / `protocol` | 门禁实现路径与协议章节 |
| `reference` / `candidate` | 本次比较的两侧路径 |
| `selectors.theme` / `selectors.routes` | 实际生效的过滤条件；`routes` 为空 = 全部 |
| `thresholds.structure` | `max_rule_delta_px`、`required_best_shift`、`min_edge_coverage` |
| `thresholds.visual` | `min_blur_ssim`、`blur_sigma` |
| `thresholds.raw` | `max_delta_rgb`、`min_within_tolerance_ratio` |
| `results[].raw` | `different_ratio`、`mean_delta_rgb`、`max_delta_rgb`、`within_tolerance_ratio`、原始 `ssim`（仅参考，不作判据） |
| `results[].blurred` | 同一组指标在 σ=1.0 模糊后；`ssim` 是视觉档判据 |
| `results[].structure` | `ref_covered_within_1px`、`out_covered_within_1px`、`best_exact_shift{dx,dy,exact_ratio}`、`zero_shift_exact_ratio`、`rules{...}`、边缘像素计数 |
| `results[].worst_blocks` | 按 mean ΔRGB 排序的 3 个 90×90 区块，用于把残差定位到控件 |
| `results[].gate.tiers` | 三档各自的 `passed` 与 `reasons` |
| `results[].gate.failed_tiers` / `gate.reasons` | 失败档位与合并后的原因 |
| `summary` | `total`、`passed`、`failed[]`、`verdict` |

退出码：

| 码 | 含义 |
|---:|---|
| `0` | 所选 pair 全部通过三档 |
| `1` | 至少一个 pair 违反任一档（表格与 JSON 仍会完整写出） |
| `2` | 用法错误：未知 `--route`/`--theme`、`ref`/`out` 不存在、没有匹配的 pair、尺寸不一致 |

## 出图定位（不是验收门）

```bash
python3 tools/parity/diff.py \
  tools/parity/ref/dashboard-light.png \
  tools/parity/out/dashboard-light.png \
  --report-dir tools/parity/out/diffs
```

`diff.py` 保持冻结的 CLI：默认仍按原始层 `ΔRGB≤32 ≥98%` + 原始 SSIM≥0.95 判 `PASS/FAIL`，
所以它对新协议下的合格图可能打印 FAIL。那只表示“原始层未达 98%”，**不是验收结论**；
验收结论只来自 `scripts/diff.sh` / `gate.py`。需要逐块定位时看 `worst_blocks` 或 `*-diff.png`。

## 注意

- `out/` 与 `*.bmp` 被 `.gitignore` 忽略；参考图与 workspace 必须提交。
- CUI 快照 PNG 未压缩（约 3.7 MiB/张），这是为了字节级确定性。
- 门禁只判像素与结构，不替代确定性检查：两次独立运行仍需 sha256 相同（同一 argv 拼写）。
- 7 条路由 × light/dark 的实测数字、确定性哈希与残差定位见 `docs/PARITY-RESULTS.md`。
