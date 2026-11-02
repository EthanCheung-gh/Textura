# 鸿蒙 HAP 工程（CUI on SDL + 仓颉宿主）

本目录是 Textura 仓颉版的 HarmonyOS 应用壳：ArkTS 只负责给出一个 XComponent surface 并把仓颉运行时点起来，
真正的界面由 CUI 在 surface 里逐帧绘制。

完整说明（从零复现、pin、运行时初始化依据、打包闭包、验收命令、已知风险）见
**[`../docs/HARMONY.md`](../docs/HARMONY.md)**。这里只留最短索引。

## 目录

| 路径 | 作用 |
|---|---|
| `AppScope/` | bundleName `com.ethancheung.textura`、应用名「织理 Textura」、分层图标 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `requireCJLib("libtextura_host.so")` → `sdl.provideArkTSObjects(...)` |
| `entry/src/main/ets/pages/Index.ets` | 唯一页面：一个 `XComponent({type: SURFACE, libraryname: 'SDL3'})` + 焦点收敛 |
| `entry/src/main/cpp/host_bootstrap.c` | `libmain.so` 的 C shim，把 SDL 入口转发给仓颉宿主库 |
| `entry/src/main/cpp/CMakeLists.txt` | 只编 `libmain.so`（不重编 SDL） |
| `host/` | 仓颉宿主包 `textura_host`：与桌面入口同一契约（`AppStore` → `ShellRuntime` → `ShellHost` → `buildShell`），`@C` 导出 `SDL_App*`，用 CUI-P01 逐帧驱动；工作区/偏好落应用沙箱 |
| `entry/libs/arm64-v8a/` | 构建产物（staged，只存在于快照，不提交） |
| `entry/libs/arm64-v8a/ohos/` | interop 运行时（8 个库）：loader 启动仓颉运行时后按名解析，**必须随包落位** |
| `device-libs/` | 设备提取库（如 `libc++.so`）的落地目录，gitignored，设备侧系统库不得入库 |
| `out/` | `assemble_hap.sh` 回拷的 HAP（不提交） |

## 四条命令

```bash
cd cangjie
./scripts/harmony/build_ohos.sh
./scripts/harmony/stage_libs.sh
./scripts/harmony/assemble_hap.sh
```

构建只在快照（默认 `/tmp/cj-harmony`）里跑，共享工作树不会被写入。

换签名材料（拿到 `com.ethancheung.textura` 的调试 profile 之后）：

```bash
./scripts/harmony/set_signing_material.sh \
  --store-file <store.p12> --key-alias <alias> --cert <cert.cer> --profile <profile.p7b>
```

## 当前状态

- 交叉编译（**从空快照可重建**）、`assembleHap`、HAP 内容校验（含 `libs/arm64-v8a/ohos/` 的 8 个
  interop 库）：已通过。HAP ≈29 MB，宿主库 12.6 MB（含整套壳层与七个视图）。
- 宿主入口已迁到 `buildShell(ShellHost)`（与 `cangjie/src/main.cj` 同契约）：首启在应用沙箱里播种
  demo 工作区，路由/主题偏好也存沙箱，详见 `docs/HARMONY.md` §4.5。
- 产物可安装性由 `assemble_hap.sh` 结尾显式判定：现在打印 **`STATUS: NOT INSTALLABLE`**
  （unsigned；本机没有 `com.ethancheung.textura` 的调试 profile，hvigor 报 `00303074`）。
- 真机安装/启动：**待设备（UDID）+ 待该 bundle 的调试 profile + 待确认固件自带仓颉互操作系统库**。
  见 `docs/HARMONY.md` §6（前置条件与验收序列）与 §7.1（签名）。

## 不要做的事

- 不要在 `host_bootstrap.c` 或任何 C 代码里调用 `CJ_MRT_CjRuntimeInit/CjRuntimeStart`：那会让运行时在
  ArkTS 线程上重建栈并 SIGBUS。运行时只由 ArkTS 侧 `requireCJLib` 启动。
- 不要手工往 `entry/libs/arm64-v8a/ohos/` 放库：`stage_libs.sh` 每次重建该目录，加库改
  `scripts/harmony/_common.sh` 的 `OHOS_INTEROP_LIBS`。
- 不要把设备提取的系统库（`libc++.so` 等）提交进仓库：放 `device-libs/`，它已被 `cangjie/.gitignore` 忽略。
- 不要在 `host/cjpm.toml` 里写死本机 sysroot 路径：占位符由 `build_ohos.sh` 在构建期替换。
- 不要在 `Index.ets` 里处理按键（`onKeyEvent` 会吞掉事件，必须让 ArkUI → SDL → CUI 这条链吃到）。
- 不要改 `third_party/**`；需要补丁先按 `docs/STRUCTURE.md` 的流程报批。
