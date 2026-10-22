# 鸿蒙 HAP 宿主（CUI on SDL）—— 实现、复现与验收

本文记录 Textura 仓颉版装进 HarmonyOS 应用壳的完整链路：工程结构、交叉编译、运行时初始化选型、
打包闭包、接设备后的验收命令与已知风险。桌面版（`docs/BUILD.md`）不受影响。

> **本轮验证范围**：本机 `hdc list targets` 为空（无设备），所以除「真机安装/启动/首帧」外的每一环都在
> 构建期验证过（ELF 架构、导出符号、NEEDED 闭包、**interop 运行时落位**、HAP 内容、ArkTS 编译、
> CMake shim、签名失败码、可安装性判定）。凡未在真机验证的结论，正文里都显式标注「仅构建期验证」。

---

## 0. 状态速览

| 项 | 状态 | 证据 |
|---|---|---|
| `libtextura_host.so` aarch64-linux-ohos 交叉编译 | ✅ | `build_ohos.sh`；`ELF 64-bit LSB shared object, ARM aarch64`；**从空快照可重建**（本轮实测） |
| 宿主入口 = 桌面壳层契约 | ✅ | `AppStore(SystemClock)` → `store.load(<沙箱>/workspace.json)` → `ShellRuntime` → `ShellHost(interactive=true)` → `buildShell(host)`（§4.5） |
| 宿主库导出 SDL 入口 | ✅ | `.dynsym` 含 `SDL_AppInit/AppIterate/AppEvent/AppQuit`（GLOBAL FUNC） |
| C shim → `libmain.so` | ✅ | hvigor `BuildNativeWithNinja`；`SONAME libmain.so`，导出同样 4 个符号 |
| ArkTS 编译 + 页面打包 | ✅ | hvigor `CompileArkTS` 成功，`entry-default-*.hap` 内含 `ets/`、`module.json`、`resources.index` |
| `assembleHap` 成功 | ✅ | `product=unsigned`：`BUILD SUCCESSFUL`，产出 ≈29.08 MB HAP（见 §5.1） |
| HAP 内含宿主 + SDL + 仓颉运行时闭包 | ✅ | 25 个 `libs/arm64-v8a/*.so`（§5.4） |
| **HAP 内含 `libs/arm64-v8a/ohos/` interop 运行时** | ✅ | 8 个库，与真机可用的参考 HAP **逐文件 sha256 相同**（§5.5） |
| 签名产物（可安装） | ❌ | 本机无 `com.ethancheung.textura` 的调试 profile，`00303074`（§7.1） |
| 「产物是否可安装」由脚本显式判定 | ✅ | `assemble_hap.sh` 结尾打印 `STATUS: installable` / `STATUS: NOT INSTALLABLE` |
| 工作区播种 / 偏好持久化（沙箱） | ⚠️ 仅构建期验证 | 路径与建目录逻辑见 §4.5；真机看 `files/textura/workspace.json` 是否生成 |
| 运行时初始化（`requireCJLib` 路线） | ⚠️ 仅构建期验证 | 符号/依赖证据见 §4.2；无设备无法验证 ArkVM 注册与首帧 |
| 宿主包与 loader 的版本组合 | ⚠️ **高风险** | 与本仓相同的组合在参考项目上**失败过**（§7.3） |
| 真机安装/启动/首帧/键盘 | ❌ 未验证 | 需设备 + 为 `com.ethancheung.textura` 签发的调试 profile |

---

## 1. Pin 版本与本机路径

| 组件 | 版本 / 路径 | 用途 |
|---|---|---|
| 仓颉编译器 / cjpm | 1.2.0（`~/.cjv`，`cjc 1.2.0 (cjnative)`） | 宿主库编译 |
| 仓颉 ohos 交叉工具链 | `sts-1.2.0-linux-x64-ohos`（`cjv install sts-1.2.0 -t ohos`） | `--target aarch64-linux-ohos` |
| 官方鸿蒙仓颉 SDK | `~/cangjie-ohos-sdk`（`cangjie/oh-uni-package.json` = 5.0.5.165，apiVersion 15，Beta2） | loader、`ohos.*` 模块库、c_wrapper diff、libsecurec |
| DevEco 命令行工具 | `/home/ethan/deveco-cli-stable/command-line-tools`（26.0.0.821，hvigor 6.26.4，API 26） | `hvigorw`、`ohpm`、hdc、ohos CMake/ninja、sysroot |
| `hdc` | `~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc`（**不在 PATH**，文档一律写绝对路径） | 设备安装/日志/取库 |
| CUI | 0.9.6 vendored，含 `CUI-P01-hosted-frame-step` | `beginHostedRun/step/endHostedRun` |
| cangjie-sdl | 0.9.6 pin `98edeb79` | SDL3 绑定 |
| SDL3（ohos） | `third_party/cangjie-sdl/.sdl3-ohos/libSDL3.so`<br>build-id `516bb2a8d60c32b25cec0648de6af145ca832954`，sha256 `cea7d57d…361febfa` | 预编译，**不重修源码**（见 §8） |
| SDL3_ttf（ohos） | `.sdl3-ohos/libSDL3_ttf.so`<br>build-id `d8701394c394e8ba6d172c78e2a0bbb01f3c673d`，sha256 `cb51514d…5e8c` | 同上 |
| `libark_interop_loader.so` | `~/cangjie-ohos-sdk/cangjie/build/linux_ohos_aarch64_llvm/ohos/`（217 992 B） | ArkTS 侧启动仓颉运行时 |
| `libohos.*.so` / `libcj_ndk_ffi.z.so` | 同上目录（`libohos.ark_interop.so` 2 112 304 B 等 7 个） | loader 启动运行时后按名解析的 interop 库 |
| `libohos_ark_interop_diff.z.so` | `~/cangjie-ohos-sdk/cangjie/c_wrapper_diff/linux_ohos_aarch64_llvm/`（5 592 B） | `libohos.ark_interop.so` 的 C wrapper 差分 |
| `libsecurec.so` | `~/cangjie-ohos-sdk/cangjie/compiler/runtime/lib/linux_ohos_aarch64_llvm/`（63 304 B） | 每个 `libohos.*.so` 的 NEEDED |
| 调试签名材料 | `~/CodeRepo/sandbox/PixCap-Cangjie/.certs/pixcapt-debug/`（只读复用，**bundleName 不符**，见 §7.1） | `build-profile.json5` 的 `signingConfigs` |
| 目标 SDK | `targetSdkVersion` / `compatibleSdkVersion` = `5.0.4(16)`，实际用 API 26 SDK 编译 | SDL openharmony 后端要求 ≥ API 16 |

**版本错配（必须知情）**：宿主库由 cjv `sts-1.2.0`（cjc 1.2.0）交叉编译，而 loader 与
`libohos.*` / `libark_interop.z.so` 来自 DevEco 仓颉 SDK **5.0.5.165**（cjc 0.53.20）。这两套不是同一
代工具链，正是参考项目记录过「失败→最终成功」的组合；本仓沿用同一组合，风险等级**高**，详见 §7.3。

固定约定：设备类型 `tablet / 2in1 / phone`，`orientation: landscape`，bundleName `com.ethancheung.textura`，
**不声明任何权限**（声明即安装期校验，见 §7.7）。

---

## 2. 从零复现（3 条命令）

```bash
cd /home/ethan/CodeRepo/sandbox/Textura/cangjie

./scripts/harmony/build_ohos.sh      # 交叉编译宿主库（含快照同步）
./scripts/harmony/stage_libs.sh      # NEEDED 闭包 + loader + ohos/ interop -> entry/libs/arm64-v8a
./scripts/harmony/assemble_hap.sh    # hvigorw assembleHap -> harmony/out/*.hap（含载荷校验 + 可安装性判定）
```

重复执行安全（幂等）。三个脚本都**只在快照里构建**，共享工作树不会被写入 `target/`、`.hvigor/`、
`oh_modules/`：

```
快照目录      $TEXTURA_HARMONY_SNAP（默认 /tmp/cj-harmony）
同步方式      rsync -a --delete --exclude target --exclude tools/parity/out \
                    --exclude node_modules --exclude dist --exclude harmony/out <repo>/ <snap>/
```

>`rsync --delete` 会删掉快照里的 `entry/libs`（它不在源码树里），所以 `assemble_hap.sh --no-sync`
>之前必须自己有 `stage_libs.sh` 的产物；带 sync 的 `assemble_hap.sh` 会自动重跑 staging。

**别把构建 scratch 放在一个快满的文件系统上**。两个位置都要够：

| 位置 | 环境变量 | 典型占用 | 失败现象 |
|---|---|---|---|
| cjc/LLVM 中间对象 | `TMPDIR`（默认 `/tmp`） | 编译期 1–2 GB | `LLVM ERROR: IO failure on output stream: Disk quota exceeded`，看起来像某个包编译失败 |
| 快照 + hvigor 归档 | `TEXTURA_HARMONY_SNAP`（默认 `/tmp/cj-harmony`） | ≈250 MB + HAP 归档 | `PackageHap … IOException: Disk quota exceeded`，zip 报 `Bad CRC checksum` / `unclosed entries` |

`/tmp` 在本机是 13 GB tmpfs 且被多个 worker 共享，上面两种失败都真实发生过。脚本会在 scratch 剩余空间
少于 2 GB 时提前 warn（`require_tmp_space`），照提示换到大盘即可，脚本本身无改动：

```bash
export TMPDIR=$HOME/.cache/tmp && mkdir -p "$TMPDIR"
export TEXTURA_HARMONY_SNAP=$HOME/.cache/textura-harmony-snap
```

可覆盖的环境变量：`TEXTURA_CANGJIE_ROOT`、`TEXTURA_HARMONY_SNAP`、`DEVECO_HOME`、`CJ_HOME`、
`TEXTURA_OHOS_SDK`、`TEXTURA_OHOS_LIBCXX`。

`build_ohos.sh` 在编译前做四件必要的事（每一步都是踩过的坑，不要删）：

1. **把 aarch64 的 SDL3 放到绑定的 FFI 目录**：`third_party/cangjie-sdl/cjpm.toml` 里 `[ffi.c]` 写死
   `./.sdl3`，所以快照里把 x86_64 的两个库挪进 `.sdl3.host/`、把 `.sdl3-ohos/` 两个库拷进 `.sdl3/`。
   宿主编译用 `.sdl3`，鸿蒙编译用 `.sdl3-ohos`，同一份绑定源码两种架构。
2. **`crti.o` / `crtn.o`**：cjpm 给 `ld.lld` 的命令行上是**裸文件名**，而 `ld.lld` 只用 `-L/--sysroot`
   解析 `-l`，裸文件名只在**工作目录**里找。链接的工作目录是模块目录，所以脚本在 `harmony/host/`
   里放两个软链；仓库里不提交这两个文件。
3. **把 sysroot 戳进 `host/cjpm.toml`**：仓库里的 `link-option` 写的是占位符
   `-L__OHOS_SYSROOT__/usr/lib/aarch64-linux-ohos`，`cjpm.toml` 无法展开环境变量，所以脚本把
   `DEVECO_HOME` 推出的真实 sysroot 路径 sed 进**快照副本**，并断言占位符已消失。
   **换机器/换 SDK 只需重跑 `build_ohos.sh`，不要手改这个路径**（手改会留下下一台机器上失效的绝对路径）；
   直接 `cjpm build` 这个包不是受支持的用法。
4. **`cjv envsetup sts-1.2.0 --target ohos`**：唯一被支持的进入 target 工具链的方式（cjv 拒绝把 target
   变体设为 active）。

---

## 3. 工程结构

```
cangjie/harmony/
├── AppScope/
│   ├── app.json5                     bundleName / 版本 / 图标 / 应用名「织理 Textura」
│   └── resources/base/{element,media} app_name、分层图标（background+foreground）
├── build-profile.json5               signingConfigs（复用 PixCap .certs）+ products: default / unsigned
├── hvigorfile.ts                      appTasks
├── oh-package.json5 / code-linter.json5 / hvigor/hvigor-config.json5
├── entry/
│   ├── build-profile.json5           externalNativeOptions -> src/main/cpp/CMakeLists.txt（只编 libmain.so）
│   ├── hvigorfile.ts / oh-package.json5   entry 依赖两个 .d.ts 包（libSDL3.so、libark_interop_loader.so）
│   ├── src/main/module.json5         deviceTypes、landscape、无权限、pages
│   ├── src/main/ets/entryability/EntryAbility.ets   requireCJLib + provideArkTSObjects（§4.1）
│   ├── src/main/ets/pages/Index.ets  唯一 XComponent + 焦点收敛（§4.3）
│   ├── src/main/cpp/CMakeLists.txt   libmain.so 目标
│   ├── src/main/cpp/host_bootstrap.c C shim：SDL 入口转发到 libtextura_host.so（§4.1）
│   ├── src/main/cpp/types/libSDL3/   provideArkTSObjects 的 .d.ts
│   ├── src/main/cangjie/loader/      requireCJLib 的 .d.ts
│   ├── src/main/resources/           字符串、启动背景色、main_pages、图标
│   └── libs/arm64-v8a/               构建产物（staged，不提交，只存在于快照）
│       └── ohos/                     interop 运行时：loader 按名解析的 8 个库（§5.5）
├── host/                             仓颉宿主包 textura_host
│   ├── cjpm.toml                     output-type=dynamic；依赖 textura(../..) + cui + sdl；
│   │                                 link-option 里的 sysroot 是 __OHOS_SYSROOT__ 占位符（§2）
│   └── src/main.cj                   与桌面入口同一契约：AppStore -> ShellRuntime -> ShellHost ->
│                                     buildShell(host)，再交给 CUI-P01 逐帧驱动（§4.2）；@C 导出
│                                     SDL_App*（§4.3）；工作区/偏好落在应用沙箱（§4.5）
├── device-libs/                      设备提取库的落地目录（gitignored，不进快照，见 §7.2）
└── out/                              assemble_hap.sh 回拷的 HAP（gitignored）

cangjie/scripts/harmony/
├── _common.sh             路径/环境、快照同步、SDL 绑定就位、crt 软链、sysroot 戳入、
│                          platform_provided 判定、interop 库清单、profile 读取
├── build_ohos.sh          交叉编译 + 产物证据（架构、SONAME、.dynsym、NEEDED）
├── stage_libs.sh          NEEDED 闭包 + 运行时按名 dlopen 的必要库（loader / ohos/ / libsecurec）
├── assemble_hap.sh        hvigorw assembleHap（signed -> 失败则 unsigned）+ 载荷校验 +
│                          设备侧验收命令 + 「是否可安装」判定
└── set_signing_material.sh 把外部调试签名材料（p12/cer/p7b）写入 build-profile.json5（§7.1）
```

**桌面包与宿主包如何共享源码**：`harmony/host/cjpm.toml` 直接依赖 `textura = { path = "../.." }`，
即 `cangjie/` 这个 cjpm 工程本身。`cjpm` 以库的方式编译它（`src/main.cj` 的 `main()` 只产生一条
`unused function` 警告），于是宿主 `import textura.ui.*`、`import textura.shell.*` 拿到的就是桌面版
同一份源码——没有复制、没有分叉。副作用是宿主构建也要求 `src/` 全部包可编译（并行 worker 正在改
`src/views/**`、`src/ui/**` 时构建会跟着失败，见 §7.8）。

---

## 4. 启动链与运行时初始化

### 4.1 时序（谁在什么时候做什么）

```
ArkTS EntryAbility.onCreate          (ArkTS 线程，UIAbility 生命周期)
  1. requireCJLib("libtextura_host.so")
        libark_interop_loader.so：注册 host ArkVM -> 启动仓颉运行时 -> dlopen 宿主库
        （宿主库的包注册/静态初始化在此期间执行，见 4.2 的 CJ_MRT_PreInitializePackage）
        注意：运行时启动阶段 loader/系统侧会**按名**打开 interop 库，loader 里硬编码的搜索路径即
        <libs>/arm64-v8a/ohos（与 <libs>/arm64-v8a/runtime）。所以 ohos/ 必须随包落位，
        否则在第 1 步就断链，宿主库根本没有机会被 dlopen（§5.5）。
  2. sdl.provideArkTSObjects(ability, atManager, i18n.System, pointer.setPointerVisibleSync, ime)
        SDL 校验 argc==5，TakeOverUIAbility 覆写 ability 原型上的生命周期方法
        （因此 EntryAbility 里写 onWindowStageCreate 永远不会执行）
  3. SDL 自己 windowStage.loadContent("pages/Index")
        pages/Index 只有一个 XComponent({type: SURFACE, libraryname: 'SDL3'})
        系统 dlopen libSDL3.so，openharmony 视频后端接管 surface
  4. SDL 启动序列 dlopen("libmain.so") + dlsym("SDL_AppInit")
        libmain.so 是 C shim，只做转发 -> 宿主库的 SDL_AppInit
  5. 宿主 SDL_AppInit:
        字体注册 -> 沙箱目录（SDL_GetPrefPath）+ HOME 指向它
        -> AppStore(SystemClock) + store.load(<sandbox>/workspace.json)   [首启播种 demo]
        -> 还原偏好 route/theme -> ShellRuntime -> ShellHost(interactive=true)
        -> DesktopApp(themeByName(store.ui.theme)) -> beginHostedRun { buildShell(host) }
  6. XComponent OnFrame -> SDL_AppIterate -> app.step()   （唯一允许碰 surface 的线程）
  7. 退出：SDL_AppQuit -> app.endHostedRun()
```

### 4.2 运行时初始化：为什么选「ArkTS 侧 loader」而不是「C 里自己 init」

**结论：采用官方 loader 路线（ArkTS `requireCJLib`），C shim 不启动运行时。** 依据：

| # | 证据 | 命令/现象 |
|---|---|---|
| 1 | 宿主库**只**依赖一个运行时符号 `CJ_MRT_PreInitializePackage@CANGJIE`，没有任何 `CJ_MRT_CjRuntimeInit` / `CjRuntimeStart` 引用 | `llvm-readelf --dyn-syms libtextura_host.so \| grep CJ_MRT` → 1 行 |
| 2 | 该符号是 `UND`（未定义），由 `libcangjie-runtime.so` 提供 | `libcangjie-runtime.so` dynsym 含 `CJ_MRT_CjRuntimeInit@@CANGJIE`、`CJ_MRT_CjRuntimeStart@@CANGJIE`、`CJRegisterArkVMInRuntime@@CANGJIE` |
| 3 | 也就是说：`dlopen` 宿主库时它的包注册会**立刻调用运行时函数**，运行时必须已经起来 | 1+2 的组合结论 |
| 4 | loader 是 NAPI 模块：`nm_modname = ark_interop_loader`，用 `napi_define_properties` 导出 `requireCJLib`；`NEEDED` 仅 `libhilog_ndk.z.so`、`libace_napi.z.so`、`libc.so`（都是系统库） | `strings`/`readelf -d` |
| 5 | 反向方案（C 构造器里 `CJ_MRT_CjRuntimeInit/Start`）在参考项目上 SIGBUS：运行时启动会重建调用线程栈，而那是 ArkTS 自己的线程 | `PixCap-Cangjie/docs/scope/evidence/M0-host-chain.md`「Startup shim: progress and the SIGBUS」 |
| 6 | 因此 shim 保持纯 C、无仓颉依赖，可以早于运行时被加载，失败时返回 `SDL_APP_FAILURE` 而不是崩溃 | `entry/src/main/cpp/host_bootstrap.c` |

**为什么这次能走官方路线而参考项目当初走不通**：当时缺 `libark_interop_loader.so` 与 `ohos.ark_interop`
（只有 DevEco 仓颉插件里才有）。本机 `~/cangjie-ohos-sdk` 已带该 loader，且宿主包**源码层面**不
`import ohos.*`，所以不需要注册 `JSModule`。

但这**不等于**「不需要 interop 库」：loader 启动运行时之后仍会**按名**从
`<libs>/arm64-v8a/ohos` 打开 interop 运行时库，`stage_libs.sh` 必须把这些库随包落位（§5.5）。
源码不依赖 `ohos.*`（无编译期依赖）与运行时仍需要 `ohos/*.so`（有运行期依赖）是两件事，早期版本
把后一条漏掉了，HAP 少了整个 `ohos/` 目录而构建期完全看不出来。

**此结论仅构建期验证**：真机上还需确认 `requireCJLib` 返回后 `hilog` 出现
`Textura/HOST: Cangjie runtime started via requireCJLib`，且没有
`F CANGJIE-RUNTIME: Check failed: runtime != nullptr`。

> 若真机上 `requireCJLib` 失败：不要退回「C 里 init」——那会重演 SIGBUS。正确做法是抓
> `hilog -T CANGJIE-RUNTIME`，确认 SDK 版本与 `libark_interop_loader.so` 的来源（必须是 DevEco 仓颉插件
> 的同版本产物），并把 loader 的 `NEEDED` 与设备 `/system/lib64` 对齐。

### 4.3 逐帧驱动（CUI-P01）

CUI 的 `DesktopApp.run()` 是阻塞循环，不能用：XComponent `OnFrame` 是唯一能碰 surface 的线程。
`harmony/host/src/main.cj` 用 vendored CUI 的补丁 API：

```cangjie
app.beginHostedRun { buildShell(host) }                // 一次
@C SDL_AppIterate -> if (app.step()) { 0 } else { 1 }  // 每帧
@C SDL_AppQuit    -> app.endHostedRun()                // 一次
```

`SDL_AppIterate` 返回 `SDL_APP_SUCCESS(1)` 表示「UI 要求关闭」，不是错误。`SDL_AppEvent` 恒返回
`SDL_APP_CONTINUE`：CUI 自己轮询 SDL 事件队列，在这里再取一次会双重处理输入。

### 4.4 首帧前：字体与主题

- 主题：来自 `AppStore.ui.theme`（偏好里记住的值，否则 `THEME_LIGHT`），经 `themeByName(...)` 变成
  CUI `Theme` 同时用于 `DesktopApp(theme:)` 与 `buildShell` 内部——所以持久化的深色偏好在**第一帧**
  就是深色，不会先闪一下浅色。`texturaLight()/texturaDark()` 仍由 `themeByName` 间接使用。
- 字体：`harmony/host/src/main.cj` 的 `configureHostFont()` 先看沙箱 `<filesDir>/fonts/`（=`SDL_GetPrefPath`
  对应目录）里有没有 `.ttf/.ttc/.otf`，有就注册成 `textura-ui` 并设为默认；没有则退到系统字体族
  `HarmonyOS Sans SC`。CUI/SDL_ttf 只能打开真实文件路径，HAP 里 rawfile 的字体它看不到，所以不打包字体
  （见 §7.5 的 side-load 命令）。
- 窗口：`WindowSpec("织理 Textura", 1440, 900, supersample: 1)`。鸿蒙上 OPENHARMONY 后端会用 surface 尺寸
  覆盖它，这里的尺寸只是初值；`supersample: 1` 是为了不把每帧按 4 倍像素栅格化。

### 4.5 工作区与偏好：都落在应用沙箱（宿主契约 = 桌面契约）

宿主不再自造一个「gate 页面」，而是照 `cangjie/src/main.cj` 的壳层契约搭出真正的 AppShell：

```
AppStore(clock: SystemClock())          // clock 必须显式注入，AppStore 不会自己退回墙上时钟
  └─ store.load(<沙箱>/workspace.json)  // 缺失/空白 = 全新安装 -> core.data 播种 demo 并写回
ShellPreferences.load()                 // $HOME/.textura/ui-prefs.json（route/theme/最近项）
ShellRuntime(prefs, store)              // 自动保存状态机、toast 生命周期、偏好持久化
ShellHost(store, runtime, today, interactive=true, loadError, 1440, 900)
  └─ buildShell(host)                   // 侧栏/顶栏/七个视图/命令面板/快速收集
```

- **沙箱目录**：`ApplicationPaths.preferencePath("textura", "textura")`（= `SDL_GetPrefPath`，应用级
  files 目录 + app 标签）：

  | 视角 | 路径 |
  |---|---|
  | 应用内（`/data/storage/el2/...` 视图） | `/data/storage/el2/base/files/textura/` |
  | shell（`hdc shell ls`） | `/data/app/el2/100/base/com.ethancheung.textura/files/textura/` |
  | 工作区文件 | 上述目录下 `workspace.json` |
  | 偏好文件 | 上述目录下 `.textura/ui-prefs.json` |
  | 字体（side-load 目标） | `/data/app/el2/100/base/com.ethancheung.textura/files/fonts/` |

  注意模块级 `filesDir`（`UIAbility.context.filesDir` → `…/haps/entry/files`）是**另一个**目录；
  SDL 的 `OH_AbilityRuntime_ApplicationContextGetFilesDir` 才是应用级那个。
- **首启播种**：`store.load` 在文件缺失/空白时走 fresh-install 分支，`createSeedWorkspace` 生成 demo
  工作区并 `persist` 到该路径——所以真机第一次启动就能看到与桌面同一份内容，第二次启动是加载而不是重播种。
  父目录由宿主在 `prepareSandbox()` 里 `Directory.create(recursive: true)` 保证。
- **`HOME` 指向沙箱**：`ShellPreferences.load()` 用 `$HOME/.textura/ui-prefs.json`，设备上 `HOME`
  通常不可写或未设置；宿主在加载偏好之前 `setVariable("HOME", <沙箱>)`，路由/主题才能跨启动记住。
  写失败是**尽力而为**（`ShellPreferences.persist` 吞掉 I/O 异常），不会把 UI 拖挂。
- **`interactive = true`**：这是活窗口，自动保存、toast 计时、偏好持久化都开启；桌面的
  `--snapshot` 路径才传 `false`（它不允许写任何东西）。`today` 取本机日期（`store.anchorToday()`），
  加载失败时降级为 `"unknown"` 并让壳层渲染它自己的错误页。
- **workspace 写不进去时**：`StoreStatus.Ready` 但 `save()` 报 `SaveState.Error`，顶栏显示「保存失败」，
  文件权限/沙箱问题因此可见而不是静默丢数据。真机上排查：

  ```bash
  HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
  $HDC shell ls -l /data/app/el2/100/base/com.ethancheung.textura/files/textura/
  $HDC shell cat /data/app/el2/100/base/com.ethancheung.textura/files/textura/.textura/ui-prefs.json
  ```

---

## 5. 产物与打包闭包

### 5.1 HAP

| 项 | 值 |
|---|---|
| 路径 | `cangjie/harmony/out/entry-default-unsigned.hap`（快照内为 `entry/build/unsigned/outputs/default/`） |
| 大小 | **≈29.08 MB**（本轮实测 29 083 038 B，其中宿主库 13 260 920 B；同一 `src/**` 状态下连续两次构建字节数完全一致）。宿主库链接整份 `textura` 源码，`src/**` 有改动时体积会跟着浮动（本轮两次完整重建之间宿主库就多了约 40 KB）；另外 hvigor 打 zip 时写入时间戳，所以 **sha256 每次构建都不同**，别拿哈希当复现判据，用字节数 + 载荷清单。 |
| product | `unsigned`（`default` 签名失败，见 §7.1） |
| native 库 | **25 个** `libs/arm64-v8a/*.so`（顶层，= 23 个 staged + `libmain.so` + hvigor 补的 `libc++_shared.so`）+ **8 个** `libs/arm64-v8a/ohos/*.so`（interop，见 §5.5） |
| 其他 | `ets/`（`pages/Index` + `EntryAbility` 字节码）、`module.json`、`resources.index`、`resources/`、`pack.info`、`pkgContextInfo.json` |

宿主入口迁到 `buildShell(host)` 之后 HAP 从 ≈22.33 MB 涨到 ≈29.08 MB（宿主库从 7.0 MB → 12.6 MB，
因为它现在真的链接了侧栏/顶栏/七个视图/命令面板），这是**预期**的体积变化，不是回退。

`module.json` 关键项（已从 HAP 内解出核对）：`deviceTypes=["tablet","2in1","phone"]`、
`EntryAbility.orientation="landscape"`、`pages=$profile:main_pages`（`main_pages.json` 内为
`{"src":["pages/Index"]}`）、`requestPermissions` 缺省。

HAP 内不含任何签名材料（`*.p12/.p7b/.cer`）、不含 `PixCap` 字样、不含 `entry/libs` 之外的构建中间产物：
`stage_libs.sh` 只往 `entry/libs/arm64-v8a{,/ohos}` 写，`cangjie/.gitignore` 忽略这些目录与设备提取库。

### 5.2 `libmain.so`（C shim，CMake 产物）

```
ELF 64-bit LSB shared object, ARM aarch64, stripped, 6304 B
SONAME  libmain.so
NEEDED  libc.so
dynsym  FUNC GLOBAL DEFAULT SDL_AppInit / SDL_AppIterate / SDL_AppEvent / SDL_AppQuit
```

纯 C、只链 `dl`，因此可以在仓颉运行时之前被 `dlopen`。

### 5.3 `libtextura_host.so`（仓颉宿主）

```
ELF 64-bit LSB shared object, ARM aarch64          （快照内 ≈16.1 MiB / 16 841 056 B，HAP 内 stripped ≈12.6 MiB / 13 260 920 B）
dynsym: SDL_AppInit SDL_AppIterate SDL_AppEvent SDL_AppQuit textura_host_error textura_host_ready
SONAME: 空（cjpm 不写 soname；loader 按文件名 dlopen，不需要）
```

宿主库包含整个壳层（`AppStore` + `ShellRuntime` + 侧栏/顶栏/命令面板/快速收集 + 七个视图），所以它
比「只画一个 gate 页面」的早期版本大得多：后者 7.0 MB（HAP 内），现在 12.6 MB（stripped）。

`textura_host_error()` / `textura_host_ready()` 是给 shim 的诊断出口：仓颉 `println` 不进 hilog，启动异常
必须经 `SDL_Log` 才能看到。

### 5.4 载荷构成（`stage_libs.sh`）

载荷是两部分的并集，别的都不带：

**A. NEEDED 闭包 + 顶层按名加载的库（23 个）**

| 来源 | 库 |
|---|---|
| 本仓交叉构建 | `libtextura_host.so` |
| `third_party/cangjie-sdl/.sdl3-ohos` | `libSDL3.so`、`libSDL3_ttf.so` |
| ohos 工具链 runtime | `libcangjie-runtime.so`、`libboundscheck.so`、`libcangjie-std-{core,collection,collection.concurrent,convert,env,fs,io,math,overflow,random,sort,sync,time,unicode,binary}.so`（15 个） |
| 官方鸿蒙仓颉 SDK | `libark_interop_loader.so`（loader，ArkTS 侧 `requireCJLib` 按名 dlopen） |
| 官方鸿蒙仓颉 SDK | `libsecurec.so`（`libohos.*.so` 的 NEEDED，平台不提供） |
| 设备 `/system/lib64` 备份（参考项目留存） | `libc++.so`（见 §7.2） |

`libtextura_host.so` 自己的 NEEDED 里 `libcangjie-std-*` 是 **14 个**
（core、collection、collection.concurrent、convert、env、fs、io、math、overflow、random、sort、sync、
time、unicode）；第 15 个 `libcangjie-std-binary.so` 是另一个 std 库的传递依赖，被闭包自动带进来。
`overflow`/`random` 是宿主接上真实壳层（`AppStore` 的历史栈溢出检查与 id 生成）之后新增的。
统计口径：`llvm-readelf -d libtextura_host.so | grep NEEDED`（见 §10）。

**B. 运行时按名 dlopen 的库（`libs/arm64-v8a/ohos/`，8 个，见 §5.5）**

`stage_libs.sh` 每次都 `rm -rf` 重建 `ohos/`，所以从清单里删掉的库不会残留在旧快照里。

**设备自带、因此不打进 HAP 的 soname**（判定方式：存在于 HarmonyOS native sysroot，即公共 NDK 面）：

```
libc.so libace_napi.z.so libace_ndk.z.so libability_runtime.so libdeviceinfo_ndk.z.so
libhilog_ndk.z.so libhitrace_ndk.z.so librawfile.z.so libohcommonevent.so libohbattery_info.so
libohcamera.so libohimage.so libimage_receiver.so libnative_image.so libnative_buffer.so
libnative_display_manager.so libpasteboard.so libudmf.so
```

这些几乎全部来自 `libSDL3.so` 的 NEEDED（SDL 的 openharmony 后端直接用相机/音频/pasteboard 等系统 NDK）。
`stage_libs.sh` 用「在 sysroot 中存在 ⇒ 平台提供」的规则自动分类，所以新增依赖会显式报 unresolved，
而不是被静默漏掉。

**不打进 HAP 的其它东西**：

- `libc++_shared.so`（HAP 里却出现了 1 262 504 B）：hvigor 为带 CMake 目标的模块自动补的 NDK libc++。
  `libmain.so` 的 NEEDED 只有 `libc.so`，没有任何库引用它，是惰性负载。无害，但计入体积。
- 未用到的 `ohos.*` 模块库（`libohos.component.so`、`libohos.image.so`、`libohos.hilog.so`、…）与
  `libcj_*.z.so` 桥：本仓宿主包没有 `import ohos.*`，只带 interop 启动所需的 8 个（§5.5）。
  参考项目为了「完整性」把 60 个库整体塞进 HAP，本仓只带闭包 + 按名加载集合。

### 5.5 `libs/arm64-v8a/ohos/`：interop 运行时（**必须随包落位**）

`libark_interop_loader.so` 在 `requireCJLib` 里启动仓颉运行时，运行时阶段会**按名**打开 interop 库，
loader 二进制里硬编码的搜索路径是 `<libs>/arm64-v8a/ohos`（以及 `<libs>/arm64-v8a/runtime`）。
这一步发生在宿主库被 `dlopen` **之前**，所以：

- 缺 `ohos/` ⇒ 启动链在 §4.1 第 1 步就断，`libtextura_host.so` 根本没被加载，
  日志里看不到 `textura-shim` 的任何输出；
- `ohos/` 里的库不是宿主库的 NEEDED（`readelf -d libtextura_host.so` 里没有 `libohos.*`），
  所以「NEEDED 闭包」这类静态检查**永远发现不了**缺失——只能靠落位脚本 + HAP 内容断言。

落位的 8 个库、与真机可用参考 HAP 的一一对应（**HAP 内 8 个文件的 sha256 与参考 HAP 完全相同**；
hvigor 打包时对两者做了同样的 strip，所以与本机 SDK 里的文件相比体积略小，但 build-id 不变）：

| 库 | 来源目录 | HAP 内体积 |
|---|---|---|
| `libohos.ark_interop.so` | SDK `build/linux_ohos_aarch64_llvm/ohos` | 2 112 304 |
| `libohos.ark_interop_helper.so` | 同上 | 26 232 |
| `libohos.ffi.so` | 同上 | 621 312 |
| `libohos.so` | 同上 | 354 208 |
| `libohos.base.so` | 同上 | 123 456 |
| `libohos.ability.so` | 同上 | 671 440 |
| `libcj_ndk_ffi.z.so` | 同上 | 279 872 |
| `libohos_ark_interop_diff.z.so` | SDK `c_wrapper_diff/linux_ohos_aarch64_llvm` | 4 760 |

复核方式（任选其一）：

```bash
# a) 只看名字与数量（本仓 HAP，期望 8 行且与上表一字不差）
unzip -l cangjie/harmony/out/entry-default-unsigned.hap \
  | awk '$4 ~ /libs\/arm64-v8a\/ohos\/[^/]+\.so$/ {print $4}' | sort

# b) 与真机验证过的参考 HAP 逐文件比对（期望 8 行全是 IDENTICAL）
unzip -q entry-default-unsigned.hap 'libs/arm64-v8a/ohos/*' -d /tmp/texohos
unzip -q <PixCap 已签名 HAP> 'libs/arm64-v8a/ohos/*' -d /tmp/pixohos
cd /tmp/texohos/libs/arm64-v8a/ohos && sha256sum * \
  | while read -r h f; do
      [ "$h" = "$(sha256sum "/tmp/pixohos/libs/arm64-v8a/ohos/$f" | cut -d' ' -f1)" ] \
        && echo "IDENTICAL $f" || echo "DIFF $f"
    done
```

**这些库自己的 NEEDED 里还有 18 个 soname 不在 sysroot 里**（`libark_interop.z.so`、
`libark_interop_helper_ffi.z.so`、`libcj_bind_ffi.z.so`、`libcj_frontend_ohos.z.so`、`libcj_ability_ffi.z.so`、
`libcj_errormanager_ffi.z.so`、`libcj_image_ffi.z.so`、`libcj_bind_native.z.so`、`libappkit_native.z.so`、
`libabilitykit_native.z.so`、`libuiabilitykit_native.z.so`、`libutils.z.so`、`libcolor_manager.z.so`、
`libhilog.so`、`libohos.hilog.so`、`libohos.image.so`、`libohos.eventhub.so`、`libohos.window.so`）。
它们由设备 `/system/lib64/platformsdk` 提供——参考项目的 HAP 用同样的 8 个库在真机上跑通过，
但本机没有设备、也没有设备文件清单，**这一条只有真机能证实**（§7.4 的验证命令）。

---

## 6. 接上设备后的验收序列（5 步，按顺序做，第 3 步不过后面全是噪音）

`hdc` 不在 PATH 上，下面一律用绝对路径（与 `assemble_hap.sh` 打印的一致）：

```bash
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
```

### 第 0 步（前置条件，缺一不可）

1. **设备已连**：`$HDC list targets` 有输出（本机为空）。
2. **HAP 已签名且 profile 含本机 UDID**：`assemble_hap.sh` 结尾必须是 `STATUS: installable`。
   若是 `STATUS: NOT INSTALLABLE`，先按 §7.1 换签名材料，别往下走。
   要确认 profile 绑了哪台设备：`set_signing_material.sh` 会打印 profile 里的 `device-ids`。
3. **设备固件自带仓颉互操作系统库**——这是本 HAP 的硬前置，`libcj_environment.z.so` 与
   `libark_interop.z.so` 只能由固件提供，**不可能打进 HAP**（它们在系统命名空间里，且随固件版本走）：

   ```bash
   $HDC shell 'ls /system/lib64/platformsdk/ | grep -E "ark_interop|cj_environment"'
   ```

   预期至少两行：

   ```
   libark_interop.z.so
   libcj_environment.z.so
   ```

   （参考项目在 HarmonyOS 7.0 / API 26 的 2in1 上还额外看到 `libark_interop_helper_ffi.z.so`；
   `const.SystemCapability.ArkCompiler.CangjieInterop = true` 与之一致。）

   **缺失即不可运行**：仓颉运行时起不来，日志会出现
   `CANGJIE-RUNTIME ... Check failed: runtime != nullptr` 或 `ARKTS-INTEROP` 的 dlopen 失败，
   而不是任何 Textura 自己的日志。这种情况只能换设备/升级固件，改 HAP 无用。

### 第 1 步 安装

```bash
$HDC install -r cangjie/harmony/out/entry-default-signed.hap
```

预期：`install bundle successfully.`

失败对照：`9568289` = 声明了受限权限（本 HAP 无权限，不会出现）；
签名/profile 类错误（`9568345`、`code: 0x...` 校验失败）= profile 不是给
`com.ethancheung.textura` 的，或 UDID 不在 `device-ids` 里。

### 第 2 步 启动

```bash
$HDC shell aa start -a EntryAbility -b com.ethancheung.textura
```

预期：`start ability successfully.`

### 第 3 步 抓宿主日志（关键一步）

```bash
$HDC shell hilog | grep -E 'Textura/(HOST|FOCUS)|textura-shim|SDL/STARTUP|ARKTS-INTEROP|CANGJIE-RUNTIME'
```

> hilog 的 tag 是 **`Textura/HOST`** 与 **`Textura/FOCUS`**（含斜杠），所以 `hilog -T Textura`
> 匹配不到任何东西；要么用上面的 `grep`，要么 `$HDC shell hilog -T 'Textura/HOST'`（逐个 tag）。

预期出现的行（顺序即 §4.1 的顺序）：

```
Textura/HOST    Cangjie runtime started via requireCJLib
Textura/HOST    handing control from ArkTS to native SDL
SDL/STARTUP     ...（SDL 载入 libmain.so 与 pages/Index）
Textura/FOCUS   textura-focus request=appear#N ok=true
Textura/FOCUS   textura-focus event=onFocus
```

第 3 步通过后，宿主的 `SDL_AppInit` 已经把真实壳层跑起来了，所以还要看**沙箱里的文件**是否被创建
（这是「工作区播种 + 偏好持久化」是否真的工作过的唯一证据，比日志可靠）：

```bash
$HDC shell ls -l /data/app/el2/100/base/com.ethancheung.textura/files/textura/
$HDC shell 'head -c 200 /data/app/el2/100/base/com.ethancheung.textura/files/textura/workspace.json'
```

预期：首次启动后出现 `workspace.json`（demo 工作区文档），改动路由/主题后出现 `.textura/ui-prefs.json`。
若 `workspace.json` 不存在而界面正常，说明 `store.load` 走了内存分支——回到 §4.5 检查沙箱写权限。

**不可出现**的行（出现了就是本节的已知风险命中）：

| 日志 | 含义 | 去看 |
|---|---|---|
| `F CANGJIE-RUNTIME: Check failed: runtime != nullptr` | `requireCJLib` 没生效 / 设备缺互操作系统库 | §6 第 0 步第 3 条 |
| `E ARKTS-INTEROP: cj module must dependent on ohos_ark_interop` | 宿主库与运行时的工具链代际不匹配 | §7.3（本仓最可能的失败点） |
| `[textura-shim] dlopen libtextura_host.so failed` | 库没进 HAP / 命名空间问题 | §9 |
| `[textura-shim] host SDL_AppInit failed: <reason>` | 宿主启动异常，`reason` 由仓颉侧给出（例如沙箱不可写、字体注册失败） | §9、§4.5 |
| `CANNOT LINK EXECUTABLE ... libc++.so` | `std::__h` ABI 不匹配 | §7.2 |
| `dlopen failed: library "libcangjie-trace.so" not found` | 已知风险 R5，通常无害 | §7.4 |

### 第 4 步 首帧截图

```bash
$HDC shell snapshot_display -f /data/local/tmp/textura.jpeg
$HDC file recv /data/local/tmp/textura.jpeg /tmp/textura.jpeg
```

屏幕应是暖纸色的 **AppShell**：左侧栏（七个路由）+ 顶栏 + Dashboard 首页内容，而不是 ArkUI 白屏、
也不是空窗口。中文字形缺失时是方框（§7.5 的 side-load 补救），不是白屏。

### 最可能失败点排序（按概率）

1. **第 1 步**：签名材料（本机根本没有 `com.ethancheung.textura` 的 profile），与 HAP 内容无关；
2. **第 3 步**：`cj module must dependent on ohos_ark_interop`（§7.3，本仓宿主是 cjc 1.2.0 时代产物）；
3. **第 3 步**：`libc++.so` 的 `std::__h` ABI（§7.2，用的是从设备拉出来的库）；
4. **第 3 步**：`ohos/` 里 interop 库的 18 个 NEEDED 在设备 `platformsdk` 中缺失（§5.5 末段）；
5. **第 3 步之后**：沙箱不可写（`workspace.json` 没生成、顶栏「保存失败」）——这是新宿主入口引入的
   第一类**业务**失败面，构建期只能验证到「路径解析 + 建目录」为止。

---

## 7. 已知风险

### 7.1 签名：`00303074`，当前 HAP 不可安装（阻塞项，**需要用户提供材料**）

`build-profile.json5` 的 `product=default` 复用参考项目的调试材料
（`PixCap-Cangjie/.certs/pixcapt-debug/`，`keyAlias=pixcapt-debug`）。hvigor 在 `SignHap` 阶段直接拒绝：

```
00303074 Configuration Error
Error Message: The bundleName in app.json5/hvigorfile.ts does not match the bundleName
               in the generated SigningConfigs
```

原因：该 p7b 是 `type:debug` 的 profile，`bundle-name` 字段为 `com.ethancheung.pixcapt`，且
`debug-info.device-ids` 只含参考设备那一个 UDID。签名工具比对 bundleName，不符即停。

因此本仓提供两个 product：`default`（签名，本机必然失败）与 `unsigned`（同模块同 SDK，无签名材料）。
`assemble_hap.sh` 先试 signed，命中 `00303074` 后自动回落 unsigned 并把错误原文打印出来，**并在结尾
明确打印产物是否可安装**：

- `STATUS: NOT INSTALLABLE`：不给 `hdc install` 命令（unsigned 产物装不上，给了只会误导）；
- `STATUS: installable`：打印设备侧 4 条命令，全部带 hdc 绝对路径，**第 1 条是固件互操作库自检**
  （`ls /system/lib64/platformsdk/ | grep -E "ark_interop|cj_environment"`），之后才是
  `install / aa start / hilog`。

并且现在**在构建开始前**就把 profile 的 bundleName 与 `AppScope/app.json5` 对比打印，
00303074 不用等一次完整构建才发现：

```
==> signing profile: .../PixCap-Cangjie/.certs/pixcapt-debug/PixCaptDebugCertDebug.p7b
==>      profile bundle-name=com.ethancheung.pixcapt  app bundleName=com.ethancheung.textura
warn: the profile's bundleName does not match com.ethancheung.textura, so product=default cannot be signed here
```

**本机可行性核查（结论：不可，缺账号 + 设备 UDID）**

| 路线 | 结论 | 证据 |
|---|---|---|
| `devecocli signature generate` | ❌ 需要登录 + 需要设备 | 命令存在（`devecocli signature generate [--team-id] [--force]`）；设置 `DEVECO_CLI_CLT_PATH=<clt>` 后直接返回 `Failed to automatically generate signatures. Run devecocli auth login to sign in.`；`devecocli auth status` → `Not logged in`；`devecocli device list` → `No active devices`（本机无设备，UDID 也拿不到） |
| `~/.ohos/config` 已有材料 | ❌ 没有本 bundle | 该目录全部 10 个 p7b 覆盖的 bundleName 是：`com.ethan.metricstudio`、`com.ethancheung.metricstudio`、`com.ethancheung.harmodrive`、`com.ethancheung.moduse`、`com.ethancheung.ohclashparty`、`com.ethancheung.pixcapt`、`com.example.cangjiehnp`，**没有 `com.ethancheung.textura`**（`strings *.p7b \| grep -o '"bundle-name":"[^"]*"'`） |
| `hap-sign-tool.jar`（`sdk/default/openharmony/26/toolchains/lib/`） | ⚠️ 工具在，但救不了 | 有 `sign-app` / `sign-profile` / `generate-keypair` 等子命令，可以本地签名；但 profile 的签名链到 AGC 根、内容是 AGC 签发的 JSON（bundleName + device-ids）。自己 `generate-profile-cert` + `sign-profile` 造出来的 profile 设备不认，安装期校验失败。它只能用于「材料齐了之后手工签」，而 hvigor 已经会调它 |

**需要你提供**（两样，缺一不可）：

1. 设备 UDID（连上设备后 `$HDC shell bm get --udid`，部分固件用 `bm get -u`；或 DevEco Studio 的
   设备管理器里看）；
2. 为 `com.ethancheung.textura` + 该 UDID 签发的调试 profile（`.p7b`），以及与之配对的
   `.p12`（keystore，含私钥）与 `.cer`（证书）。
   最省事的做法是在有 GUI/账号的机器上跑一次 `devecocli auth login` +
   `devecocli signature generate`，它会把材料写进 `build-profile.json5`；只需把
   `~/.ohos/config/default_<bundle>*.{p12,cer,p7b}` 这三个文件拷过来。

材料到手后**一条命令换掉**（全部是参数，脚本里没有写死任何路径）：

```bash
cangjie/scripts/harmony/set_signing_material.sh \
  --store-file   <keystore.p12> \
  --key-alias    <alias> \
  --cert         <certificate.cer> \
  --profile      <debug-profile.p7b> \
  [--store-password <加密串>] [--key-password <加密串>] [--dry-run]

cangjie/scripts/harmony/assemble_hap.sh    # 结尾应变成 STATUS: installable
```

脚本会先校验：文件存在且非空；profile 的 `bundle-name` == `AppScope/app.json5` 的 bundleName
（不符直接报错退出，不写文件）；打印 profile 里授权的 `device-ids`。`--dry-run` 只校验不落盘。

### 7.2 `libc++.so` 的 ABI 与来源（阻塞真机加载，已 workaround）

`libcangjie-runtime.so` 的 NEEDED 含 `libc++.so`，而它要的是导出 `std::__h` 命名空间的那份
（例：`_ZNSt3__h15recursive_mutex4lockEv`）。本机两条常规来源都不满足：

- ohos 工具链：只有 `third_party/mingw/lib/libc++.a`，没有 aarch64-ohos 的 `libc++.so`；
- DevEco SDK sysroot / `hms/native/BiSheng/...`：导出 `std::__n1`，ABI 不符。

`stage_libs.sh` 因此按以下顺序取，并对每个候选跑 `readelf --dyn-syms` 校验 ABI 后才复制：

1. `$TEXTURA_OHOS_LIBCXX`
2. `cangjie/harmony/device-libs/arm64-v8a/libc++.so`（**推荐的落地位置**，见下）
3. `PixCap-Cangjie/entry/libs/arm64-v8a/libc++.so`（参考项目里那份设备备份）

统计口径与实测值（针对 stage 的这份 `libc++.so`，1 282 896 B）：

```bash
RE=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/native/llvm/bin/llvm-readelf
L=cangjie/harmony/device-libs/arm64-v8a/libc++.so
"$RE" --dyn-syms "$L" | awk '$4=="FUNC" && $7!="UND"' | grep -c 'St3__h'   # 1405 个已定义的 std::__h FUNC
"$RE" --dyn-syms "$L" | grep -c 'St3__h'                                   # 1893 行（含 OBJECT/其他类型）
"$RE" --dyn-syms "$L" | awk '$7=="UND"' | grep -c 'St3__h'                 # 0 行（没有未定义引用）
"$RE" --dyn-syms "$L" | grep -c '_ZNSt3__h15recursive_mutex4lockEv'        # 1（ABI 探针）
```

> 早期版本写的「1055 个」是旧口径/旧文件留下的错误数字，以本节的 **1405（已定义 FUNC）/ 1893（全部
> dynsym 行）** 为准，统计命令如上，谁都能复算。

风险：那是**从设备 `/system/lib64` 拉出来的系统库**，随 HAP 分发需要法务确认；正解是等仓颉 ohos 工具链
自带匹配的 libc++。**设备侧重新取一份**（落到工作树里被 gitignore 的目录，不要落到快照里——快照每次
构建都会被 `rsync --delete` 重建）：

```bash
$HDC file recv /system/lib64/libc++.so cangjie/harmony/device-libs/arm64-v8a/libc++.so
```

`cangjie/.gitignore` 已忽略 `harmony/device-libs/`、`harmony/entry/libs/`、`harmony/out/` 与
`harmony/host/{crti.o,crtn.o}`：设备提取的系统库**不得入库**。

### 7.3 工具链代际错配（**高风险，本仓最可能的真机失败点**）

本仓的组合是：

- 宿主库：cjv `sts-1.2.0`（**cjc 1.2.0**）交叉编译，`libtextura_host.so` 的 `.cjo` 里没有
  `ohos_ark_interop` 依赖声明；
- loader 与 interop：DevEco 仓颉 SDK **5.0.5.165**（cjc 0.53.20 时代）。

参考项目把**同一个组合**跑到了真机上并失败（`PixCap-Cangjie/docs/scope/evidence/M0-runtime-bootstrap.md` §1/§5）：

```
I CANGJIE-RUNTIME: Cangjie runtime started.
I PixCap/HOST: Cangjie runtime started via requireCJLib
I PixCap/HOST: handing control from ArkTS to native SDL
E ARKTS-INTEROP: cj module must dependent on ohos_ark_interop
I SDL/APP: SDL_AppInit said SDL_APP_FAILURE! Terminating!
```

即：**运行时起来了，但系统库 `libark_interop.z.so` 拒绝加载没有 `ohos_ark_interop` 依赖声明的仓颉
模块**，`dlopen` 返回 NULL，`SDL_AppInit` 直接失败。参考项目的判断是「统一到鸿蒙仓颉工具链」，
最终在同一个设备上拿到成功（`M0-exit-font-and-live-window.md` §1）：

```
I PixCap/HOST: Cangjie runtime started via requireCJLib
I PixCap/HOST: handing control from ArkTS to native SDL
I SDL/APP: SDL_AppInit said continue! We are live!
```

两侧证据并列的结论：**loader 能启动运行时 ≠ 宿主库会被接受**。本仓目前的证据只到「运行时能被启动」
（§4.2 的符号/依赖分析），没有「宿主库被 `libark_interop.z.so` 接受」的任何证据，而这正是参考项目
卡住的那一步。

- 风险等级：**高**（构建期无法排除；命中后表现为 `cj module must dependent on ohos_ark_interop`，
  与 HAP 内容、签名、权限都无关）。
- 触发条件：设备上用 `requireCJLib` 加载一个 `.cjo` 未声明 `ohos_ark_interop` 的仓颉动态库。
- 正解（超出本次打包修复范围，需要协调者批准改宿主包契约）：把宿主从
  `cjc 1.2.0 + 手工 C ABI` 迁到鸿蒙仓颉工具链（`cangjie-linux-x86-ohos-*.zip` 那一套），让宿主
  `import ohos.ark_interop` 并在 `.cjo` 里声明 `ohos_ark_interop`，然后重建 cangjie-sdl bindings → CUI → 宿主。
- 本轮的处置：不隐瞒、不假装已解决；把它写进 §6「最可能失败点」第 2 条，命中时按上面的日志特征判定，
  而不是去改 HAP 内容。

### 7.4 R5：`libcangjie-trace.so` 无来源（已知风险，不影响启动）

`libcangjie-runtime.so` 里带两个字符串（`strings libcangjie-runtime.so | grep cangjie-trace`）：

```
libcangjie-trace.so
%s/runtime/lib/%s_cjnative/libcangjie-trace.so
```

也就是说运行时会**按名 `dlopen`** 一个当前所有工具链都没有的 trace 库（`sts-1.2.0` 的 runtime 目录、
DevEco SDK、参考项目 HAP 里都没有）。它是调试/追踪用途：

- 触发条件：运行时初始化或 `CJ_MRT_*` 起步阶段尝试加载 trace 支持（每次进程启动都会试）；
- 预期影响：`dlopen` 失败 → 只丢 trace 能力，正常运行路径不需要它；
- 若真机上因此崩溃（而不是打印失败），说明这个版本的运行时把 trace 当硬依赖，属于**未知项**；
- 验证命令（设备侧）：

  ```bash
  $HDC shell hilog | grep -iE 'cangjie-trace|libcangjie-trace'
  # 期望：没有输出，或只有一行 dlopen 失败的 warn；不期望 SIGABRT / SIGSEGV
  $HDC shell 'ls /system/lib64/platformsdk/ /system/lib64/ | grep -i trace'
  # 确认固件也没提供（固件提供了就说明是版本差异，可忽略本风险）
  ```

### 7.5 中文字形：没打包字体

HAP 内没有字体文件。`configureHostFont()` 会优先用沙箱里的字体，否则用系统族 `HarmonyOS Sans SC`。
若真机出现方框（CUI 缺字回退失败），side-load 一个 CJK 字体：

```bash
# 目标是「应用级 files 目录」下的 fonts/（SDL_GetPrefPath("textura","fonts") 的返回值），
# 不是模块级的 …/haps/entry/files（两者不是同一个目录，见 §4.5）：
#   shell 视角  /data/app/el2/100/base/com.ethancheung.textura/files/fonts/
#   应用内视角  /data/storage/el2/base/files/fonts/
FONT_DIR=/data/app/el2/100/base/com.ethancheung.textura/files/fonts
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
$HDC shell mkdir -p "$FONT_DIR"
$HDC file send NotoSansCJK-Regular.ttc "$FONT_DIR/NotoSansCJK-Regular.ttc"
```
放好重启应用即可（首帧前注册，热重载不需要）。这是可复现的补救路径，不是「已支持」的声明。
验证是否被宿主看见：

```bash
$HDC shell ls -l /data/app/el2/100/base/com.ethancheung.textura/files/fonts/
# 有 .ttf/.ttc/.otf 就会被注册成 textura-ui 并设为默认；没有则退回 HarmonyOS Sans SC
```

### 7.6 运行时初始化：仅构建期验证

见 §4.2。真机上的三个未知点：ArkVM 注册是否接受当前 loader 版本；宿主库在应用命名空间里能否解析
`libSDL3.so`（两者都在 `libs/arm64-v8a`，与参考项目同构）；`beginHostedRun` 的线程断言
（`scheduler.assertOwnerThread()`）是否与 XComponent 回调线程一致。三者都只在设备上才能确认。

### 7.7 权限：一个都不声明

`module.json5` 的 `requestPermissions` 为空是刻意的：**声明的受限权限会触发安装期校验**，参考项目因此
被 `9568289 install failed due to grant request permissions failed` 挡住过。本轮功能不需要任何权限。

### 7.8 与并行 worker 的耦合

宿主包依赖整个 `textura` cjpm 工程，所以任何 `src/views/**`、`src/ui/**`、`src/shell/**` 的中间状态都会让
宿主交叉编译失败。这**不是**鸿蒙链路的问题，重跑 `build_ohos.sh` 即可。历次实测：

- `src/views/sop/logic/model.cj` 文档注释里的 `src/modules/sop/*` 意外开启了嵌套块注释（Cangjie 支持
  嵌套 `/* */`）；
- `src/ui/modal.cj`、`src/ui/paint.cj`、`src/views/gtd/gtd_metrics.cj`、`src/views/okr/okr_page.cj`、
  `src/shell/capture.cj`、`src/ui/tokens.cj` 的编辑中途状态；
- **契约变更（已收口）**：`src/shell/appshell.cj` 把入口从 `buildGate(GateModel, Theme)` 换成了
  `buildShell(ShellHost)`，`GateModel` / `buildGate` 已从 `src/` 整体消失
  （`grep -rn 'buildGate\|GateModel' src/` 无结果）。`harmony/host/src/main.cj` 当时仍按旧契约调用，
  宿主包一度**无法从零重建**：

  ```
  error: undeclared type name 'GateModel'          harmony/host/src/main.cj:134
  error: undeclared identifier 'buildGate'         harmony/host/src/main.cj:163
  ```

  现已迁移到与桌面入口同一契约（`AppStore(clock:)` → `ShellRuntime` → `ShellHost` → `buildShell`，
  见 §4.5），从零构建已通过。**再出现同类断裂时的判据与处置**：

  1. 先看是不是 `src/shell`/`src/core` 的公共 API 变了：`grep -n "public class ShellHost" -A 20
     src/shell/appshell.cj`、`grep -n "public func buildShell" src/shell/appshell.cj`、
     `grep -n "public init" -A 6 src/core/data/store.cj`；
  2. 以 `cangjie/src/main.cj` 为唯一权威用法**照抄**连接方式（它是每个 worker 都在跑的门禁路径，
     永远不会停在半改状态）；
  3. 宿主独有的只有三件事：沙箱路径、`interactive = true`、`today` 用本机日期（§4.5）。
  不要在宿主里复制壳层逻辑，也不要在宿主里另造入口——那是这次失败的成因。

若长期需要隔离，可把 `textura.ui`/`textura.shell` 拆成独立 cjpm 包、让宿主只依赖它们（需要协调者改
`docs/STRUCTURE.md` 的包契约）。

### 7.9 其它构建期注意事项

- `libtextura_host.so` 无 SONAME；loader 按文件名 `dlopen`，无影响，但不要改成互相 NEEDED 的关系。
- hvigor 会自动往 HAP 塞 `libc++_shared.so`（NDK 版本，SONAME 不同），目前是惰性负载（§5.4）。
- `.sdl3-ohos` 的两个库是参考项目**打完 4 个 SDL 补丁后**的构建产物（事件保留、uinput 事件、
  窗口尺寸跟随 XComponent、指针/surface 同步）。CUI 依赖其中「事件保留」那条（它自己轮询队列），
  所以不能随意替换成上游原版。
- `libs/arm64-v8a/ohos/` 由 `stage_libs.sh` 每次 `rm -rf` 重建；不要手工往里放库，
  加库请改 `_common.sh` 的 `OHOS_INTEROP_LIBS`（`assemble_hap.sh` 会断言数量与关键成员）。

---

## 8. 何时需要重编 SDL3 / SDL3_ttf（默认不需要）

本轮遵守「不重修 SDL 源码，用 vendored `.sdl3-ohos`」。只有下面两种情况才需要重编：

1. 设备上出现 SDL 层的具体 bug，且判定必须升级 pin；
2. `.sdl3-ohos` 与 `libSDL3_ttf.so` 缺失或架构不符（`file` 不是 aarch64）。

重编步骤（参考项目脚本，**不要**在本仓改 `third_party/SDL` 源码；需要补丁先报协调者）：

```bash
CLT=$HOME/deveco-cli-stable/command-line-tools
SR=$CLT/sdk/default/openharmony/native
$SR/build-tools/cmake/bin/cmake -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$SR/build/cmake/ohos.toolchain.cmake \
  -DCMAKE_BUILD_TYPE=Release -DOHOS_COMPATIBLE_SDK_VERSION=16.0.0 \
  -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
  -DCMAKE_PLATFORM_NO_VERSIONED_SONAME=1 <SDL 源码>
ninja
# SDL3_ttf 同理，加 -DSDLTTF_VENDORED=ON -DSDLTTF_HARFBUZZ=OFF -DSDLTTF_PLUTOSVG=OFF -DSDLTTF_SAMPLES=OFF
# -DCMAKE_PLATFORM_NO_VERSIONED_SONAME=1 是硬要求：否则 SONAME 带版本号，在鸿蒙命名空间里按名字加载失败。
```

产物复制到 `cangjie/third_party/cangjie-sdl/.sdl3-ohos/`，然后重跑 §2 的三条命令。

---

## 9. 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `error: unknown argument '-B<path>'` + `cannot open crti.o` | cjpm 把 `link-option` 交给 `ld.lld`；`-B` 是 clang driver 选项，且裸 `crti.o` 只在工作目录里找 | 只在 `link-option` 里给 `-L`；靠 `build_ohos.sh` 放的 `crti.o/crtn.o` 软链 |
| `ld.lld: error: cannot open .../__OHOS_SYSROOT__/...` | `host/cjpm.toml` 的 sysroot 占位符没被替换 | 用 `build_ohos.sh`（不要直接 `cjpm build`）；换机器后重跑它（§2 第 3 条） |
| `failed to compile package textura.ui/views.*` | 并行 worker 正在改 `src/**` | 重跑 `build_ohos.sh`；与本链路无关 |
| `Error: root package 'textura_host' imports package 'cui' ... not added as a dependency` | 宿主直接 import 了 `cui`/`sdl` | `harmony/host/cjpm.toml` 必须显式声明这两个依赖 |
| hvigor `00303074` | 签名 profile 的 bundleName 不符 | §7.1；脚本会在构建前就打印 profile/应用的 bundleName，并自动回落 `product=unsigned` |
| hvigor `9568289`（安装期） | 声明了受限权限 | 不声明权限（§7.7） |
| 设备上 `dlopen libtextura_host.so failed` | 库没进 HAP 或 loader 名字不符 | `unzip -l <hap> \| grep textura_host`；确认 `EntryAbility.ets` 的 `CANGJIE_HOST_LIB` |
| 设备上 `dlopen failed: library "libohos.ark_interop.so" not found` / `cj module must dependent on ohos_ark_interop` | `ohos/` 没落位，或宿主与运行时工具链代际不匹配 | 先确认 HAP 里有 8 个 `libs/arm64-v8a/ohos/*.so`（§5.5）；都在还报后一种日志 → §7.3 |
| 设备上缺 `libc++.so` | §7.2 | stage 正确的 ABI 或从设备拉取（落到 `harmony/device-libs/`） |
| `dlopen ... libcangjie-trace.so` | 已知风险 R5（运行时按名加载缺失的 trace 库） | §7.4；通常无害 |
| 中文方框 | 无 CJK 字体（§7.5） | side-load 字体到沙箱 `fonts/` |
| `hilog -T Textura` 什么都抓不到 | hilog 的 tag 是 `Textura/HOST` / `Textura/FOCUS`（含斜杠） | 用 `hilog \| grep -E 'Textura/(HOST\|FOCUS)'`（§6 第 3 步） |
| 键盘快捷键无效 | XComponent 没拿到焦点 | 保留 `focusable/defaultFocus/focusOnTouch` + 有限次 `requestFocus` 重试；看 `textura-focus` 日志 |

---

## 10. 命令速查

```bash
cd /home/ethan/CodeRepo/sandbox/Textura/cangjie

./scripts/harmony/build_ohos.sh [--no-sync]    # 宿主库 + 符号/架构/NEEDED 证据
./scripts/harmony/stage_libs.sh                # 闭包 + loader + ohos/ interop -> entry/libs/arm64-v8a
./scripts/harmony/assemble_hap.sh [--no-sync]  # HAP -> harmony/out/ + 载荷校验 + 可安装性判定
./scripts/harmony/set_signing_material.sh --help   # 换签名材料（§7.1）

# 直接看快照里的中间产物（readelf 用 SDK 自带的 llvm-readelf，PATH 里没有）
RE=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/native/llvm/bin/llvm-readelf
L=/tmp/cj-harmony/cangjie/harmony/entry/libs/arm64-v8a
ls -l "$L" "$L/ohos"
"$RE" --dyn-syms "$L/libtextura_host.so" | grep SDL_App
"$RE" -d "$L/libtextura_host.so" | grep NEEDED
"$RE" -d "$L/libtextura_host.so" | grep NEEDED | grep -c libcangjie-std   # 12（§5.4）

# HAP 载荷（ohos/ 必须 8 个，与参考 HAP 对齐）
unzip -l cangjie/harmony/out/entry-default-unsigned.hap \
  | awk '$4 ~ /libs\/arm64-v8a\/ohos\/[^/]+\.so$/ {print $4}' | sort

# 设备侧（hdc 不在 PATH 上）
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
$HDC list targets
$HDC shell 'ls /system/lib64/platformsdk/ | grep -E "ark_interop|cj_environment"'
$HDC install -r cangjie/harmony/out/entry-default-signed.hap
$HDC shell aa start -a EntryAbility -b com.ethancheung.textura
$HDC shell hilog | grep -E 'Textura/(HOST|FOCUS)'
```
