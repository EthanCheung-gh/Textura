# 织理 Textura · 仓颉重写（CUI on SDL3）

Web 版 Textura（React + Tauri）的**仓颉原生重写**。UI 用 vendored 的 CUI 0.9.6 绘制，窗口/字体/事件走
cangjie-sdl 的 SDL3 绑定；目标有两个：在 1440×900 下与 Web 版逐像素对齐，以及打成一个鸿蒙 HAP。

- 802 个 `.cj`（含 vendored CUI / cangjie-sdl 绑定），根目录 `cjpm.toml` 只依赖 `cui`。
- 七条路由全部是真实业务视图，不再是占位面板。
- 本目录自洽：不修改仓库根的 `src/`、`package.json`、`vite.config.ts`、`src-tauri/`。

## 1. 当前状态

| 项 | 状态 | 证据 |
|---|---|---|
| 七个视图（dashboard / calendar / okr / gtd / gantt / sop / settings） | ✅ 实现并可渲染 | `tools/parity/out/` 14 张截图 |
| 应用外壳（侧栏、顶栏、路由、快速收集、命令面板、快捷键） | ✅ | `docs/SHELL.md` |
| 领域内核（Item/Edge/Area/Run、workspace 读写、selectors、日期/季度） | ✅ | `docs/CORE-API.md` |
| 设计令牌 / 基础控件 / 图标集 | ✅ | `docs/UI-KIT.md` |
| 单元测试 | ✅ 547 个用例全绿（7 个测试包） | `cjpm test` |
| Parity（7 路由 × light/dark） | ✅ 14/14 通过（模糊 SSIM 0.9538–0.9885；`ΔRGB≤32` 95.44%–98.46%） | `docs/PARITY-RESULTS.md` || 截图确定性 | ✅ 14/14 两次独立运行逐字节一致 | `docs/PARITY-RESULTS.md §5` |
| 鸿蒙 HAP 构建 | ✅ `BUILD SUCCESSFUL`，≈29 MB（25 + 8 个 `.so`） | `docs/HARMONY.md §5` |
| HAP 签名 / 安装 | ❌ 未签名（本机无 `com.ethancheung.textura` 的调试 profile） | `docs/HARMONY.md §7.1` |
| 真机运行 | ❌ 未验证（`hdc list targets` 为空） | `docs/HARMONY.md §6` |

一句话：**桌面侧已完成并有像素证据；鸿蒙侧构建链完整但停在「无设备 + 无签名材料」。**

> Parity 的 14/14 有一个前提：在**短路径**快照目录里跑（`--workspace` 57 字符）。`settings` 的路径行
> 没做省略号截断，≥64 字符会折行并让该路由掉出阈值（已知缺陷 7b）。在仓库内直接构建（72 字符）会命中。

## 2. 快速开始

### 2.1 环境依赖（桌面）

| 依赖 | 版本 / 路径 | 必需 |
|---|---|---|
| 仓颉编译器 + cjpm | `cjc 1.2.0 (cjnative)`、`cjpm 1.2.0`，装在 `~/.cjv`（`cjv envsetup` 可用） | ✅ |
| Cangjie 运行时 | 由 `scripts/env.sh` 的 `cjv envsetup` 注入 `LD_LIBRARY_PATH` | ✅ |
| SDL3 / SDL3_ttf（宿主 x86_64） | 已 vendored 在 `third_party/cangjie-sdl/.sdl3/` | ✅ |
| X11 / Xvfb | `xvfb-run -a -s "-screen 0 1440x900x24"`；必须 `unset WAYLAND_DISPLAY` | ✅ |
| 字体 | `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`（Noto Sans CJK SC） | ✅ |
| Python + Pillow + numpy | 3.14 / 12.1 / 2.3（只用于 `tools/parity/*.py`） | 仅比对 |
| Node 22+ + Chrome | 只在**重跑参考图**时需要（`tools/parity/capture_ref.mjs`） | 仅 oracle |
| DevEco 命令行工具 | `~/deveco-cli-stable/command-line-tools`（hvigor 6.26.4 / API 26）+ `~/cangjie-ohos-sdk` | 仅鸿蒙 |

### 2.2 构建与运行

```bash
cd cangjie
source scripts/env.sh            # PATH / LD_LIBRARY_PATH / SDL_VIDEODRIVER=x11 / TEXTURA_FONT
./scripts/build.sh               # 增量；产物 target/release/bin/textura
CLEAN=1 ./scripts/build.sh       # 从零（实测 2 分 51 秒，最大 RSS ≈ 976 MiB）

# 交互运行（关窗返回）
xvfb-run -a -s "-screen 0 1440x900x24" ./target/release/bin/textura \
  --route dashboard --theme light --width 1440 --height 900

# 截图并退出（CUI 写 BMP，进程内转成 PNG；1440×900、DPR=1）
xvfb-run -a -s "-screen 0 1440x900x24" ./target/release/bin/textura \
  --workspace tools/parity/workspace.json --route dashboard --theme light \
  --width 1440 --height 900 --snapshot ~/.cache/dashboard-light.png
```

CLI 全参数、退出码与“为什么 `--snapshot` 传的是 `.png` 而 CUI 写 BMP”见 `docs/PARITY.md §1、§4`。

### 2.3 Parity（验收）

```bash
cd cangjie && source scripts/env.sh
TEXTURA_PARITY_THEMES="light dark" ./scripts/parity.sh    # 14 张 -> tools/parity/out/（约 35 秒）

# 验收门：结构 ≤1px + 1px 高斯模糊 SSIM ≥0.95 + 原始 ΔRGB≤32 ≥95%
python3 tools/parity/metrics.py tools/parity/ref tools/parity/out
#   -> summary: 14/14 pairs pass (blurred SSIM>=0.95, raw ΔRGB<=32 >=95%)   退出码 0

# 出图复核（side-by-side + 差异热力图）；判定用的是原始层阈值，只作定位
python3 tools/parity/diff.py tools/parity/ref tools/parity/out --report-dir tools/parity/out/diffs
```

- 参考图 oracle 在 `tools/parity/ref/`（Chromium 截图，1440×900、DPR=1、`Noto Sans CJK SC`、锚点
  `2026-03-16`），必须入库；`tools/parity/out/` 是生成物，已 gitignore。
- **在短路径目录里跑**（例如 `~/.cache/cj-final-1`，`--workspace` 57 字符）。`settings` 会显示这个路径，
  长路径会折行导致该路由 FAIL（已知缺陷 7b，`docs/PARITY-RESULTS.md §7.3`）。
- 实测数字、两次运行 sha256、逐路由最差残差块定位：`docs/PARITY-RESULTS.md`。
- 重跑参考图需要 Web 版能构建：`docs/BUILD.md §5`。

### 2.4 测试

```bash
cd cangjie && source scripts/env.sh
cjpm test                        # 547 cases / 7 packages；首次约 3 分 18 秒，缓存后 17 秒
```

### 2.5 磁盘注意事项

本机 `/tmp` 是 tmpfs（13 G，长期 80% 占用）。**构建与截图请在 `$HOME` 下做**，并固定 `TMPDIR`：

```bash
export TMPDIR=~/.cache/tmp && mkdir -p "$TMPDIR"
rsync -a --delete --exclude target --exclude 'tools/parity/out' ./ ~/.cache/cj-work/
```

`ar` 打静态库时会写 `$TMPDIR`，`/tmp` 满会直接 ENOSPC。

## 3. 目录与依赖

```
cangjie/
├── cjpm.toml               只依赖 cui（CUI 再导出 sdl）
├── scripts/                env.sh / build.sh / parity.sh / diff.sh / harmony/*
├── src/
│   ├── main.cj             CLI + DesktopApp 生命周期（唯一知道 parity 参数的地方）
│   ├── snapshot.cj         BMP -> 确定性 PNG（仅 std.fs）
│   ├── core/data/          领域模型、JSON、store、selectors、日期、fixtures、ViewContext
│   ├── ui/                 设计令牌、字体、基础控件、图标
│   ├── shell/              侧栏/顶栏/路由/快速收集/命令面板/快捷键
│   └── views/<name>/       七个视图，各自 <name>/logic/ 放纯算法 + 测试
├── third_party/            CUI 0.9.6、cangjie-sdl（只读，见 third_party/README.md）
├── harmony/                鸿蒙工程（AppScope / entry / host / scripts 的产物落点）
├── tools/parity/           ref/（oracle）、workspace.json、diff.py、metrics.py、capture_ref.mjs
├── docs/                   见 §6
└── assets/fonts/           字体说明
```

依赖方向（**不得反向**，详见 `docs/STRUCTURE.md §2`）：

```
        main
       /     \
   shell ---> ui ---> core.data
     |
     +--> views.<name> ---> ui / core.data
```

- 视图之间**不得互相 import**；共享逻辑放 `core.data` / `ui`。
- `core.data` 不依赖 `cui`/`ui`/`shell`/`views`（所以 store 自带 `StateCell`，不用 `cui.State`）。
- `ui` 不依赖 `shell`/`views`；`views` 不依赖 `shell`。
- 视图只通过 `core.data.ViewContext`（store / theme / today / width / height / navigate）接入。

公共契约（实体字段、`Route`、令牌、parity CLI、`bootstrapTitle()`）改动前须经协调者批准，
见 `docs/STRUCTURE.md §3` 与 `AGENTS.md §3`。

### 第三方 pin

| 依赖 | pin / 版本 | 说明 |
|---|---|---|
| CUI | **0.9.6** + `CUI-P01-hosted-frame-step`（`beginHostedRun/step/endHostedRun`）+ `CUI-P02-overlay-scrollbar`（`ScrollView.scrollBarVisible` 等） | vendored；补丁说明见 `third_party/README.md` |
| cangjie-sdl | 0.9.6，commit **`98edeb79cb6d58b7c8ed86d8d6b5342dca4291a6`** | SDL3 / SDL3_ttf 绑定 |
| SDL3（宿主 x86_64） | 3.5.0，源码 ref `6defbc0129b5ba90bab3f6c67bbc1e9329e24ff1` | `third_party/cangjie-sdl/.sdl3/` |
| SDL3_ttf（宿主 x86_64） | 3.2.2（vendored FreeType，无 HarfBuzz/PlutoSVG） | 本机构建；PixCap 那份是 aarch64-ohos，不能给宿主用 |
| SDL3 / SDL3_ttf（OHOS） | 参考项目打完 4 个 SDL 补丁的 aarch64-ohos 产物 | `third_party/cangjie-sdl/.sdl3-ohos/`，含 **SDL3 openharmony 后端**（XComponent + 事件保留，CUI 依赖「事件保留」） |
| 仓颉 ohos 工具链 | `cjv install sts-1.2.0 -t ohos` | 交叉编译宿主库 |

**不要**在这里改第三方源码：需要补丁先报协调者并登记 `third_party/README.md`。

## 4. 已验证 / 未验证

### 4.1 已验证（可在本机复现）

- 从零构建：`rsync` 到空目录后 `CLEAN=1 ./scripts/build.sh` 成功（2 分 51 秒，无第三方预编译产物）。
- 测试：`cjpm test` 547/547，0 失败、0 错误、0 跳过。
- 七条路由 × light/dark 14 张截图全部生成，且**两次独立运行逐字节一致**（sha256 见 RESULTS §5）。
- Parity 三档判据 14/14 通过；逐路由最差残差块已定位到具体控件（RESULTS §6）。
- 结构项：画布、侧栏 240px、顶栏线 y=45/46、全局位移 (0,0)、长直线 ≤1.5px、文本行基准 ≤1px。
- 鸿蒙侧构建链：`build_ohos.sh` → `stage_libs.sh` → `assemble_hap.sh` 三步可重复执行，
  HAP 内含宿主库 + SDL + 仓颉运行时闭包（25 个 `libs/arm64-v8a/*.so` + 8 个 `ohos/*.so`），
  interop 运行时与参考 HAP **逐文件 sha256 相同**（`docs/HARMONY.md §5.5`）。

### 4.2 未验证 / 已知差异（接手前必须知道）

| # | 项 | 现状 | 影响 / 下一步 |
|---|---|---|---|
| 1 | **无鸿蒙设备** | `hdc list targets` 为空 | 安装/启动/首帧/软键盘全部未验证；`docs/HARMONY.md §6` 有 5 步验收序列 |
| 2 | **签名材料缺失** | 本机只有 `PixCap-Cangjie` 的 profile，bundleName 不符，`assembleHap` 报 `00303074`，回落 `product=unsigned` | 需要用户提供 `com.ethancheung.textura` 的调试 profile（§5） |
| 3 | **工具链代际错配** | 宿主库用 `cjv sts-1.2.0`（cjc 1.2.0）交叉编译；loader 与 `libohos.*` 来自 DevEco 仓颉 SDK 5.0.5.165（cjc 0.53.20） | 高风险：真机可能报 `ARKTS-INTEROP: cj module must dependent on ohos_ark_interop`（HARMONY §7.3） |
| 4 | **`libc++.so` 来源** | ohos 工具链不带 aarch64-ohos 版；当前用的是从**设备** `hdc file recv /system/lib64/libc++.so` 拉下来的那份（落在被 gitignore 的 `harmony/device-libs/`） | 换设备/固件要重新拉；仓库里不含该文件 |
| 5 | **`libcangjie-trace.so` 无来源** | 运行时按名 dlopen，找不到 | 已知风险 R5，通常只打一条 warn，不影响启动（HARMONY §7.4） |
| 6 | **SOP 检查器字段不可键入** | CUI 无绝对定位容器，自绘面板挂不了 `TextField`；Area/输入框是绘制态 | 重命名、改字段值不可用；勾选/增删/类型 chip/复制/删除/运行都可用（SOP-VIEW §4.4） |
| 7 | **settings 内容偏离参考图** | 文案 `importDocument` vs Web `replaceWorkspace`；CUI 多一个「清空工作区…」按钮 | 产品决策项，见 PARITY-RESULTS §7.1 |
| 7b | **settings 路径行会折行** | 「工作区文件」行没做省略号截断，`--workspace` ≥64 字符时折行并把下方内容下移 ~24px，该路由 parity 掉到 FAIL | **真实缺陷，待修**（改单行 + 中段省略）；修之前 parity 必须在短路径目录跑，见 PARITY-RESULTS §7.3 |
| 8 | **1px 线锐度不同** | 位置 ≤1px，但 CUI 把 1px 线画成 2px 半强度软边 | 渲染层特性，模糊后消失；不属结构失败 |
| 9 | **字形 AA 模型不同** | Chromium LCD 次像素（彩边）vs FreeType 灰度 | 不可消除，是原始像素指标只要求 95% 的原因 |
| 10 | **71 处 `src/` 编译 warning** | 全是 unused import/variable/unreachable pattern | 不影响产物；清理需另开任务 |

## 5. 接手第一步

### 5.1 有设备之后（三条命令 + 验收）

```bash
cd cangjie
./scripts/harmony/build_ohos.sh      # 交叉编译宿主库（幂等，只在快照里构建）
./scripts/harmony/stage_libs.sh      # NEEDED 闭包 + loader + ohos/ interop -> entry/libs/arm64-v8a
./scripts/harmony/assemble_hap.sh    # hvigorw assembleHap，结尾打印 STATUS: installable / NOT INSTALLABLE
```

这三条跑完只证明「HAP 打出来了」。**安装与启动按 `docs/HARMONY.md §6` 的 5 步走**（第 0 步的三个
前置条件不过，后面全是噪音）：

```bash
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
$HDC list targets                                              # 第 0 步：必须有设备
$HDC shell 'ls /system/lib64/platformsdk/ | grep -E "ark_interop|cj_environment"'   # 固件必须带仓颉互操作库
$HDC install -r harmony/out/entry-default-signed.hap           # 第 1 步
$HDC shell aa start -a EntryAbility -b com.ethancheung.textura  # 第 2 步
$HDC shell hilog | grep -E 'Textura/(HOST|FOCUS)|SDL/STARTUP|ARKTS-INTEROP|CANGJIE-RUNTIME'
$HDC shell ls -l /data/app/el2/100/base/com.ethancheung.textura/files/textura/
```

最后一条是「工作区播种是否成功」最可靠的证据（比日志可靠）：首次启动应出现 `workspace.json`，
切过主题/路由后出现 `.textura/ui-prefs.json`。

### 5.2 需要用户提供的材料

1. **给 `com.ethancheung.textura` 签发的调试 profile**（`.p7b`），其 `debug-info.device-ids` 必须包含目标设备 UDID；
2. 与之配对的 `.p12` 私钥 + 密码、`.cer` 证书链；
3. 目标设备的 UDID（`$HDC shell bm get -u`）。

材料给到后放进 `harmony/` 的签名目录并执行 `scripts/harmony/set_signing_material.sh`，
`assemble_hap.sh` 结尾变成 `STATUS: installable` 才继续往下做真机验证。

## 6. 文档索引

| 文档 | 内容 |
|---|---|
| `AGENTS.md` | 后续 worker 的强制约定（技能门禁、边界、提交规则） |
| `docs/STRUCTURE.md` | 目录/包所有权、依赖方向、公共契约 |
| `docs/BUILD.md` | 从零构建、运行、参考图 oracle、失败排查 |
| `docs/PARITY.md` | **验收协议**：CLI、确定性、三档阈值（含 95%/模糊 SSIM 的理由） |
| `docs/PARITY-RESULTS.md` | **实测证据**：14 张两套指标、确定性哈希、残差定位 |
| `docs/CORE-API.md` | `core.data` 公开 API（视图接入必读） |
| `docs/UI-KIT.md`、`docs/CUI-PRIMER.md` | 令牌/控件/图标；CUI 0.9.6 实战与踩坑 |
| `docs/SHELL.md` | 外壳几何、路由契约、命令面板、快速收集 |
| `docs/{CALENDAR,OKR,GTD,GANTT,SOP,DASHBOARD}-LOGIC.md` | 六个视图的算法层 |
| `docs/{GANTT,SOP}-VIEW.md` | 两个自绘视图的实现与已知差异 |
| `docs/HARMONY.md` | 鸿蒙链路：交叉编译、打包闭包、签名、真机验收、风险 |
| `third_party/README.md` | vendored 依赖 pin 与补丁登记 |
