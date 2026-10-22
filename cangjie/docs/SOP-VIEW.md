# SOP 视图 · `textura.views.sop`

Web 版 `src/modules/sop/*` 的 1:1 移植（SopPage / SopList / SopCanvas / SopNode /
SopInspector / SopRunBar / RunHistory + `sop.css`）。画面由自绘 Widget 组成（CSS grid +
绝对定位画布 + box-shadow 卡片无法映射到 CUI 线性栈），配色/间距全部取 `textura.ui`
令牌，画布坐标、自动布局、适配、运行状态机全部走 `textura.views.sop.logic`。

- 目录：`src/views/sop/`（`sop.cj` 入口 + `sop_model.cj` 常量/视图模型 + `sop_paint.cj`
  绘制原语 + `sop_list.cj` / `sop_canvas.cj` / `sop_inspector.cj` / `sop_runbar.cj` 四个区块）
- 依赖：`cui`、`textura.core.data`、`textura.ui`、`textura.views.sop.logic`（不 import shell）

## 1. 崩溃根因与修复（2026-10，`Route.Sop` SIGSEGV）

shell 把 `Route.Sop` 派发到 `sop.render` 后整条路由 `exit 139`，栈顶为
`sop.render → paintCanvas → paintEdgeLabel → ui.paint.textLeading → Renderer.text →
GlyphAtlas.get → SDL_UpdateTexture`（`text_glyph_atlas.cj:180`）。**两个独立 bug**，
都属于视图层：

### 1.1 无界 measure 把画布放大到 ≈1e6 px（真正触发崩溃的）

`.shell-content` 是 `ScrollView`；`ScrollView.measure` 用
`Size(contentWidth, LAYOUT_UNBOUNDED)`（≈999936）探测子项高度。`SopPageWidget.measure`
原样回显 `available.h`，于是：

1. 页面矩形高 ≈999936 → 画布 flow 区域同样 ≈999936；
2. `paintDots` 按 flow 区域铺点阵（18px 间距 × 0.84 zoom）→ 每帧约 **200 万个**
   `fillCircle`；
3. SDL 几何批次被撑爆（堆写坏），下一次 `SDL_UpdateTexture` 才炸——所以栈顶出现在
   “无文字也崩”的位置：把连线关掉后崩溃点会平移到 `paintNodeTitle`。

修复（`sop.cj`）：页视图必须报告**视口高度**而不是滚动内容高度。

```cangjie
public func measure(_: UiContext, available: Size): Size {
    // `.page.sop-page { height: 100% }`：页面占满 shell 内容盒
    let bounded = available.h < SOP_UNBOUNDED_PROBE           // 4096
    let height = if (bounded) { available.h } else {
        max(0.0, Float32(windowHeight) - tk.metrics.topbarHeight - tk.space.s5 * 2.0)
    }
    Size(min(max(0.0, available.w), 8192.0), min(height, 8192.0))
}
```

外加两道防御（`sop_canvas.cj`）：`paintDots` 只铺 flow 与当前 renderer clip 的交集，
并按 `SOP_DOTS_LIMIT = 20000` 上限保护；`paintCanvas` 在 flow 尺寸 ≤0 时直接返回。
即使宿主再给出异常矩形，也不会再产生百万级图元。

复现原崩溃：把 `measure` 改回 `Size(available.w, available.h)` 即可（本仓不再保留该路径）。

### 1.2 `match` 常量模式变成了绑定（连线几何全错）

`SOP_HANDLE_TOP` 等是 `let Int64`。仓颉里 `match (side) { case SOP_HANDLE_TOP => ... }`
的裸标识符是**绑定模式**（匹配一切），于是第一个分支恒命中：所有连线都用 top handle，
标签锚点算成 `(100, 400)` 而不是 `(105, 449)`，箭头/标签位置全偏（是/通过标签落到节点下方
约 40px）。同类问题此前已在检查器变体判定上踩过（`SopInspVariant` 已改为枚举）。

修复：`handleAnchor` / `handleDirection` 改用 `if (side == SOP_HANDLE_...)`。
教训：**只有当模式是字面量、枚举构造器或常量表达式时才做比较**，`let` 常量入 `match`
必须写成 `case x where x == C` 或直接 `if`。

## 2. 交互（全部真实写库）

| 交互 | 落库动作 |
|---|---|
| 选中节点 / 连线 | `store.select(id)` + 本地 selection |
| 拖动节点 | 释放时 `updateItems(SopPatch.canvasX/Y)`（拖动前先 materialize 预览布局） |
| 自动布局 | `logic.layoutIds(rankdir=TB, nodesep=60, ranksep=90, margin=40)` → 批量写回 |
| 适应画布 / 缩放（滚轮、按钮） / 平移 | `logic.computeReadableViewport` + 视口状态 |
| 运行 / 通过 / 未通过 / 跳过 / 退出 | `logic.startSession` / `recordResult` / `moveTo` + `store.logRun` |
| 分支选择 | `logic.advance(choice:)` |
| 检查项勾选 / 新增 / 删除 | `updateItem(sop.checklist)` |
| 新建 SOP / 新建节点 / 连边 / 复制节点 / 删除 | `createItem` / `createEdge` / `deleteItems` / `deleteEdge` |

手势与视口状态集中在 `SopViewState`（`remember` 持有，每次变更 bump `State<Int64>`），
`draw` 阶段不修改状态。

## 3. Parity（1440×900，DPR=1，`Noto Sans CJK SC`，固定 today）

度量脚本 `/tmp/sop_metrics.py`：复用 `tools/parity/diff.py` 的 `block_ssim`，两侧各做 1px 高斯模糊再算一次 SSIM（归一化跨引擎文字抗锯齿）。该脚本只在 /tmp，不落在仓库内（`tools/parity/` 是冻结契约）。

| theme | different | mean ΔRGB | max ΔRGB | ΔRGB≤32 | SSIM | **SSIM(blur 1px)** |
|---|---:|---:|---:|---:|---:|---:|
| light | 9.04% | 4.20 | 220 | **96.24%** | 0.8883 | **0.9532** |
| dark | 9.08% | 3.78 | 209 | **96.47%** | 0.8865 | **0.9543** |

分区块（light / dark，≤32 与 blurred SSIM）：

| 区块 | differ | ≤32 | blur SSIM |
|---|---:|---:|---:|
| sidebar | 3.65 / 3.58% | 98.38 / 98.44% | 0.9934 / 0.9935 |
| topbar | 7.81 / 7.83% | 97.88 / 97.95% | 0.9856 / 0.9861 |
| header | 6.24 / 6.25% | 97.79 / 97.76% | 0.9918 / 0.9904 |
| list | 5.33 / 5.35% | 98.26 / 98.50% | 0.9830 / 0.9825 |
| canvas | 11.03 / 11.20% | 95.58 / 95.79% | 0.9194 / 0.9221 |
| inspector | 16.10 / 16.14% | 91.33 / 91.93% | 0.8996 / 0.9083 |
| history | 19.32 / 19.35% | 89.07 / 90.13% | 0.9190 / 0.9251 |

两次独立运行逐像素一致：
`sha256 = c1dedad47079177a5636f30fbec41e5fd9cc89468d9381d476403249f31451bd`（light，`cmp` 相同）。

节点几何与参考图逐点吻合（白盒左上/右下，误差 ≤3px）：`(735,276) (733,375) (733,475)
(639,576) (638,677) (835,677)` vs ref `(735,276) (733,376) (733,476) (636,577) (633,678)
(836,678)`——含 `信息是否完整？` 决策节点（logic 修复回边图后 x 从 122 回到 11）。

## 4. 已知差异（未达标项定位）

`ΔRGB≤32` 未达 98%，缺口 100% 集中在两个文字密集面板，且**不是布局偏移**（卡片、输入框、
徽章边框、分隔线均与参考对齐 ±1px）：

1. **inspector / history（91.3% / 89.1%）**：字形栅格化差异。CUI 用 SDL_ttf 整数定位 +
   `textHeight` 居中，Chromium 用亚像素定位 + line-box 居中；实测同一行文字 ink 相差
   +1~+2px、笔画偏重（`550/620/650` 落 Medium/Bold 两个固定字面，`UI-KIT.md` §6.2）。
   11.5px 的 `运行历史` 行因此每个字形都有差异，1px 模糊后可回到 0.919。
2. **canvas（95.6%）**：节点标题/元信息同样是缩放后的小字号文字（13px × 0.84 zoom ≈ 10.9px），
   SDL_ttf 的 advance 略窄于 Chromium（实测标题 ink 65px vs 73px），叠上标签 chip 宽度差。
   边线颜色/宽度、点阵相位、节点边框与阴影均已对齐（ΔRGB 峰值只来自字形边缘）。
3. 其余同 `UI-KIT.md` §6：无 `letter-spacing`、无 `transition`、无 `color-mix` 精确实现
   （`tint` 等价）、无滚动条主题化。
4. `.sop-select`（Area）与 `.input` 在本移植中是**绘制态**：CUI 无绝对定位容器，自绘面板
   无法挂 `TextField`，因此检查器字段不可键入（重命名同理）；任务要求的全部交互
   （勾选/增删检查项/类型 chips/复制/删除/运行）都已实现。

## 5. 复现

```bash
rsync -a --delete --exclude target --exclude 'tools/parity/out' \
  cangjie/ /tmp/cj-view-sop/
cd /tmp/cj-view-sop && source scripts/env.sh
export TMPDIR=$HOME/.cache/cj-tmp        # /tmp 是 tmpfs，ar 打包可能 ENOSPC
cjpm build -i -o textura
for t in light dark; do
  xvfb-run -a -s "-screen 0 1440x900x24" ./target/release/bin/textura \
    --workspace tools/parity/workspace.json --route sop --theme $t \
    --width 1440 --height 900 --snapshot /tmp/sop-$t.png
done
python3 /tmp/sop_metrics.py              # 原始 + 1px 模糊 SSIM + 分区块（脚本见上）
```
