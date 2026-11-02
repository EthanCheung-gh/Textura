# cangjie/AGENTS.md — 后续 worker 强制约定

本目录是 Textura 仓颉重写的唯一工作区。开始任何代码前，先读：

1. `docs/STRUCTURE.md`（目录/所有权/公共契约）
2. `docs/CUI-PRIMER.md`（CUI 真实 API 与踩坑）
3. `docs/PARITY.md`（截图验收协议）

## 1. 技能门禁（强制）

- 写任何仓颉代码前：用 Skill 工具加载 `cangjie-coding`。
- 语言语法、标准库、集合、字符串、溢出、闭包等问题：再加载 `cangjie-language-basic`。
- 鸿蒙阶段（`harmony/`、OHOS 交叉编译、HAP、XComponent/ArkTS、hosted frame step）：必须加载 `cangjie-harmonyos`，不要用通用仓颉技能替代。
- 不凭记忆写 CUI API。先查 `third_party/CUI/docs/api/cui/**`、`docs/guide/**`、`docs/guide/tutorials/**`；CUI 0.9.6 的 vendored 副本没有 `examples/`。
- 不凭记忆写 SDL API。查 `third_party/cangjie-sdl/docs/api/**`。

## 2. 不可越界

- **不得修改 Web 版源码**：仓库根 `src/`、`package.json`、`vite.config.ts`、`src-tauri/`、`scripts/qa/`、`docs/screenshots/` 只读。
- **不得修改** `/home/ethan/CodeRepo/sandbox/PixCap-Cangjie` 的任何文件；只读参考。
- `cangjie/third_party/**` 是 vendored 只读副本。除已记录的 CUI-P01 外，不直接改第三方源码；需要补丁时先向协调者申请，并更新 `third_party/README.md`。
- 不实现不属于自己视图包的业务逻辑；不把业务逻辑塞进 `src/shell` 或 `src/ui`。
- 视图之间不得互相 import；共享逻辑放 `core.data` / `core.algo` / `ui`。

## 3. 公共契约

以下修改必须先经协调者批准，否则视为破坏并行工作：

- `textura.core.data` 的 `Item` / `Edge` / `Area` / `Run` / `Workspace` 字段与语义。
- `textura.core.data.inspectWorkspace` 的摘要字段。
- `textura.ui` 的主题工厂与设计令牌。
- `textura.shell` 的 `Route` / `routeId` / `parseRoute` / `ROUTES`。
- parity CLI 与 `docs/PARITY.md` 的容差。
- `textura.views.*` 的 `bootstrapTitle()` / `bootstrapNote()` 名称（在 shell 派发切换前）。

新增公共 API 时，先写清所有权、依赖方向和验收方式，再改代码。

## 4. 每个视图的强制交付

1. 只改自己的 `src/views/<name>/`；需要共享控件时先在 `src/ui/` 提案，不要在视图里复制。
2. 必须提供 parity 证据：
   - `tools/parity/out/<route>-light.png`
   - `tools/parity/ref/<route>-light.png` 的 diff 输出（不同像素占比、mean/max ΔRGB、SSIM、是否 PASS）
   - 两次独立运行逐像素一致（`sha256sum` 或 `diff.py` 自比）
3. 1440×900、`Noto Sans CJK SC`、固定 `today`；中文不得出现缺字方框。
4. 与参考图仍有差异时，在提交说明中逐项解释（布局/字号/颜色/交互态），不能只写“接近”。
5. 不通过修改参考图、裁剪截图、放宽容差来“通过”。

## 5. 构建/运行/验收命令

```bash
cd cangjie
source scripts/env.sh
./scripts/build.sh                 # -> target/release/bin/textura
./scripts/parity.sh                # 7 条路由 -> tools/parity/out/
./scripts/diff.sh light            # 超差返回非 0
```

运行环境固定：

- `unset WAYLAND_DISPLAY`、`SDL_VIDEODRIVER=x11`（`env.sh` 已处理）。
- `xvfb-run -a -s "-screen 0 1440x900x24"`。
- `--width 1440 --height 900`、DPR=1。
- 字体 `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`（SC face = 2）。

## 6. 代码约定

- 每个目录必须有 `.cj` 包文件；Cangjie 不扫描无包文件的中间目录。
- 包名与目录一致：`src/views/okr` -> `textura.views.okr`。
- 设计令牌只从 `textura.ui` 取；视图不写十六进制颜色。
- 间距/尺寸用 `vp`，文字用 `fp`，设备像素细节才用 `px`。
- 不读系统时钟/随机数进入视图；parity 的“今天”从 `ViewContext`/workspace 锚点来。
- 状态用 `State` / `rememberState` / `DerivedState`；不要用普通局部变量跨帧保存。
- 布局栈默认 `flexible = true`；放进 Panel 的栈/面板记得 `.hug()`。
- 只格式化本次改动的 `.cj` 文件；不要批量重排第三方或无关文件。

## 7. 提交

- 提交信息英文，文档中文。
- 按逻辑分批提交；不要一个巨型 commit。
- 不提交 `target/`、`tools/parity/out/`、`*.bmp` 临时文件。
- 提交前跑：`./scripts/build.sh`、至少一个相关路由的 `parity.sh` 与 `diff.py`。
- 若发现契约冲突或环境阻塞，停止并报告具体错误、已尝试方案、最小可行替代，不要静默跳过。
