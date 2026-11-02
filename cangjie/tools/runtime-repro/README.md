# runtime-repro — 仓颉运行时 GC 崩溃的最小复现（未成功，如实记录）

目标缺陷见 `docs/HANDOFF.md` §6、`docs/STABILITY.md` §3：

- 真机：`F CANGJIE-RUNTIME: Check failed: toRegion2Idx != INVALID_VALUE`（`CopyCollector::ForwardFromSpace`）。
- 主机：`SIGSEGV`，栈顶 `SlotRoot::VisitGCRoots → CheckAndPush`，`addr: (nil)`。

## 程序做什么

`src/main.cj` 复刻应用侧的形状，而不是 UI：

1. 96 层递归（相当于 CUI 布局栈 + dagre 栈），每层在**当前帧**分配 `ArrayList` / `HashMap` / 字符串；
2. 每层跨一次 FFI（`malloc`/`free`），让 C 帧混在深栈里；
3. 栈底做一次 4096 条字符串的重分配；
4. 单进程重复 300 轮，每轮丢弃上一轮的堆，迫使 GC 反复扫描这些深栈。

## 构建与运行

```bash
cd cangjie/tools/runtime-repro
source ../../scripts/env.sh
cjpm build
./target/release/bin/main          # 单次 ~0.6s，正常输出 "survived 300 rounds"

# 压力：200 次并行，统计非零退出与运行时断言
rm -rf /tmp/repro-logs && mkdir -p /tmp/repro-logs
seq 1 200 | xargs -P 8 -I{} sh -c \
  './target/release/bin/main >/dev/null 2>/tmp/repro-logs/{}.err; echo "$? {}"' > /tmp/repro-logs/rc.txt
awk '{c[$1]++} END {for (k in c) print k, c[k]}' /tmp/repro-logs/rc.txt
grep -l "Check failed\|SIGSEGV\|SIGABRT" /tmp/repro-logs/*.err | wc -l
```

## 实测结果（2026-10-28，主机 Linux x86_64，`cjc 1.2.0`）

| 版本 | 次数 | 崩溃 | 备注 |
|---|---|---|---|
| 纯仓颉分配 + 深递归 | 200 | **0** | 全部输出 `survived 300 rounds` |
| 每层加 `malloc`/`free` FFI 帧 | 200 | **0** | 同上 |

**结论：这个最小形状不能复现缺陷。** 说明触发条件不只是「深栈 + 高频 GC」，还依赖 CUI/SDL 的
C++ 栈内容或该构建产物里的栈图；把栈换成纯仓颉（哪怕中间夹 C 帧）后，运行时扫描是安全的。

## 目前唯一可复现的主机路径

`cangjie/scripts/stability.sh` 跑 `textura.shell` 套件（CUI 布局 + SOP dagre + SDL 调用）：

```bash
cd cangjie
TEXTURA_STRESS_RUNS=100 TEXTURA_STABILITY_TARGET_DIR=/path/to/target ./scripts/stability.sh
```

修前 11/50，修后约 1/100（`docs/STABILITY.md` §4.3）。`#0` 行就是可提交给运行时的栈。

## 给运行时的材料

1. 真机 `hilog -x` 原始两行（`docs/STABILITY.md` §2）与设备版本
   `MNT-W72C 7.0.0.111 SP7C00E103R12P2`；
2. 主机 `CheckAndPush` 崩溃栈（`docs/STABILITY.md` §3.1）；
3. 本目录的两个「不复现」结果——它把问题范围从「任何深栈 GC」收窄到「CUI/SDL 参与的栈」。