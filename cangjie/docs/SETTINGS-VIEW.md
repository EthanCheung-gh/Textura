# 设置视图（`textura.views.settings`）实现与验收说明

本文记录设置视图的移植来源、桌面端能力映射、长路径处理方式与 parity 证据。
移植来源（只读）：`src/modules/appshell/SettingsPage.tsx`、`src/modules/appshell/appshell.css`（`.settings-*`，319-515）、
`src/modules/appshell/{workspaceIO.ts,importValidation.ts}`、`src/styles/shell.css`（`.page*`，255-296）。

## 1. 长路径处理（2026-10-23 修复）

**问题**：`--workspace` 路径原先按原样绘制在「工作区文件」行。该行沿用 Web 的
`.settings-row-value { max-width: 68%; word-break: break-all }`（appshell.css:406-413），
路径 ≥64 字符时会折成两行，行高由 19.25 变为 36.5，整页下移 24px，parity blur SSIM 从
0.954 掉到 0.906。仓库默认路径（`/home/ethan/CodeRepo/sandbox/Textura/cangjie/tools/parity/workspace.json`，
72 字符）必然触发。

**修复**：值列改为**单行 + 中间省略号**（`ellipsizeMiddle()`，`widgets.cj`），保留目录头与
文件名尾部（`/tmp/ppp…pppppppp/workspace.json`）；悬停时用 tooltip 显示完整值。
对应 commit `a0c7a81`（`fix(cangjie): ellipsize long workspace paths in the settings view`）。

**为什么不用 Web 的换行**：Web 的两个值是短常量（`localStorage`、`textura.workspace.v1`），
`word-break` 折行不会发生；桌面端的工作区路径长度不受控，折行会改变卡片高度并推移后续卡片，
与「卡片高度、行数、后续卡片起点必须与参考图一致」相冲突。因此选择截断：行高恒定，参考图
（单行值）的几何得以保持，且文件名始终可见。该取舍与 Web 的差异仅限「超长值被截断」，
Web 在超长值时表现为换行。

**阈值**：值列宽 = `min(行宽 × 68%, 行宽 − 标签宽 − 16)`。1440×900、左列卡片内宽 597 时
上限为 406px；`Textura Mono` 11.5px 下约等于 58 个半角字符（CJK 约 35 字）。超过即出现 `…`，
行高不变。`数据目录` 行与 `存储概况` 行使用同一控件、同一规则。

## 2. 版式不随内容长度变化（实测）

4 个不同长度的 `--workspace` 路径，1440×900、`--route settings --theme light`：

| 路径长度 | 左侧卡片分隔/边界行 | 右侧卡片分隔/边界行 | 页内容高 | blur SSIM |
|---:|---|---|---:|---:|
| 28 | 251 / 330 / 346 / 419 / 645 / 661 / 752 / 889 | 233 / 353 / 416 / 473 / 490 / 563 / 728 | 810.2 | 0.9584 |
| 57 | 同上 | 同上 | 810.2 | 0.9531 |
| 64 | 同上 | 同上 | 810.2 | 0.9525 |
| 96 | 同上 | 同上 | 810.2 | 0.9519 |

四组几何完全一致（卡片顶边 161 / 346 / 661 与 161 / 490，末卡底边 889，关于卡底边 728），
blur SSIM 均 ≥ 0.95。路径长度只影响「工作区文件」一行的文字墨迹，不再影响布局。

另做 200 字符路径压力测试：分隔/边界行同为 `251/330/346/419/645/661/752/889` 与
`233/353/416/473/490/563/728`，行高与卡片起点不变，值显示为
`/tmp/qqq…qqqq/workspace.json`（尾部文件名保留）。

**最终门禁复测（2026-10-23，仓库内 72 字符路径）**：`settings-light` blur SSIM **0.9529**、raw ≤32 **95.39%**、
边缘覆盖 92.46%；`settings-dark` **0.9552** / 95.81% / 92.00%（`tools/parity/out/gate-report.json`）。
把 28/57/64/96/200 字符路径的截图与 72 字符截图逐像素相减，差异**只落在值行 bbox（x 480–877 / y 466–504）**，
blur SSIM 落在 0.9526–0.9582，全部 PASS——即路径长度已不影响版式，只影响那一行的墨迹。
（与 §2 表的 0.9519–0.9584 是两次独立测量：路径字符串不同则墨迹不同，属正常范围。）

## 3. Parity 复测（仓库相对路径 `tools/parity/workspace.json`，29 字符）

| 主题 | 原始 SSIM | 原始 ΔRGB≤32 | 1px 高斯模糊 SSIM |
|---|---:|---:|---:|
| light | 0.9182 | 95.54% | **0.9587**（PASS ≥0.95） |
| dark | 0.9205 | 95.95% | **0.9609**（PASS ≥0.95） |

两次独立运行逐像素一致：
light `c501a29c13a8e27dc7cdeb6d2482f5c90ffb97aeeaa51c6667d0170bfeffabaa`，
dark `c8b34aa892ae6a02de352cbc9cc5c3a1b840a33f2dfb3d0f86640870d51e499e`。

原始 ΔRGB≤32 未达 98% 的原因：整图文字墨迹约 60k px（4.6%），其中约 83% 的像素
ΔRGB>32；即使逐元素取最优整数平移，单行墨迹 bad 率仍为 65–90%。这是 CUI/SDL_ttf 与
Chromium 的字形栅格差异（hinting / gamma / 亚像素定位），位于 `textura.ui`/CUI 文本后端，
不在本视图的写入范围；shell 自绘区域（文字与布局本应完全一致）同样有 1.3–2.3% 的该差异。

## 4. 已知差异（保留的桌面端文案，均为有意）

| 位置 | 参考图（Web） | 本实现 | 理由 |
|---|---|---|---|
| 页头徽章 | 浏览器调试模式 | 桌面模式 | 单文件持久化 |
| 运行模式 | 浏览器调试模式（localStorage） | 桌面（文件持久化） | `AppStore.save()` 原子写 |
| 数据目录 | localStorage | 真实目录（可截断） | 工作区目录 |
| 工作区文件 | textura.workspace.v1 | 真实路径（中间省略） | 见第 1 节 |
| 第四行 | 轮换备份 / 浏览器调试模式不提供 | 存储概况 / `v1 · N 条记录 · X KB · 最后保存` | 任务要求记录数/版本/字节数/最后保存；不新增行 |
| 外观卡说明 | 立即生效 + localStorage | 记录偏好，重启后生效 | CUI 主题在 `DesktopApp` 创建时固定 |
| 数据与备份说明/提示 | localStorage 或 Tauri `.bak` | 原子写入、无轮换备份、恢复走导入 | `core.data` 无备份 API |
| 维护说明/提示 | 同步写回磁盘 / replaceWorkspace | 需手动保存 / importDocument | 核心无自动保存、API 实名 |
| 导入卡提示 | replaceWorkspace | importDocument | 同上 |
| 关于·技术栈 | Tauri v2 · React 18.3 … | 仓颉 1.2.0 · CUI 0.9.6 · SDL3 · 自绘控件 | 真实技术栈 |
| 维护卡操作行 | 仅「重置为演示数据」 | 追加「清空工作区…」 | 任务强制的危险操作（二次确认） |

## 5. 其它「内容长度影响布局」的隐患

1. **导入/导出卡提示**：文本内嵌 `items / areas / runs` 计数（如 `30 条记录 · 3 个领域 · 3 条 SOP 运行记录`）。
   计数达到 5–6 位时该提示可能由 2 行变 3 行，卡片高度 +19px。Web 同样按 CSS 折行，属设计内行为；
   若后续要求绝对固定高度，可在提示里改用「千分位缩写 + 省略」。
2. **存储概况行**：字节数/记录数变长时只影响文字宽度，已单行截断，不改变行高。
3. **文档版本号**：`v${workspace.version}` 变长（如 `v10`）同样只影响文字宽度，已单行截断。
4. **卡片标题、关于·技术栈、数据模型**：常量文案，不受数据影响。
5. **提示框（`.settings-note`）宽度**：固定为卡片内宽，与窗口宽度相关；窗口 ≥1180px 时单列/双列
   断点与 Web 的 `@media (max-width: 1180px)` 一致（双列 → 单列由 shell 宽度决定，本轮未改）。

## 6. 复现命令

```bash
cd cangjie
rsync -a --exclude target --exclude tools/parity/out ./ /tmp/cj-view-settings/
cd /tmp/cj-view-settings && source scripts/env.sh && ./scripts/build.sh
for th in light dark; do
  xvfb-run -a -s "-screen 0 1440x900x24" ./target/release/bin/textura \
    --workspace tools/parity/workspace.json --route settings --theme $th \
    --width 1440 --height 900 --snapshot /tmp/settings-$th.png
done
cd /home/ethan/CodeRepo/sandbox/Textura
python3 cangjie/tools/parity/diff.py cangjie/tools/parity/ref/settings-light.png /tmp/settings-light.png
python3 - <<'PY'
from PIL import Image, ImageFilter
for t in ("light", "dark"):
    Image.open(f"cangjie/tools/parity/ref/settings-{t}.png").filter(ImageFilter.GaussianBlur(1.0)).save(f"/tmp/b-{t}-ref.png")
    Image.open(f"/tmp/settings-{t}.png").filter(ImageFilter.GaussianBlur(1.0)).save(f"/tmp/b-{t}-out.png")
PY
python3 cangjie/tools/parity/diff.py /tmp/b-light-ref.png /tmp/b-light-out.png
```
