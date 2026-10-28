# HANDOFF · Textura 仓颉重写（CUI + HarmonyOS）

> 写给下一个接手的人（或下一个会话）。**先读这一页**，再按 §9 挑一个入口。所有数字都是实测的，未验证的会写「未验证」，不要把它们当成已完成。

## 1. 一句话现状

七个视图 + 外壳在仓颉/CUI 上完整可跑，像素门禁 14/14，签名 HAP 已装上华为笔记本（MateBook，HarmonyOS 6，外接屏 2880×1620）。
**唯一阻塞项**：OKR 页底「新增关键结果」prompt 打开后 10–90 秒必崩，根因在**仓颉运行时 GC（CopyCollector forward 阶段）**，应用侧已做「去泵」但不足以规避（见 §6）。

## 2. 仓库与分支

| 项 | 值 |
|---|---|
| 仓库 | `/home/ethan/CodeRepo/sandbox/Textura` |
| 分支 | `feat/cangjie-rewrite`（新目录 `cangjie/`，Web 原版在根目录不动） |
| HEAD | `c0bbeeb perf(okr): stop re-measuring the same text advance on every layout` |
| 工作树 | clean（`build-profile.json5` 必须保持未修改状态，见 §7） |
| 测试 | 根包 `cjpm test` **704/704**；CUI 包 967 通过 + 1 个既有夹具 ERROR；cangjie-sdl 包 239/241（1 个既有字体像素失败） |
| 像素门禁 | `scripts/parity.sh --theme both` + `scripts/diff.sh --theme both` **14/14** |

## 3. 设备与当前安装包

| 项 | 值 |
|---|---|
| hdc | `~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc`（**无线调试，端口会轮换**：`hdc list targets` / `hdc tconn <ip>:<port>`） |
| bundle | `com.ethancheung.textura` |
| 已装包 | HEAD `c0bbeeb` 出货包，**30,118,758 B**，sha256 `a2ac45a691d46b0fefc68118bfb891624b68b9c442d26da970458783dc90105e`（构建副本 `~/.cache/wk-final/cangjie/harmony/out/entry-default-signed.hap`） |
| 用户数据 | 已还原到验收前：`workspace.json` sha256 `0ec8c7029db30219c57089bd8f142e33297a6a87dbec13337a816e4f9962edbd`；备份在 `~/.cache/workspace-before.json` |
| 界面状态 | 浮动窗口、浅色主题、密度「详细」、路由 OKR |

## 4. 本轮（最近 14 个提交）修了什么

| 提交 | 内容 | 真机验证 |
|---|---|---|
| `c0bbeeb` | OKR 文字宽度记忆化（每帧测量 821→149） | 主机 |
| `030dff0` | OKR 绘制批跨帧复用（`OkrPaint.clear()`） | 主机 |
| `8d09c26` | 钉住「滚轮 → 画布重排 + 重绘」的用例 | 主机 |
| `876526a` | **CUI-P12**：修 `ScrollView` 滚轮后布局阶段失聪（真因见 §5.2） | 主机 0px → 34.7 万 px |
| `5107ce2` | OKR 可见区裁剪（文字绘制 606→169/帧，绘制 23.3→7.7ms/帧） | 主机字节级一致 |
| `98e2d3b` | **CUI-P11**：`clipPaintBounds()` 把逻辑裁剪暴露给自绘画布 | 主机 |
| `80e8c35` | 小键盘 `KP_0..9` / `KP_ENTER` → `Key.Digit` / `Key.Enter` | **真机 PASS**（2104/2105/2119） |
| `e920244` | SOP 复选框接受区 14×14 → 行首 22×30（绘制不变） | **真机 PASS**（0/2↔1/2） |
| `a4fea9b` | 文档：数字键修复 + 真机验收记录（DEVICE-NOTES §27） | — |
| `6c4b32f` | **CUI-P10**：裸 `KeyDown` 可打印字符兜底（硬件数字键打不进的真因） | **真机 PASS** |
| `c529457` | SOP 选中节点从 `store.selected()` 恢复（改字段不再跳回整体设置） | **真机 PASS** |
| `077bee9` | 宿主用 `updateCursor` 取代每字符 `attach`（IME 会话不再被打断） | 真机（组合不再丢） |
| `4fb0a44` | 全角数字折半角后才解析 | 主机 |
| `a39bd4c` | 「无法解析成数字」其实多为「值没变」→ 不再误报 | 主机 |

补丁台账在 `cangjie/third_party/README.md`（CUI-P01…P12，含 SDL 补丁与理由），**改动 CUI/SDL 前必须读它**。

## 5. 两个「看起来是 UI，其实在框架」的根因（别重踩）

### 5.1 硬件数字键打不进（已修，CUI-P10）
- 字符只有一条写入路径：`UiEvent.TextInput`；字母会被系统输入法接管并提交，**数字不会**——它只作为 `KeyDown Digit(52)` 落到应用，而 `TextField.handleKey` 没有 `Key.Digit` 分支，字符被静默丢弃；退格走 `KeyDown(Backspace)` 有分支，所以「只删得掉」。
- 修法：按下时**暂存**，同帧若有 `TextInput` 则取消，下一帧 tick 用同一条 `actions().insert()` 落字（杜绝双插入）。
- **坑**：`DesktopApp.stepFrame` 只把帧 tick 交给 `frameSubscriber`，`UiEvent.Frame` 从不进控件树——第一版把 flush 挂在 `handle(UiEvent.Frame)` 上，主机全绿、真机零效果（见 `text_printable_key.cj` 顶部注释）。

### 5.2 滚轮滚动后画面不动（已修，CUI-P12）
- 现象：滚轮改变偏移但一帧都不重绘，切页签再回来才显示新位置（切路由会**把偏移复位**，所以别拿它当"强刷"）。
- 真因：`PhaseStateDependencies.reuseCommittedPrefix` 把「已提交前缀」的边挂到 pending frontier 时**没登记进 `pendingSources`**，随后 `commit()` 的 `closeRemovedDependencies` 把仍 pending 的边关掉 → 布局阶段对 `scrollOffset` 永久失聪。判据是 `stateSet listeners=0`。
- 修法：`third_party/CUI/src/core/state_phase_dependency.cj` 里补登记（4 行），**不是**在 OKR 里 `requestFrame` 能解决的。

## 6. 唯一阻塞项：OKR prompt 打开后必崩（运行时缺陷）

### 6.1 事实
- 崩溃定位：`libcangjie-runtime` CopyCollector forward 阶段，**应用侧无栈帧**
  - 主线程 `F CANGJIE-RUNTIME: Check failed: toRegion2Idx != INVALID_VALUE`（总在 `Preforward light sync` 之后）→ SIGABRT
  - GC 线程 `SIGSEGV@0x8`：`RegionInfo::VisitLiveObjectsUntilFalse → RegionManager::ForwardRegion → CopyCollector::ForwardFromSpace`
- 复现：最大化窗口 + 点「紧凑」→ 点页底 `＋ 新增关键结果…`（`okr_cards.cj:525-548`，热区 `okr-add-<objId>`）打开 prompt → **不动任何东西**等：88s / 2s / 17.7s 三次都崩（GC 中位间隔 160ms、峰值 allocated 25.5MB）。
- 触发面比「双击」宽：单击同样崩（延迟到下次 GC）；点 KR 行上/下移动图标也崩；Esc 关 prompt 也崩；什么都不点则 2 分钟+稳定。
- 已做缓解（不足）：绘制批跨帧复用 + 文字测量记忆化 → 每帧文字测量 821→149、GC 时间 −28%，但**崩溃仍 3/3**。

### 6.2 下一步（按推荐顺序）
1. **调运行时 GC 参数**：`libcangjie-runtime.so` 里有 `cjHeapSize`、`cjLargeThresholdSize` 参数（字符串证据：`Unsupported cjHeapSize parameter...`）。在 `requireCJLib('libtextura_host.so')` **之前**把参数注入（`setenv` 可在 `harmony/entry/src/main/cpp/host_bootstrap.c` 里做，或 ArkTS 侧加一个 NAPI 前置调用），把 heuristic GC 从 160ms 一次压到秒级；配合同步降低光标闪烁期间的整页重绘（让闪烁只重绘编辑器矩形）。验收口径就用「打开 prompt 等 90s ×3 不崩」。
2. **最小复现上报运行时**：一个 ~60 行仓颉程序，30MB/s 分配 + 周期 GC，能稳定打出 `toRegion2Idx != INVALID_VALUE`；附 §6.1 两条栈与设备版本（MNT-W72C 7.0.0.111 SP7C00E103R12P2）。
3. **临时绕开**（换可用性）：prompt 打开期间停掉光标闪烁/页面动画，把「持续出帧 + 高分配」这个组合拆掉。属缓解，需在文档里标明。

## 7. 构建 / 装机（照抄即可）

```bash
# 1) 主机门禁（务必在私有副本里跑，不要在共享树跑 cjpm/hvigor）
cp -a cangjie ~/.cache/wk-x/ && cd ~/.cache/wk-x/cangjie
export TMPDIR=~/.cache/tmp
cjpm test                                    # 期望 704/704
./scripts/build.sh && ./scripts/parity.sh --theme both && ./scripts/diff.sh --theme both   # 期望 14/14

# 2) 打出货包（不要加 TEXTURA_PROBE=1，那是诊断包）
./scripts/harmony/build_ohos.sh
C=.certs/textura-debug      # 相对快照根；传给脚本时用绝对路径（相对路径会报 00303107）
./scripts/harmony/set_signing_material.sh \
    --store-file     /abs/snap/cangjie/harmony/$C/textura-debug.p12 \
    --key-alias      textura-debug \
    --cert           /abs/snap/cangjie/harmony/$C/TexturaDebug.cer \
    --profile        /abs/snap/cangjie/harmony/$C/TexturaProfileDebug.p7b \
    --store-password "$(cat $C/password.txt)" --key-password "$(cat $C/password.txt)" \
    --dry-run        # 先 dry-run 确认 bundleName/UDID 匹配，再去掉 --dry-run 正式写
./scripts/harmony/assemble_hap.sh
#    若 stage_libs.sh 报找不到 libc++：export TEXTURA_OHOS_LIBCXX=<PixCap>/entry/libs/arm64-v8a/libc++.so

# 3) 装机
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
$HDC uninstall com.ethancheung.textura ; $HDC install -r harmony/out/entry-default-signed.hap
$HDC shell aa start -a EntryAbility -b com.ethancheung.textura

# 4) 收尾（必须！）
git checkout -- cangjie/harmony/build-profile.json5     # 含机器绑定签名密文，不得入库
git status --porcelain                                  # 必须为空
```

## 8. 真机操作与取证的经验（血泪，能省你两小时）

- **屏幕坐标换算**：`屏幕 = (windowX + 1.75·x, windowY + 内容原点 + 1.75·y)`，density=1.75；窗口原点每次会话都要重新量（`hilog` 的 `textura-geometry`，或直接截图量）。图像分析工具给的坐标有 ±7% 偏差，**先叠网格标定再点**。
- **点击注入**：`uitest uiInput click` 只发抬手（对某些控件无效），**可靠写法**是 `uitest uiInput swipe x y x+3 y+2 60`；真双击用 `uinput -M -b <x> <y> 0 20 80`。
- **滚轮/鼠标注入进不了 SDL 表面**（`uinput -M -s` 像素 0 变化，而 `PageDown` 能滚 21%）——判断滚动类问题请让用户用**实体鼠标**，或改用键盘 PageUp/PageDown 作为「重排+重绘是否生效」的代理指标。
- **键盘注入**：小键盘 `KEYCODE_NUMPAD_1=2104 / _2=2105 / ENTER=2119`；主键盘数字 `2000..2009`；`uinput -K -d <c> -u <c>`。注意：主键盘数字会被系统输入法当候选键吃掉（只有字母会走 IME 组合，空格提交才落字）。
- **日志**：D 级 ArkUI 日志会在数秒内把环形缓冲冲掉——取证必须 `hilog -r` → 动作 → 立刻 dump。`/data/log/faultlog/faultlogger` 对 shell 是 Permission denied，但 hilog 里的 `DfxFaultLogger` 行**带完整 #00–#10 栈**。
- **锁屏**：设备经常自己锁上，锁屏下 `aa start` 报 `10106102`、注入穿不过去；需用户手动解锁（`uitest uiInput keyEvent Home` 有时能解除）。
- **系统弹窗**：「软件更新」会置顶并吞输入 → 每次操作前截图，见到就点「稍后」。
- **无无障碍树**：`uitest dumpLayout` 只能看到 `XComponent(SDL)` 容器，所有控件坐标只能从像素量。

## 9. 待办（按优先级）

1. 【阻塞】§6.2 的 GC 参数调优 → 用「prompt 等 90s ×3」验收；顺带把 §6.1 的最小复现写出来。
2. 【待用户确认】实体鼠标滚一格：应立刻移动约 72px、连滚 3 秒连续更新、不需切页签（CUI-P12 主机已验证，真机因注入限制未测）。滚轮目前是 72px 跳步，**没有惯性动画**——若需要平滑滚动是另一个决定（时间驱动偏移动画）。
3. 【体验】OKR 页底 prompt 打开时整页每帧重绘（光标闪烁驱动）→ 可只重绘编辑器区域，既是性能也是 §6.2 第 1 条的配套。
4. 【已知小问题】SOP 右栏在浮动窗口高度下「检查项」区块被裁切且右栏不可滚动（最大化才看得到），与 Web 的 `overflow-y: auto` 有差距。
5. 【文档】把 §6 的运行时缺陷整理进 `docs/STABILITY.md`（现有 §C1 已有同类栈），并给上游一份可复现材料。
6. 【清理】`~/.cache/` 下的构建副本（`wk-*`，含 800MB+ 树、HAP）可随时删。

## 10. 关键文件地图

| 关注点 | 路径 |
|---|---|
| 应用外壳 / 路由 / 滚动容器 | `src/shell/appshell.cj`、`src/shell/*.cj` |
| OKR 页（自绘画布） | `src/views/okr/{okr_page,okr_cards,okr_canvas,okr_ops,okr_prompt}.cj` |
| SOP 页 / 检查器 / 浮层 | `src/views/sop/{sop,sop_inspector,sop_area_picker,sop_prompt,sop_model}.cj` |
| 原位编辑器（画布字段上的真控件） | `src/ui/inline_editor.cj`、`src/ui/inline_anchor.cj`、`src/ui/ui.cj` |
| CUI 补丁（含 P10/P11/P12） | `third_party/CUI/src/text/text_printable_key.cj`、`third_party/CUI/src/core/{spatial_clip,state_phase_dependency,scrolling}.cj`、`third_party/README.md` |
| SDL 键盘解码 | `third_party/cangjie-sdl/src/events.cj`、`sdl_types_raw.cj` |
| 鸿蒙宿主（XComponent / IME / 尺寸） | `harmony/entry/src/main/ets/pages/Index.ets`、`ets/entryability/EntryAbility.ets`、`cpp/textura_keys.c` |
| 文档 | `docs/DEVICE-NOTES.md`（§21 IME、§24 尺寸、§27 数字键验收）、`docs/STABILITY.md`、`docs/HARMONY.md`（签名）、`docs/PARITY.md` |
