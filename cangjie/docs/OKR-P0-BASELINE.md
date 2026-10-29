# OKR P0 基线：每帧计数器与实测数字

> P0 只做两件事：**加观测**（`src/views/okr/okr_metrics.cj`）与**记录基线**（本文件）。
> 不改渲染行为、不改像素、不改交互。方案与分阶段计划见 `docs/OKR-EDIT-PLAN.md`。
>
> 本文件里的每个数字都能用 §6 的命令在自己的机器上复现；不能复现的（真机 GC 数据）都标注了
> 「未重测」并给出出处。

---

## 1. 环境

| 项 | 值 |
|---|---|
| 分支 / HEAD | `feat/cangjie-rewrite` @ `1a9d77e`（`feat(okr): 卡片编辑按钮与独立目标编辑视图`，**该提交只动 Web 侧** `src/modules/okr/**`，`cangjie/` 未变） |
| 主机 | Linux `7.0.0-42-generic`，x86_64，16 核 |
| 工具链 | `cjc 1.2.0 (cjnative)`，`cjpm` `cjc-version = "1.2.0"`（`cjpm.toml`） |
| 运行环境 | `source scripts/env.sh`（`SDL_VIDEODRIVER=x11`、`unset WAYLAND_DISPLAY`、`TEXTURA_FONT=Noto Sans CJK SC`） |
| 设备 | **无**。`hdc list targets` → `[Empty]`（无线调试未连接）。因此本轮**没有**任何真机复测，真机数字全部引用 `docs/HANDOFF.md`（§5） |
| 工作树 | 15 个既有未提交改动（滚轮/选中修复、`tools/runtime-repro/`、`docs/{HANDOFF,STABILITY}.md` 等）**保持未提交**；P0 只新增/改动 §4 列出的文件 |

---

## 2. 数据与构造方式

| 项 | 说明 |
|---|---|
| 测试数据 | `createSeedWorkspace(FixedClock(1773626400000))`（`src/core/data/fixtures.cj:12` 的演示 workspace）：**1 个目标**（`obj_activation`）+ **3 个 KR** + 关联执行项，季度 `2026-Q1`，浅色主题，`density=detailed`，`view=cards` |
| 页面尺寸 | 窗口 1440×900，页面 `min(1080, 1152) = 1080` 宽（`.shell-content` 内容宽 1152 = 1440 − 240 侧栏 − 48 内边距；`.page.okr-page` 的 `max-width: 1080`） |
| parity 数据 | `tools/parity/workspace.json`：30 条 item（`objective=1`、`keyresult=3`、`project=1`、`action=13`、`step=7`、`reference=2`、`note=2`、`sop=1`），OKR 周期全部 `2026-Q1` —— 与演示数据同规模，所以 §3 的数字对 parity 截图同样有代表性 |
| 构造路径 | 与 shell 同一条：`VStack { OkrPage(viewCtx, okrUiState()) }`，由 `WidgetTestHost` 负责 build → measure → layout → draw（不手工调 `layout`，见 `src/views/okr/okr_metrics_test.cj`） |
| 帧的口径 | 1 次 `host.frame` = **3 次** `OkrPage.layout`（CUI 的「测—布—再布」）。`frames` 计数器数的是 `layout` 调用，**不是**窗口帧；§3 的表按「每次 layout」给值，并给出 ×3 的窗口帧值 |

---

## 3. 每帧计数

### 3.1 主表（演示数据，page 1080 宽，detailed，cards）

由 `okr_metrics_test.cj` 打印的一行（第二帧，`[okr-metrics] layouts=3 …`）：

```text
[okr-metrics] layouts=3 ops=302 hotspots=86 widgets=9 textMeasure=224 misses=0 ellipsize=25 candidates=0 stringBuilds=13 focusableIds=0 frameUs=940 firstFrameUs=1234
```

| 计数器 | 每次 `layout` | 每个窗口帧（×3） | 说明 |
|---|---|---|---|
| `ops` | **302** | 302（每帧重填，不叠加） | 绘制指令总数；跨帧复用后第二帧与第一帧**相等**（用例断言） |
| `hotspots` | **86** | 86 | 命中区 + 焦点 id 的一半（另一半是只画焦点环的 `rings`） |
| `widgets` | **9** | 9 | `BadgeView` / `ProgressView` 子控件（`cv.badge` / `cv.progress`） |
| `textMeasure`（`okrTextW` 调用） | **224** | 672 | 含两次高度预演的测宽点 |
| `textMeasureMisses`（未命中缓存） | **0** | 0 | 第二帧全命中：宽度记忆化（`c0bbeeb`）跨帧有效 |
| `ellipsize` | **25** | 75 | 1080 宽下没有一处真的需要截断 |
| `ellipsizeCandidates` | **0** | 0 | 与上一行同因；窄页见 §3.3 |
| `stringBuilds` | **13** | 39 | `format*` 类格式化调用（调用点见 §3.4） |
| `focusableIds` | **0** | 0 | 只在焦点遍历时被 CUI 调用；一次返回 46 个 id |
| 帧耗时 `frameUs` | — | **940µs**（首次 1234µs） | 主机 `WidgetTestHost` 一帧（build+measure+layout+draw）。**不是**真机口径，见 §5 |

### 3.2 指令分解（同一次 layout，302 条）

| 容器 | 条数 | 备注 |
|---|---|---|
| `texts` | **129** | 布局阶段生成；绘制时再按视口裁剪（`docs/HANDOFF.md` §4 的 169/帧 是**设备上画出去**的条数，口径不同） |
| `fills` | 55 | 卡片/按钮/分段/chip 底色 |
| `strokes` | 37 | 1px 边框 |
| `rings` | 47 | 焦点环，只在 `ctx.showFocusRing(id)` 为真时画 |
| `icons` | 13 | 24×24 描边图标 |
| `lines` | 7 | 分隔线 |
| `chevrons` | 6 | KR 上移/下移箭头 |
| `shadows` | 6 | 卡片/主按钮投影 |
| `dashes` | 1 | `.okr-add-kr` 虚线框 |
| `dots` | 1 | Area 圆点 |

### 3.3 窄页面（page 520 宽）——`ellipsize` 的真实成本

```text
[okr-metrics] narrow=520 layouts=6 ellipsize=160 candidates=1162 textMeasure=2714 stringBuilds=91
```

| 计数器 | 每次 `layout` |
|---|---|
| `ellipsize` | ≈ 26.7 |
| `ellipsizeCandidates` | **≈ 194**（每字一个 `String(runes[0..keep]) + "…"`） |
| `textMeasure` | ≈ 452 |

结论：宽窗口（1080）下 `ellipsize` 免费；**窄窗口/长标题**时它每帧要构造上百个候选串，
是 `docs/OKR-EDIT-PLAN.md` §3 第 4 行的实测依据。

### 3.4 `stringBuilds` 计的是哪些调用

| 调用点 | 位置 | 频率由什么决定 |
|---|---|---|
| `pad2`（KR 序号 `01/02/03`） | `okr_ops.cj:683`（实现在包内，直接计数） | KR 行数 |
| `jsNumberToString`（页头「时间已过 N%」、健康度「季度时间进度」） | `okr_page.cj:557`、`okr_page.cj:743` | 固定 2 次/布局 |
| `quarterLabel`（页头副标题、每个季度 chip） | `okr_page.cj:559`、`okr_page.cj:593` | 1 + 季度 chip 数 |
| `formatMetric`（KR 指标摘要、节奏提示） | `okr_cards.cj:346`、`okr_cards.cj:421` | 带指标的 KR 行数 |
| `formatNumber`（紧凑密度的「当前 / 目标」） | `okr_cards.cj:223` | 仅 `density=compact` 时 |
| `formatSchedule`（执行项排期） | `okr_cards.cj:476`、`okr_views.cj:326` | 关联执行项行数 |
| `quarterLabel2`（空态文案） | `okr_views.cj:461` | 仅空态 |

演示数据（detailed、3 个 KR）合计 **13 次/布局**；表/对齐视图（`okr_views.cj:122`、`okr_views.cj:289`）
另计，切到那两个视图时才发生。窄页（520）实测 ≈ **15 次/布局**——同一份数据下比 1080 宽多两次，
**未逐项归因**（计数器只给总量，不做 per-site 分解；要归因需要按点位加独立计数器）。

---

## 4. 命令与结果（本轮真实输出）

### 4.1 单测

```bash
cd cangjie && source scripts/env.sh
cjpm test
```

```text
Summary: TOTAL: 713
    PASSED: 713, SKIPPED: 0, ERROR: 0
    FAILED: 0
cjpm test success
```

- P0 之前：**710/710**（与本轮既有的 15 个未提交改动一致，见 `docs/HANDOFF.md` §4.1）。
- P0 之后：**713/713**（新增 `okrFrameCountersDoNotGrowAcrossLayouts`、
  `narrowPageReportsEllipsizeCandidates`、`resetZeroesEveryCounter`）。
- 只跑 OKR 包：`cjpm test --skip-build src/views/okr` → `PASSED: 45`（原 42 + 3），连跑 3 次结果一致。

### 4.2 像素门禁

```bash
./scripts/parity.sh --theme both
./scripts/diff.sh --theme both
```

`diff.sh` 的 OKR 两行与总结（完整 14 行见 `tools/parity/out/gate-report.json`）：

```text
okr-dark            10.07   3.33    96.58    0.9729      96.65      97.67      1.0   (0,0)  PASS
okr-light           10.04   3.86    96.38    0.9701      97.92      96.86      1.0   (0,0)  PASS

gate: 14/14 PASS (theme=both, routes=all) [structure: ruleΔ≤1.5px, shift=(0,0), edge≥90% | visual: blur SSIM≥0.95 | raw: ΔRGB≤32 ≥95%]
gate: verdict PASS (exit 0)
```

结论：**计数器没有改变像素**（14/14，逐字节口径的门禁与 P0 之前相同）。

两次独立运行逐像素一致（`AGENTS.md` §4 的第 2 条证据要求）：

```text
$ shasum -a 256 tools/parity/out/*.png | sort          # 跑两遍 parity.sh 后对比
IDENTICAL: 14/14 byte-identical across two independent runs
30d82a8e47b9bf15c7b0bf6e85d70390bb6077e98f4c4a3805c5824613bfc4d0  tools/parity/out/okr-dark.png
c7929df45c4b20eeebcfe05c573df2f5291ab275d84dba9c3fc11a711f0fae79  tools/parity/out/okr-light.png
```

### 4.3 观测开关（默认关闭）

```bash
TEXTURA_OKR_METRICS=1 cjpm test --skip-build src/views/okr
```

每 60 次 layout 打印一行，例如整包跑完后：

```text
[okr-metrics] frames=900 ops=302 hotspots=86 widgets=12 textMeasure=235872 misses=146 ellipsize=23763 candidates=0 stringBuilds=14066 focusableIds=0
```

- 缓存有效性（跨整个 OKR 用例集）：235 872 次测宽只有 **146** 次真正测量（0.06%）。
- 不设这个变量时**一次都不打印**；parity 门禁不设它，输出保持干净。

---

## 5. 真机数据（**未重测**，引用 `docs/HANDOFF.md` §6.1）

本轮**没有设备**（`hdc list targets` 为空），所以下面这一组数字是上一轮的实测记录，
**不是**本轮结果；P1 之后的 A/B 矩阵（`docs/OKR-EDIT-PLAN.md` §5.4）必须重新采。

| 指标 | 值 | 出处 |
|---|---|---|
| 崩溃点 | `Check failed: toRegion2Idx != INVALID_VALUE`（`Preforward light sync` 之后）→ SIGABRT；GC 线程 `SIGSEGV@0x8`（`RegionInfo::VisitLiveObjectsUntilFalse`） | HANDOFF §6.1 |
| prompt 打开后不操作 | 88s / 2s / 17.7s **三次都崩** | HANDOFF §6.1 |
| GC 间隔 | 中位 **160ms** | HANDOFF §6.1 |
| GC 峰值 allocated | **25.5MB** | HANDOFF §6.1 |
| 每帧文字测量（真机，记忆化后） | 821 → **149** | HANDOFF §4（`c0bbeeb`） |
| 每帧文字绘制（真机，裁剪后） | 606 → **169** | HANDOFF §4（`5107ce2`） |
| 绘制耗时（真机，裁剪后） | 23.3 → **7.7ms/帧** | HANDOFF §4（`5107ce2`） |
| 主机 vs 真机的差异 | 主机 `WidgetTestHost` 一帧 ≈ 0.9ms（§3.1）而真机 7.7ms —— **口径不同**（真机含 SDL 渲染与 XComponent 提交），不要拿主机数字当性能结论 | 本文件 §3.1 / HANDOFF §4 |

---

## 6. 复跑步骤

```bash
cd cangjie
source scripts/env.sh

# 1) 单测（含 P0 计数器用例）——期望 713/713
cjpm test

# 2) 看基线那一行（--show-all-output 才显示通过用例的 stdout）
cjpm test --skip-build src/views/okr --show-all-output | grep '\[okr-metrics\]'

# 3) 打开每 60 帧的日志（可选；不设就完全静默）
TEXTURA_OKR_METRICS=1 cjpm test --skip-build src/views/okr

# 4) 像素门禁——期望 14/14
./scripts/parity.sh --theme both
./scripts/diff.sh --theme both

# 5) 真机（本轮未跑：无设备）
scripts/harmony/device_stability.sh 180
```

---

## 7. 口径与已知局限（读数字前先看）

1. **`frames` = `layout` 调用次数，不是窗口帧数**：实测 1 个 `host.frame` = 3 次 `OkrPage.layout`。
   计数器埋在 `OkrPage.layout` 末尾（`okr_page.cj:433`）；高度预演
   （`PageCanvas(measureOnly: true)`）不计数。
2. **`ops` / `hotspots` / `widgets` 是「最近一帧」的值**，不是累计：用例断言第二帧与第一帧相等，
   任何「批没 `clear()`」或「子树累积」都会让它变大。
3. **`frameMs` 不在视图里**：`AGENTS.md` §6 要求视图不读系统时钟（否则 parity 两次运行不再
   逐像素一致），所以帧耗时由测试侧 `MonoTime` 计时，字段名 `frameUs`。
4. **`focusableIds` 基线是 0**：只有 CUI 做焦点遍历时才调用；一次返回 46 个 id（`toArray()`）。
5. **单例 + 串行前提**：`okrMetrics` 是进程内单例（`okr_metrics.cj:167`）。`cjpm.toml` 没有配
   `--parallel`，用例串行执行，所以「两帧各 3 次 layout」是稳定的；若将来开
   `cjpm test --parallel N>1`，需改成 `ThreadLocal<OkrMetrics>`（照 `okr_ops.cj:505`
   `OKR_WIDTH_MEMO` 的做法），否则 `frames` 会被其它用例一起推高。
6. **`ellipsizeCandidates=0` 是数据决定的**，不是计数器没接上：520 宽的用例会打出
   `candidates ≈ 194/layout`（§3.3）。
7. **分配量本身没有直接测量**：仓颉语言内没有可用的分配器探针，计数器是**代理指标**
   （指令条数 / 测量次数 / 候选串个数 / 格式化次数）。真正的分配速率只能在真机用
   `scripts/harmony/device_stability.sh` 的采样看（§5.5 的目标以它为准）。
