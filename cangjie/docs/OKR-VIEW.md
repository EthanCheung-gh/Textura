# OKR 视图：实现与 Web 数值对照

本文件记录 OKR 页（`src/views/okr/`）与 Web 版（`src/modules/okr/`）的逐项数值对照，
重点是「关联执行项」弹窗（`LinkItemsDialog.tsx` + `okr.css:1283-1404`）——它在真机上曾经
**列表里看不到执行项**，根因与修法见 §2、§3。

- Web 源码是唯一事实来源；实现值全部来自 `okr.css` / `ui.css` / `tokens.css`。
- 颜色/间距只从 `textura.ui` 令牌取；数值常量集中在 `okr_link_list.cj` 顶部。
- 1440×900 的七路由像素门禁不包含弹窗（弹窗需要交互打开），因此弹窗靠主机测试
  （`okr_link_test.cj` / `okr_dialogs_test.cj`）+ 真机截图验收。

---

## 1. 「关联执行项」弹窗：CSS → 实现值

| CSS（Web） | 值 | 仓颉实现 |
|---|---|---|
| `.modal` 宽（`LinkItemsDialog.tsx:79` `width={640}`） | 640 | `Ui.modal(..., width: 640.0)`（`okr_dialogs.cj`） |
| `.modal` 最大高 / 位置（ui.css:472） | `max-height: 80vh`，顶部 10vh | `ModalFrame.resolve`（`ui/modal.cj`） |
| `.modal-header` 内边距 / 标题 / 副标题 | `16px 24px`；15/650；12.5 | `Ui.modal` 头部（`tokens.space.s5`、`TextSize.subheading`、`controlSmall`） |
| `.modal-body` 内边距 | 24 | `MODAL_BODY_PAD = 24`（`ui/modal.cj`） |
| `.modal-footer` | `12px 24px`、按钮 gap 8、右对齐 | `MODAL_FOOTER_VPAD = 12`、`HStack(spacing: s2)` |
| `.okr-link-search` | `display:flex; gap:8px` | `HStack(spacing: 8)` + 15px 搜索图标 |
| `.okr-link-search .input` | `flex:1`；`min-height:34px`；13.5px；radius 8；1px 边框 | `linkSearchField`：`TextField.flex()`，高 34，字号 13.5，`SurfaceStyle(surface, border, r=8)`，聚焦换 accent 边框 |
| `.okr-dialog-hint` | `margin-top:8px; 11.5px; line-height:1.5; text-muted` | 搜索行与提示同处 `VStack(spacing: 8)`；`Label` 11.5 / `textMuted` |
| `.okr-link-list` | `gap:2px; max-height:46vh; overflow-y:auto; margin-top:12px` | `OkrLinkList`：`OKR_LINK_ROW_GAP=2`、`maxHeight = 0.46 × viewportHeight`、body `VStack(spacing: 12)`；滚轮/裁切在列表内 |
| `.okr-link-item` | `gap:10px; padding:8px 10px; border:1px transparent; radius:8` | `OKR_LINK_ROW_PAD_X=10`、`OKR_LINK_ROW_GAP_X=10`、`OKR_R_MD=8`；行边框盒高 **55.25**（1+8+19.5+2+15.75+8+1） |
| `.okr-link-item:hover` | `background: surface-2` | 行悬停（`ctx.isHovered`）填 `surface2` |
| `.okr-link-item.is-checked` | `background: accent-soft; border-color: accent/30%` | `accentSoft` + `accent.withAlpha(77)` 描边 |
| `.okr-link-item.is-linked` | `background: surface-2`；标题 `text-muted` | 已关联行优先用 `surface2`（CSS 声明顺序在 is-checked 之后）+ 标题 `textMuted` |
| `.okr-check` | **14×14**，`accent-color`，`flex:none` | `OKR_LINK_CHECK=14`，radius 3；勾选为 accent 填充 + check 图标，未选为 surface + `borderStrong`（`okr.css:773` 是 14px，不是 16px） |
| `.okr-link-main` | `flex:1; min-width:0; column; gap:2px` | 主列宽度 = 行宽 − 1 − 10 − 14 − 10 − 10 − 100 − 1（左右内边距/勾选框/gap/进度区），标题与 meta 间距 2 |
| `.okr-link-title` | `13px; weight 550; line-height:1.5` | `OKR_LINK_TITLE_SIZE=13`、重量 550、行盒 19.5 |
| `.okr-link-meta` | `gap:6px; flex-wrap:wrap; 10.5px; text-muted` | 单行排布（主列宽度足够；窄窗口仍按顺序绘制，超出部分省略），`OKR_LINK_META_GAP=6`、10.5 |
| 徽章（类型/状态/已关联） | `.badge { 11px; padding 2px 7px; 1px; radius }` | `PageCanvas.badge` → `BadgeView`，高 23.6（`OKR_BADGE_H`） |
| `.okr-area` / `.okr-area-dot` | `11.5px; gap:5px`；dot 7px | `OKR_LINK_AREA_SIZE=11.5`、`OKR_LINK_DOT=7`、间隙 5，颜色取 `Area.color` |
| 排期文案 | `formatSchedule(item)`（11.5px mono） | `linkScheduleText` + 10.5px mono（meta 行字号） |
| `.okr-link-progress` | `flex: 0 0 100px; gap:6px; 10.5px` | `OKR_LINK_PROGRESS_W=100`、gap 6；进度条高 5（`ProgressView Sm`）+ 右对齐百分比文字 |
| 空态 | `EmptyState compact`（图标/标题/描述） | `Ui.emptyState(..., compact: true)`：「没有匹配的执行项 / 换个关键词，或先在甘特 / GTD 中创建行动。」 |
| `.okr-link-count` | `margin-right:auto; 12px; text-muted` | 页脚 `Label("已选 N")` 12 + `Spacer()` |
| 页脚按钮 | 取消 ghost；`关联所选` primary，`disabled={selected.size===0}` | `Ui.button("取消", Ghost)`；`Ui.button("关联所选", Primary, enabled: selected+removed > 0)` |

### 1.1 与 Web 版有意不同的两处

1. **已关联项可取消**：Web 把已关联行的 checkbox 设为 `disabled`；按本轮用户要求，已关联行
   仍默认勾选，但可取消，确认时对取消项执行 `store.deleteEdge`（`linkRemoved` 独立记录）。
   页脚计数仍只显示「已选 N」（待关联数），通知里会区分「已关联 N，解除 M」。
2. **按钮文案保留「关联所选」**（Web 原文），未改成「确认关联」。

---

## 2. 真机「列表看不到执行项」的根因（已修复）

旧实现的一行是：

```text
HStack { 选择按钮; VStack { 标题 / 徽章行 }.hug().flex(); ProgressView }
```

`ProgressView.measure` 返回 `Size(available.w, …)`（进度条要占满轨道）。它在 HStack 里是
**非 flex 子项**，在固定测量阶段先被量成整行宽度，`remaining` 变成 0；随后 flex 主列
（标题/徽章）只分到 **0 宽**。控件确实存在、也进了语义树，但文字盒子宽度为 0，所以屏幕上
一片空白。

主机探针（修复前）输出：`row '官网改版' rect=291.25,271,0.00,28` —— `w == 0`。

---

## 3. 修法：`OkrLinkList`（自绘 + 语义）

- 新增 `okr_link_list.cj`：用本页既有的 `PageCanvas` 逐像素布局（行高/内边距/字号全部由
  §1 的常量推导），不再依赖栈的剩余宽度分配；每行宽度 = 列表宽度，标题/徽章/进度各有
  明确矩形。
- 交互：整行点击切换勾选；悬停 `surface-2`；滚轮滚动（内容高于 46vh 时，窗口跟随并裁切）；
  `MouseMove` 用 `claimHoverIfInside` 声明指针形状。
- 每行注册一个 `Checkbox` 语义节点（标题 + `checked` + `Activate`），主机测试可断言
  「首屏 ≥5 行、行宽 > 0、勾选/取消、确认写边、空态」。
- 候选池（`okrLinkCandidates`）：全部 `project` + `action`；**排除 `dropped`**；按
  「父路径（`parentPathText`）→ 标题」稳定排序；再按查询过滤（标题/标签/负责人/备注/领域名，
  复用 `matchesQuery`）。
- 打开时查询初值取 `store.ui.search`（与 Web `useEffect` 一致），搜索框自动聚焦
  （`FocusRequest` + `Ui.modal` 的 `focus`）。

---

## 4. 主机回归

| 文件 | 覆盖 |
|---|---|
| `okr_link_test.cj` | 候选非空/排除 dropped/排序；首屏 ≥5 行且行宽 >0；勾选+确认写 `okr` 边；已关联取消+确认删边；无匹配时显示空态 |
| `okr_dialogs_test.cj` | 新建目标 / 季度选择 / 目标菜单 / KR 状态 / 删除确认：关键文案与页脚按钮都进入语义树且有正宽高 |
| `okr_page_test.cj` | `measure` 在首次 layout 前就能给出内容高度（DEVICE-NOTES §12） |

---

## 5. 待补

- 真机截图：弹窗打开显示多行候选、勾选一行、确认后 KR 行出现该执行项。本轮 HAP 已重编并安装成功
  （`STATUS: installable`），但设备锁屏需要指纹/密码，`aa start` 被系统拒绝
  （`10106102 The device screen is locked`），因此截图待解锁后补；复跑命令见
  `docs/DEVICE-NOTES.md` §18.7。
- Web 版窄窗口（≤1180）下弹窗的行为未单独对拍；弹窗宽度固定 640，在 1024 视口里
  `Ui.modal` 会夹到 `min(640, viewport-48)`，行内主列按剩余宽度省略标题。
