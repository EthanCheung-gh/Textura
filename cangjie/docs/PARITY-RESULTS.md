# Parity 实测结果（7 路由 × light/dark = 14 张）

本文件是 `docs/PARITY.md` 验收协议的**证据附件**：只记录可复现的实测数字、命令与残差定位结论。
协议本身（CLI、容差、确定性要求）在 `docs/PARITY.md`；两者冲突时以 `docs/PARITY.md` 为准，并修本文件。

测量时间：2026-10-23（settings 长路径修复后的最终复跑）。测量目录：仓库工作树 `cangjie/` 直接构建，
`--workspace` 是**仓库内 72 字符绝对路径** `/home/ethan/CodeRepo/sandbox/Textura/cangjie/tools/parity/workspace.json`；
所有临时文件经 `TMPDIR=~/.cache/tmp`。修复前必须在 57 字符短路径快照目录（`~/.cache/cj-final-1`）里测，
那段历史数据保留在 §5 与 §7.3 作为对照。

## 0. 结论速览

| 层 | 指标 | 阈值 | 14 张结果 |
|---|---|---|---|
| 视觉主指标 | 1px 高斯模糊后 SSIM | ≥ 0.95 | **14/14 通过**，最低 0.9529（settings-light） |
| 原始像素 | `ΔRGB ≤ 32` 像素占比 | ≥ 95% | **14/14 通过**，最低 95.39%（settings-light） |
| 结构 | 长直线配准最大偏差 | ≤ 1px | 12/14 ≤ 0.5px；gtd-light 1.5px、okr/settings/sop 1.0px |
| 结构 | 全局最佳位移 | (0, 0) | **14/14 = (0,0)**，无系统性 1px 偏移 |
| 确定性 | 两次独立运行 sha256 | 完全一致 | **14/14 一致**（同一 argv 拼写，见 §5） |
| 构建 | `CLEAN=1 ./scripts/build.sh` | 成功 | 成功（新鲜克隆 149.78 s，最大 RSS ≈ 976 MiB） |
| 测试 | `cjpm test` | 全绿 | 547/547 通过，0 失败 0 错误 |

原始像素 SSIM（未模糊）**不作为**通过条件：14 张里只有 6 张 ≥ 0.95，其余落在 0.886–0.935。原因见 §3.3。

> 前提：上表的 14/14 是 settings 长路径缺陷修复后、在**仓库内目录**（`--workspace` 72 字符）测的。
> 修复前 `settings` 的路径行不做省略，长度 ≥64 字符时会折行并把下方内容下移 ~24px，两张随即 FAIL
> （blur 0.905）。该缺陷已在 commit `a0c7a81` 修复（单行 + 中间省略 + tooltip），修复前后对照见 §5/§7.3，
> 视图细节见 `docs/SETTINGS-VIEW.md`。

## 1. 环境

| 项 | 值 |
|---|---|
| 主机 | AMD Ryzen 7 255（16 线程），Linux x86_64，Xvfb 24 位色 |
| 编译器 | `cjc 1.2.0 (cjnative)`，`cjpm 1.2.0` |
| CUI | 0.9.6（vendored，含 CUI-P01 / CUI-P02） |
| cangjie-sdl | 0.9.6，pin `98edeb79cb6d58b7c8ed86d8d6b5342dca4291a6` |
| SDL3 / SDL3_ttf（宿主） | 3.5.0 / 3.2.2，`third_party/cangjie-sdl/.sdl3/` |
| 字体 | `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`（SC face，19 484 784 B） |
| 比对 | Python 3.14.4 + Pillow 12.1.1 + numpy 2.3.5（无 scikit-image） |
| oracle | `tools/parity/ref/`（Chromium/CDP 截图，1440×900，DPR=1） |
| workspace | `tools/parity/workspace.json`：30 items / 3 areas / 3 runs / 12 edges，`updatedAt=2026-03-16T02:00:00.000Z` |

`workspace.json` 的两种哈希都记录，避免再次误判“文档里的 sha256 过期”：

- 文件字节 sha256 = `258b14f3e3bb0d6d75b2c4b90473a053f4742dfce94dd0a27bc222c4bb2dd6c4`
- `ref/capture-report.json` 里记的 `62e62460…3611f07` = 同一对象的 Node `JSON.stringify(obj)`（**紧凑序列化**）
  sha256，不是文件字节哈希。二者可互相验证：

```bash
python3 -c "import hashlib;print(hashlib.sha256(open('tools/parity/workspace.json','rb').read()).hexdigest())"
node -e "const c=require('crypto'),f=require('fs');console.log(c.createHash('sha256').update(JSON.stringify(JSON.parse(f.readFileSync('tools/parity/workspace.json','utf8')))).digest('hex'))"
```

## 2. 从零验证（新鲜克隆）

```bash
export TMPDIR=~/.cache/tmp
git clone --branch feat/cangjie-rewrite ~/CodeRepo/sandbox/Textura ~/.cache/cj-clone-final
cd ~/.cache/cj-clone-final/cangjie
CLEAN=1 ./scripts/build.sh          # 全量重建
cjpm test                           # 7 个测试包
```

实测（2026-10-23 收尾，克隆内 `--workspace` 69 字符）：

| 项 | 结果 |
|---|---|
| 克隆内容 | 802 个 `.cj`、14 张 `ref/*.png`，工作树干净、无 `target/` |
| `CLEAN=1 ./scripts/build.sh` | 成功，**149.78 s wall**，最大 RSS 999 860 KiB |
| 产物 | `target/release/bin/textura` |
| warning | 编译器分阶段输出按 `(文件,行号)` 去重后 **99 处**：`third_party/` 28 处（CUI 27 + cangjie-sdl 1），**`src/` 71 处** |
| `cjpm test` | **547/547 通过**，0 失败、0 错误、0 跳过；7 个测试包（core.data 106、calendar.logic 117、gtd.logic 78、okr.logic 77、gantt.logic 76、sop.logic 64、dashboard.logic 29） |
| `cjpm test` 耗时 | 全量（含测试目标编译）171.65 s；缓存后约 17 秒 |
| `parity.sh --theme both` + `diff.sh --theme both` | **14/14 PASS，退出码 0**（§7.6） |

> **与预期不符的事实**：原计划“warning 只应来自 third_party”**未成立**。71 处 warning 来自本仓 `src/`
> （okr 34、sop 16、gtd 12、gantt 5、settings 3、calendar 1），全部属于 `unused import` /
> `unused variable` / `unreachable pattern` 一类，不影响产物与测试。本轮整合 worker 的写入范围不含
> `cangjie/src/**`，因此**未修**，列入 §7.4。

## 3. 像素指标（14 张）

命令：

```bash
cd ~/CodeRepo/sandbox/Textura/cangjie
export TMPDIR=~/.cache/tmp && source scripts/env.sh
./scripts/parity.sh --theme both                                # 14 张 -> tools/parity/out/
./scripts/diff.sh --theme both                                  # 三层门；报告 tools/parity/out/gate-report.json
python3 tools/parity/diff.py    tools/parity/ref tools/parity/out \
        --report-dir ~/.cache/cj-diffs --min-pass-ratio 0.95    # 旁路：side-by-side + 热力图（只定位，不判定）
```

`tools/parity/gate.py`（`scripts/diff.sh` 的实现）按 `docs/PARITY.md §2.1` 的三层判据给出 PASS/FAIL、
退出码与 JSON；度量全部来自 `tools/parity/metrics.py`（原始层 + 1px 高斯层 + 结构层 + 最大残差区块，
仅 Pillow + numpy）。`diff.py` 保持原有冻结 CLI，仍产出 `*-side.png` / `*-diff.png` 供人工复核。

### 3.1 原始像素（未模糊）

| 路由-主题 | 差异像素% | mean ΔRGB | max ΔRGB | ≤32 占比 | SSIM | 判定 |
|---|---:|---:|---:|---:|---:|---|
| dashboard-light | 7.04 | 2.69 | 220 | 97.29 | 0.9605 | PASS |
| dashboard-dark | 6.85 | 2.32 | 209 | 97.53 | 0.9611 | PASS |
| calendar-light | 5.73 | 1.98 | 220 | 97.93 | 0.9625 | PASS |
| calendar-dark | 5.57 | 1.75 | 203 | 98.04 | 0.9647 | PASS |
| okr-light | 10.01 | 3.83 | 220 | 96.41 | 0.9273 | PASS¹ |
| okr-dark | 10.04 | 3.31 | 208 | 96.61 | 0.9346 | PASS¹ |
| gtd-light | 10.41 | 4.51 | 223 | 95.69 | 0.9009 | PASS¹ |
| gtd-dark | 10.32 | 3.93 | 209 | 96.19 | 0.9052 | PASS¹ |
| gantt-light | 17.34 | 2.23 | 220 | 98.39 | 0.9668 | PASS |
| gantt-dark | 30.47 | 2.06 | 209 | 98.46 | 0.9678 | PASS |
| sop-light | 9.04 | 4.20 | 220 | 96.24 | 0.8883 | PASS¹ |
| sop-dark | 9.08 | 3.78 | 209 | 96.47 | 0.8865 | PASS¹ |
| settings-light | 10.24 | 4.80 | 220 | 95.39 | 0.9119 | PASS¹ |
| settings-dark | 10.18 | 4.11 | 217 | 95.81 | 0.9141 | PASS¹ |

¹ 原始 SSIM < 0.95，按协议**只看 ≤32 占比**（≥95%）判定通过；SSIM 未达标的原因见 §3.3。

> **与上一版（settings 修复前）的差异**：只有 settings 两行参与变化，量级 ≤0.06pp / ≤0.0013 SSIM——
> light 10.18→10.24、95.44→95.39、0.9132→0.9119；dark 10.12→10.18、95.85→95.81、0.9154→0.9141。
> 其余 12 张与 `tools/parity/out/gate-report.json` 一致到最后一位。变化原因是路径行由「折行 + 全字符」
> 改为「单行 + 中间省略」，墨迹本身不同（§7.3），不是渲染回归。

`gantt` 的“差异像素%”高达 17–30%，但 mean ΔRGB 只有 2.0–2.2、≤32 占比 98.4%：甘特是整窗自绘网格，
每个格子边线都被 CUI 画成 2px 软化边（§4.3），差异像素多但幅度极小。**差异像素占比不能单独作为判据**。

### 3.2 1px 高斯模糊后（视觉主指标）

卷积核 `exp(-x²/2σ²)`，σ=1.0、半径 3（7 taps），可分离、边缘复制填充，两张图各自模糊后再比较。

| 路由-主题 | blur SSIM | blur ≤32 占比 | 判定 |
|---|---:|---:|---|
| dashboard-light | 0.9878 | 99.31 | PASS |
| dashboard-dark | 0.9885 | 99.42 | PASS |
| calendar-light | 0.9868 | 99.45 | PASS |
| calendar-dark | 0.9877 | 99.57 | PASS |
| okr-light | 0.9713 | 98.59 | PASS |
| okr-dark | 0.9740 | 98.84 | PASS |
| gtd-light | 0.9656 | 98.18 | PASS |
| gtd-dark | 0.9685 | 98.60 | PASS |
| gantt-light | 0.9851 | 99.55 | PASS |
| gantt-dark | 0.9872 | 99.61 | PASS |
| sop-light | **0.9538** | 98.12 | PASS |
| sop-dark | 0.9543 | 98.29 | PASS |
| settings-light | **0.9529** | 97.78 | PASS |
| settings-dark | 0.9552 | 98.15 | PASS |

余量最小的两张是 `settings-light 0.9529` 与 `sop-light 0.9538`，距 0.95 只有 0.3–0.4%——
它们的残差来源已定位到具体控件（§6），不是全局性偏差。

> **本表的前提**：`--workspace` 是仓库内 72 字符绝对路径，settings 长路径缺陷已修（commit `a0c7a81`），
> 因此不需要短路径目录。修复前同样的仓库路径会把 settings 打到 blur SSIM 0.905 / 边缘覆盖 82%
> （历史数据见 §5「确定性边界」与 §7.3）。

### 3.3 为什么原始像素不能用 98%

两个不可消除的渲染管线差异：

1. **字形抗锯齿模型不同。** 参考图由 Chromium 在 LCD 模式渲染，字边缘带橙/蓝次像素彩边；CUI 走
   SDL_ttf/FreeType 灰度 AA。同一段文字、同一字体、同一字号，逐像素仍会在笔画边缘相差 50–200。
   这个差异**连外壳自身的文字（侧栏、顶栏）都无法消除**，所以它不是某个视图的实现缺陷。
2. **1px 边框被画在半像素上。** Web 的 1px 实线是单像素、满强度（样本值 217），CUI 在相同坐标摊成
   2px、各约 50% 混合（229 / 229.3）。中心位置一致，但“一条线”变成“两行灰色”。这不是缺失，
   而是 CUI 的边框取整策略；量化见 §4.3。

两条都在 1px 高斯模糊后基本消失（0.886→0.954、0.913→0.954），所以协议把**模糊后 SSIM 作为视觉主指标**，
把原始像素的 ≤32 占比作为“不能偷偷大改布局/配色”的护栏（95%），并且**不放宽任何结构性检查**。

## 4. 结构验证：元素边界 / 行高 / 列宽 / 1px 线

结构判据由 `metrics.py` 的 `structure` 段给出：

- **边缘 1px 覆盖**：参考图的每个亮度梯度像素，在对侧 3×3 邻域内是否有对应边缘（双向都算）。
- **长直线配准**：只取长度 ≥300px 的连续梯度（1px 线、面板边框、网格线、分隔线；字形笔画达不到），
  按 ±2px 容差配对，报最大偏差与“只有一侧存在”的线。
- **全局位移**：对边缘图做 −2..+2 的整像素平移搜索，最佳位移必须是 (0,0)。

### 4.1 已验证项（14/14）

| 结构项 | 期望 | 实测 |
|---|---|---|
| 画布 | 1440×900，DPR=1 | 14/14 完全一致（尺寸不符时脚本直接报错退出） |
| 侧栏右边界 | x = 240 | 14/14 检出且值相同（`vertical_rules` 的 `240.0`） |
| 顶栏底边 1px 线 | y = 45/46 | 14/14 检出且位置相同（`45.5`） |
| 全局最佳位移 | (0, 0) | 14/14 为 (0, 0)；零位移下的精确边缘重合率 0.689–0.899 |
| 水平长直线配准 | ≤1px | 12/14 最大偏差 ≤0.5px；gtd-light 1.5px；okr/settings/sop 1.0px |
| 垂直长直线配准 | ≤1px | 配上的全部 ≤0.5px；未配上的见 §4.3（锐度差异，中心仍重合） |
| 文本行基准 | ≤1px | 抽样实测：dashboard「最近运行」7 行文字带 y 起点差 ≤1px；gtd 列表 5 个文字带的 y 包络一致（CUI 侧被 1px 空隙切成两段，例如参考 313–349 vs CUI 313–326 + 328–350） |
| 边缘 1px 覆盖 | — | 92.83%（sop-dark）… 99.68%（dashboard-light），见下表 |

| 路由-主题 | 边缘 1px 覆盖% | 长直线最大偏差 px | 仅单侧存在的线 |
|---|---:|---:|---:|
| dashboard-light | 99.68 | 0.5 | 1 |
| dashboard-dark | 99.59 | 0.0 | 1 |
| calendar-light | 99.16 | 0.5 | 3 |
| calendar-dark | 99.18 | 0.0 | 2 |
| okr-light | 97.94 | 1.0 | 5 |
| okr-dark | 96.66 | 1.0 | 1 |
| gtd-light | 96.35 | 1.5 | 12 |
| gtd-dark | 97.77 | 0.0 | 11 |
| gantt-light | 99.17 | 0.5 | 2 |
| gantt-dark | 99.04 | 0.0 | 1 |
| sop-light | 93.95 | 1.0 | 10 |
| sop-dark | 92.83 | 1.0 | 9 |
| settings-light | 95.94 | 1.0 | 4 |
| settings-dark | 95.69 | 0.0 | 5 |

### 4.2 全局（14/14）出现的 y=55.5 单侧线

每一张图里 `55.5` 都出现在“仅参考侧”列表，但**这不是缺线**：参考图 y=55 是单像素实线（217），
CUI 在 y=55 / y=56 各约 50% 混合（229.0 / 229.3），梯度 241→229 只有 12，低于检测阈值 18。
内容区（x 300–1400）逐行取均值可复核：

```bash
python3 - <<'PY'
import numpy as np; from PIL import Image
for tag,p in [("ref","tools/parity/ref/dashboard-light.png"),("cui","tools/parity/out/dashboard-light.png")]:
    g=np.asarray(Image.open(p).convert("RGB")).astype(int).mean(axis=2)
    print(tag, [(y,round(g[y,300:1400].mean(),1)) for y in range(53,58)])
PY
```

### 4.3 “仅单侧存在的线”是锐度差异，不是位置差异

以 sop 右侧检查器左边界（x≈1079/1080）为例，同一 y 采样：

| | x1078 | x1079 | x1080 | x1081 |
|---|---:|---:|---:|---:|
| 参考图 | 232 | **217** | 241 | 241 |
| CUI | 232 | **224** | **229** | 241 |

参考图是 1px 满强度线，CUI 是 2px 各约 50% 的软边；两者中心都在 1079.5，误差 ≤0.5px。
gtd 的 9–10 条“单侧水平线”（y ≈ 258 / 364 / 381 / 487 / 504 / 663 / 700 / 717 / 838）同理：
同一 y 上两边的深色像素数几乎相同（如 y=487：参考 458 个、CUI 456 个），只是 CUI 的梯度摊平到两行、低于阈值。

结论：**1px 线的位置在 1px 内成立，但“锐度”不成立**（1px 实线 vs 2px 半强度软边）。这是 CUI 渲染层的特性，
在模糊后消失，也是 §3.1“差异像素多、mean ΔRGB 低”的主因。

## 5. 确定性：两次独立运行

```bash
cd ~/CodeRepo/sandbox/Textura/cangjie && source scripts/env.sh
mkdir -p ~/.cache/cj-run2
WS="$PWD/tools/parity/workspace.json"                          # 72 字符，仓库内绝对路径
for theme in light dark; do for route in dashboard calendar okr gtd gantt sop settings; do
  xvfb-run -a -s "-screen 0 1440x900x24" ./target/release/bin/textura \
    --workspace "$WS" --route "$route" --theme "$theme" \
    --width 1440 --height 900 --snapshot ~/.cache/cj-run2/$route-$theme.png
done; done
for f in tools/parity/out/*-*.png; do b=${f##*/}
  [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$(sha256sum ~/.cache/cj-run2/$b | cut -d' ' -f1)" ] \
    && echo "SAME $b" || echo "DIFF $b"
done
```

结果：**14/14 逐字节一致**。抽样（全部哈希见下表）：
| 路由-主题 | sha256（两次运行相同） |
|---|---|
| dashboard-light | `65946bce68b417ed0e284377c49e94c6c6c4341c0d2bf4777ec73590faecc8c1` |
| dashboard-dark | `33aeedbce3bd7246ede33a2c729c7e8ae77c4d752e71d234914dae10796457bd` |
| calendar-light | `a1b92d1d0457d7e2b4aaf9c6c2daf9533ec610d061297caacda6c139dde49c42` |
| calendar-dark | `97621d199215ffaeb04de514d68c5075c08628ab1e406e01316ad356cbbc137a` |
| okr-light | `ee792cf97edbd723dea3fcef67282c6c9bf5c46c3424313c41e448c10557e1fe` |
| okr-dark | `98e3a0877b5f9f022e9be896950ee2900c929365d077f33d8ecb8f4e88e07d04` |
| gtd-light | `62c98c26f3a3aa6031869105056586a817e0656bde64702935b3b8f447b4d7c8` |
| gtd-dark | `c7793857f8233d0118c14c146aef95365571ca92fa3da86bacaf9d2874c00a15` |
| gantt-light | `94ab3cd5946220071de4e48f1d858107b41bda5fcb6515ce3ead1d788e3c77ff` |
| gantt-dark | `52ae55a3df71e44a6231a9ae5c9ced62889f03c8cc799e5c4ee86e921195cbc5` |
| sop-light | `c1dedad47079177a5636f30fbec41e5fd9cc89468d9381d476403249f31451bd` |
| sop-dark | `d4995331dce631a76ab5291c9d3ca0ae5b61d6ad20cd20638022e85da783be4f` |
| settings-light | `053e1d74e56ac2da0bb276f8577bb33283aa14dfb859a57e5dae42c0fc792d86` |
| settings-dark | `46ac0c943cc0b5d1bf00590e5701c5c3996e354127bd7771a5813702fdc8d32b` |

settings 两张的哈希随长路径修复改变（旧值 `4cd42e4b…` / `28221e11…` 属于修复前的折行版）；其余 12 张不变。

> **确定性边界（实测踩到的两个坑）**
>
> 1. **`--workspace` 的字符串拼写会进入画面。** `settings` 视图的“数据目录 / 工作区文件”行直接显示
>    `store.path()`。用相对路径 `tools/parity/workspace.json` 与绝对路径各跑一次，`settings-light` 会有
>    0.13% 像素不同（1712 px，bbox x≈480–792 / y≈466–504），SSIM 0.9950。
> 2. **`--workspace` 的长度同样会进入画面，但已不影响版式（历史缺陷，commit `a0c7a81` 修复）。**
>    该行在参考图里是单行；修复前字符串变长后 CUI 会折行，下方整块下移 ~24px。修复后是单行 + 中间
>    省略，同一二进制、同一 workspace 内容、只改路径长度时：
>
> | `--workspace` 长度 | 修复前 settings-light（历史数据） | 修复后 settings-light（本轮实测） |
> |---:|---|---|
> | 28 字符（`/home/ethan/.cache/p/ws.json`） | 差异 10.07%，原始 SSIM 0.9175，**blur 0.9582**，边缘 95.89% → PASS | blur **0.9582**，raw ≤32 95.53%，边缘 94.79% → PASS |
> | 57 字符（修复前 `…/cj-final-1/…`；修复后 `…/cj-paths/pppppppppppppp/workspace.json`） | 差异 10.18%，原始 SSIM 0.9132，**blur 0.9541**，边缘 95.94% → PASS | blur **0.9538**，raw 95.43%，边缘 93.01% → PASS |
> | 64 字符 | 差异 15.58%，原始 SSIM 0.8640，**blur 0.9063**，边缘 81.77% → **FAIL** | blur **0.9533**，raw 95.41%，边缘 92.72% → PASS |
> | 72 字符（仓库内 `…/Textura/cangjie/tools/parity/workspace.json`） | 差异 15.63%，原始 SSIM 0.8634，**blur 0.9054**，边缘 81.97% → **FAIL** | blur **0.9529**，raw 95.39%，边缘 92.46% → PASS |
> | 96 字符 | 未测（已越过 57–64 折行阈值，按同一机制必然 FAIL） | blur **0.9526**，raw 95.40%，边缘 92.39% → PASS |
> | 200 字符 | 未测（同上） | blur **0.9528**，raw 95.39%，边缘 92.44% → PASS |
>
> 修复后四种长度以上的版式逐行一致：把 28/57/64/96/200 字符的截图与 72 字符截图逐像素相减，差异
> 全部落在值行 bbox（x 480–877 / y 466–504），卡片分隔线与页面高度零位移。修复前的修法说明与
> 更细的几何对照见 `docs/SETTINGS-VIEW.md §1–§2`。
>
> **结论**：只要 argv 完全一致就逐字节一致；路径长度不再影响 settings 的通过与否（最低 0.9526，仍有
> 0.26% 余量），只有路径**拼写**会改变值行那几个像素。

## 6. 逐路由最大残差区块定位

区块 = 90×90 网格，按块内 mean ΔRGB 排序取第一。`over32` = 该块内 ΔRGB>32 的像素占比。

| 路由 | 最差块 (x,y) | mean ΔRGB | over32 | 该块是什么 | 定位结论 |
|---|---|---:|---:|---|---|
| dashboard-light | (360, 720) | 18.8 | 21% | 「最近运行」列表第 3 行起的标题/时间文本 | 字形 AA 差异（灰度 vs 次像素）；行带 y 起点差 ≤1px（§4.1），无行距漂移 |
| dashboard-dark | (360, 720) | 16.5 | 20% | 同上 | 同上 |
| calendar-light | (1170, 450) | 13.7 | 16% | 右侧日程卡「信息架构重排」的标题 + 元信息行（第 3 天 / 日期区间） | 纯字形 AA；卡片边界与行位一致（垂直长线配准 0.5px） |
| calendar-dark | (1170, 450) | 12.1 | 14% | 同上 | 同上 |
| okr-light | (450, 270) | 17.6 | 14% | 目标卡片 KR 标题大字（28px 级）与表头行 | 大字号笔画更粗，AA 模型差异被放大；位置一致 |
| okr-dark | (360, 270) | 15.7 | 14% | 同上偏左（目标卡左列） | 同上 |
| gtd-light | (270, 540) | 22.7 | 23% | 列表项标题 + 元信息 chip（第二、三行） | 字形 AA + chip 圆角/描边软化；行带位置完全相同 |
| gtd-dark | (270, 540) | 19.7 | 22% | 同上 | 同上 |
| gantt-light | (270, 90) | 15.6 | 17% | 顶部工具栏（视图切换 / 缩放按钮）文字与按钮描边 | 按钮 1px 边框软化 + 文字 AA；网格线本身 ≤0.5px |
| gantt-dark | (270, 90) | 14.9 | 16% | 同上 | 同上 |
| sop-light | (1170, 270) | 25.6 | 18% | 右侧检查器面板的标签 + 正文 | 文字 AA **叠加**检查器左边界 1px→2px 软化（§4.3），所以 sop 的边缘覆盖最低（93.95%） |
| sop-dark | (1170, 270) | 22.8 | 18% | 同上 | 同上 |
| settings-light | (1080, 360) | **44.2** | 30% | 「重置为演示数据」说明段落 | **内容差异，不是渲染差异**：文案不同 + CUI 多一个按钮，见 §7.1 |
| settings-dark | (1080, 360) | 43.3 | 32% | 同上 | 同上 |

除 settings 外，全部 12 个最差块都能归到同一组原因：字形 AA 模型 + 1px 边框锐度。settings 是唯一带
**可见内容差异**的路由，把它的 44.2 与其余路线的 12–26 放在一起看，量级差异正说明“多出来的那部分”不是渲染噪声。

## 7. 已知差异与残余问题

### 7.1 settings：文案与功能偏离参考图（真实差异，非渲染）

| 项 | 参考图（Web） | CUI |
|---|---|---|
| 重置说明文案 | `重置会通过 replaceWorkspace 用内置演示数据…` | `重置会通过 importDocument 用内置演示数据…` |
| 导入说明文案 | `导入会先校验 JSON，再通过 replaceWorkspace…` | `…再通过 importDocument…` |
| 危险操作按钮 | 只有「重置为演示数据」 | 另有「清空工作区…」+ 二次确认弹窗 |

- 依据：`src/modules/appshell/SettingsPage.tsx:454` vs `cangjie/src/views/settings/settings.cj:570`；
  Web 侧 `grep -rn '清空工作区' src` 无结果，CUI 侧 `settings.cj:586,725` 有按钮与弹窗。
- 影响：像素上集中在 (1080, 360) 与 (1080, 450) 两块；语义上是**功能增量**（CUI 多一个清空入口）。
- 处置建议：这是产品决策而非渲染缺陷。若要求像素级一致，需删除清空入口并把文案改成 `replaceWorkspace`；
  若保留，则在 `docs/PARITY.md` 的偏差清单里长期登记。本轮按“不改代码”的边界**只登记不修**。

### 7.2 其余已知偏差（已在代码里确认原因）

- 1px 线与边框：位置 ≤1px，锐度为 2px 半强度（§4.3）。影响所有路由，模糊后消失。
- 字形边缘色边：LCD 次像素 vs 灰度 AA（§3.3）。不可消除。
- gantt 差异像素占比 17–30%：格子线极多，软化后每个格子贡献 2 行差异像素；mean ΔRGB 仅 2.0。

### 7.3 settings：工作区路径行（历史缺陷，commit `a0c7a81` 已修）

**历史缺陷**：`settings` 的“数据目录 / 工作区文件”两行把 `store.path()` 原样渲染且**允许折行**。
参考图里它们是单行（Web 用 `text-overflow: ellipsis` 的省略号策略），所以：

- `--workspace` 长度 ≤57 字符：单行，settings 通过（blur 0.954–0.958）。
- 长度 ≥64 字符（含**仓库内**的 `…/Textura/cangjie/tools/parity/workspace.json`，72 字符）：折成两行，
  下方“存储概况 / 立即保存 / 导入导出”整块下移 ~24px，settings 掉到 blur 0.905、边缘覆盖 82% → FAIL。

**修复**（commit `a0c7a81`，`fix(cangjie): ellipsize long workspace paths in the settings view`）：

- `src/views/settings/widgets.cj` 的 `KeyValueRow` 把值改成**单行 + 中间省略**（`ellipsizeMiddle()`，
  保留目录头与文件名尾部），行高恒为 19.25，未截断时行为不变；
- 被截断时悬停显示完整值的 tooltip，信息不丢；
- 值列宽 = `min(行宽 × 68%, 行宽 − 标签宽 − 16)`，1440×900 下约 58 个半角字符。

**修复前后对照**（同一二进制、同一 workspace 内容，只改 `--workspace` 路径长度；数据表在 §5）：

| | 修复前（历史数据） | 修复后（本轮实测） |
|---|---|---|
| 28–57 字符 | 单行，blur 0.9582 / 0.9541 | blur 0.9582 / 0.9538 |
| 64 字符 | 折行，blur 0.9063 → FAIL | blur 0.9533，PASS |
| 72 字符（仓库内） | 折行，blur 0.9054 → FAIL | blur 0.9529，PASS |
| 96 / 200 字符 | 未测（同一机制必然 FAIL） | blur 0.9526 / 0.9528，PASS |

修复后 28/57/64/96/200 字符的截图与 72 字符截图逐像素相减，差异只落在值行 bbox（x 480–877 / y 466–504），
卡片边界与页面高度零位移。几何细节、阈值推导与 200 字符压力测试见 `docs/SETTINGS-VIEW.md §1–§2`。

**对验收的影响**：parity 不再需要短路径目录，仓库内 72 字符路径直接跑就是 14/14（§0）；`settings`
两张的像素指标比修复前低 0.0012–0.0013 SSIM、0.04–0.05pp（值行墨迹变了），仍在阈值内。

### 7.4 `src/` 编译 warning（71 处，未修）

- 组成：`third_party/` 28 处（CUI 27 + cangjie-sdl 1）+ **`src/` 71 处**（okr 34、sop 16、gtd 12、
  gantt 5、settings 3、calendar 1）。
- 类型：`unused import` / `unused variable` / `unused function`（third_party）与
  `unreachable pattern`（1 处，`views/settings/logic/format.cj:82`）。
- 影响：无（产物与 547 个测试都不受影响），但会影响“干净构建”的观感。
- 未修原因：本轮整合 worker 的写入范围不含 `cangjie/src/**`；清理时只需删无用 import / 加 `_` 前缀。

### 7.5 oracle 与产物入库

- 参考图 oracle 只能在有 Chrome + Web 版构建时重跑；本轮**未重跑** `capture_ref.mjs`，沿用已提交的
  `ref/`（`capture-report.json` 记录锚点 `2026-03-16`、字体、viewport 齐全）。
- `tools/parity/out/`、`target/`、`harmony/out/`、`harmony/entry/libs/`、`*.hap` 与各类构建缓存
  均不入库（`.gitignore` 已逐条核对；`tools/parity/ref/` 与 `workspace.json` 必须在库里）。

### 7.6 新鲜克隆自检（2026-10-23）

把分支重新 `git clone` 到 `~/.cache/cj-clone-final`（工作树干净、无 `target/` 与 `out/`，克隆内
`--workspace` 为 **69 字符**绝对路径），在克隆里从零构建并跑完整门禁：

| 步骤 | 结果 |
|---|---|
| `git clone --branch feat/cangjie-rewrite ~/CodeRepo/sandbox/Textura ~/.cache/cj-clone-final` | 802 个 `.cj`、14 张 `ref/*.png`、`git status` 干净 |
| `CLEAN=1 ./scripts/build.sh` | 成功，**149.78 s wall**，最大 RSS 999 860 KiB；warning 去重 99 处（`src/` 71 + `third_party/` 28），与 §2 一致 |
| `cjpm test` | **547/547 通过**，0 失败 0 错误（171.65 s） |
| `./scripts/parity.sh --theme both` + `./scripts/diff.sh --theme both`（克隆内 69 字符路径） | **14/14 PASS，退出码 0** |

结论：**提交后的仓库自洽**——构建、547 个测试、14 张像素证据都能从零复现，而且**不再依赖构建目录的
路径长度**：克隆路径 69 字符 > 旧折行阈值 64，修复前这里必然是 12/14（`settings-light/dark` FAIL），
现在直接 14/14。settings 的路径行只改变值行那几个像素（§7.3）。

## 8. 复跑清单（接手者照着跑一遍即可复现本文件的全部数字）

```bash
export TMPDIR=~/.cache/tmp
mkdir -p ~/.cache/tmp && cd ~/CodeRepo/sandbox/Textura/cangjie

# 不需要短路径目录：settings 的路径行已单行省略（§7.3）。下面的 72 字符仓库路径就是测量条件。
echo ${#PWD}/tools/parity/workspace.json    # 72
CLEAN=1 ./scripts/build.sh                                   # §2
cjpm test                                                    # §2
./scripts/parity.sh --theme both                             # §3 的 14 张
./scripts/diff.sh --theme both                               # 三层门；期望 14/14 PASS、退出码 0
python3 tools/parity/diff.py tools/parity/ref tools/parity/out --report-dir ~/.cache/cj-diffs
```

预期输出：

```text
gate: 14/14 PASS (theme=both, routes=all) [structure: ruleΔ≤1.5px, shift=(0,0), edge≥90% | visual: blur SSIM≥0.95 | raw: ΔRGB≤32 ≥95%]
gate: verdict PASS (exit 0)
```

退出码 0。任一 pair 落到阈值外，`gate.py` 返回 1 并打印该 pair 的失败档位与原因。
`gate-report.json` 会写在 `tools/parity/out/`（已 gitignore），字段说明见 `docs/PARITY.md §9.5`。

