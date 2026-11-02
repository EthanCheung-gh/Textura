package textura.views.okr

import std.env.*

/*
 * P0：OKR 页每帧行为的观测计数器。
 *
 * 目的只有一个——**把「每帧分配多少」变成可断言的数字**，为
 * `docs/OKR-EDIT-PLAN.md` 的 P0–P4 提供基线，并为 P3（分配优化）留一条回归线。
 *
 * 纪律（改这个文件前先读）：
 *   1. 只观测：埋点一律是 `+= 1` / `= 本帧值`，**不改变任何分支、返回值、绘制顺序**；
 *      像素等价由 parity 门禁（`scripts/diff.sh --theme both`，14/14 逐字节）证明。
 *   2. 视图里不读时钟：`frameMs` 不作为字段（见 `docs/OKR-P0-BASELINE.md` §3），
 *      需要帧耗时的地方由测试侧用 `std.time.MonoTime` 计时——`AGENTS.md` §6 要求视图
 *      不读系统时钟，否则 parity 的两次运行不再逐像素一致。
 *   3. 只在真正布局时计帧：`OkrPage.layout` 末尾调用 `noteFrame`；高度预演
 *      （`PageCanvas(measureOnly: true)`）不产出指令，不算一帧。
 *   4. 日志默认关闭：只有 `TEXTURA_OKR_METRICS=1` 时每 60 帧打印一行，门禁与真机运行
 *      不受影响（不设变量就一次都不打印）。
 *
 * 语义表（哪个字段是「最近一帧」、哪个是「自 reset 起累计」）：
 *
 * | 字段 | 语义 | 埋点位置 |
 * |---|---|---|
 * | `frames` | 累计帧数 | `okr_page.cj` `OkrPage.layout` 末尾 |
 * | `ops` | **最近一帧**绘制指令条数 | 同上（`cv.paint.opCount()`） |
 * | `hotspots` | **最近一帧**命中区个数 | 同上（`cv.hotspots.size`） |
 * | `widgets` | **最近一帧**子控件个数 | 同上（`cv.children.size`） |
 * | `textMeasureCalls` | 累计 `okrTextW` 调用次数（含高度预演、按钮/分段/徽章测宽） | `okr_ops.cj` `okrTextW` |
 * | `textMeasureMisses` | 累计缓存未命中（真正调 `UiContext.textWidth`）次数 | `okr_ops.cj` `OkrWidthMemo.width` |
 * | `ellipsizeCalls` | 累计 `ellipsize` 调用次数 | `okr_ops.cj` `ellipsize` |
 * | `ellipsizeCandidates` | 累计构造的候选串个数（`String(runes[0..keep]) + "…"`） | 同上 |
 * | `stringBuilds` | 累计格式化调用次数（`formatMetric` / `formatNumber` / `formatSchedule` /
 *   `quarterLabel` / `jsNumberToString` / `pad2`；**不**统计裸 `${}` 插值） | 见 `docs/OKR-P0-BASELINE.md` §2 的调用点表 |
 * | `focusableIdCalls` | 累计 `focusableIds()` 调用次数（每次 `toArray()` 一次分配） | `okr_page.cj` `focusableIds` |
 *
 * 为什么不做成 `ThreadLocal`：本文件的计数只服务于「单线程布局 + 测试」这一条路径，
 * 而 `cjpm test` 默认串行执行用例（`--parallel` 未在 `cjpm.toml` 里配置）。若将来把
 * `cjpm test --parallel N>1` 打开，`textMeasureCalls` 这类累计值会跨线程混在一起——
 * 那时要么改成 `ThreadLocal<OkrMetrics>`（照 `okr_ops.cj` 的 `OKR_WIDTH_MEMO`），要么
 * 让用例只断言「比值/相等」而不断言绝对帧数。`okr_metrics_test.cj` 的注释写了这条前提。
 */

/** 一次 `snapshot()` 的只读副本。 */
class OkrMetricsSnapshot {
    /** 自 `reset()` 起的帧数。 */
    let frames: Int64
    /** 最近一帧的绘制指令条数。 */
    let ops: Int64
    /** 最近一帧的命中区个数。 */
    let hotspots: Int64
    /** 最近一帧的子控件个数（`BadgeView` / `ProgressView` / `TextField`…）。 */
    let widgets: Int64
    /** 自 `reset()` 起 `okrTextW` 的调用次数。 */
    let textMeasureCalls: Int64
    /** 自 `reset()` 起文字宽度缓存未命中的次数（= 真正测量的次数）。 */
    let textMeasureMisses: Int64
    /** 自 `reset()` 起 `ellipsize` 的调用次数。 */
    let ellipsizeCalls: Int64
    /** 自 `reset()` 起 `ellipsize` 构造的候选串个数。 */
    let ellipsizeCandidates: Int64
    /** 自 `reset()` 起 `format*` 类格式化调用次数。 */
    let stringBuilds: Int64
    /** 自 `reset()` 起 `focusableIds()` 的调用次数。 */
    let focusableIdCalls: Int64

    init(frames: Int64, ops: Int64, hotspots: Int64, widgets: Int64, textMeasureCalls: Int64,
        textMeasureMisses: Int64, ellipsizeCalls: Int64, ellipsizeCandidates: Int64, stringBuilds: Int64,
        focusableIdCalls: Int64) {
        this.frames = frames
        this.ops = ops
        this.hotspots = hotspots
        this.widgets = widgets
        this.textMeasureCalls = textMeasureCalls
        this.textMeasureMisses = textMeasureMisses
        this.ellipsizeCalls = ellipsizeCalls
        this.ellipsizeCandidates = ellipsizeCandidates
        this.stringBuilds = stringBuilds
        this.focusableIdCalls = focusableIdCalls
    }

    /** 一行诊断文本（`docs/OKR-P0-BASELINE.md` 的表格就是照这行填的）。 */
    func line(): String {
        "[okr-metrics] frames=${frames} ops=${ops} hotspots=${hotspots} widgets=${widgets}" +
            " textMeasure=${textMeasureCalls} misses=${textMeasureMisses} ellipsize=${ellipsizeCalls}" +
            " candidates=${ellipsizeCandidates} stringBuilds=${stringBuilds} focusableIds=${focusableIdCalls}"
    }
}

/**
 * 计数器本体。字段全部是 `var`，写入点全是 `+= 1` / `= 本帧值`（见文件头的语义表）。
 *
 * 不做并发保护：布局只在 UI 线程（测试里是测试线程）执行，加锁只会把「观测」变成热点。
 */
class OkrMetrics {
    var frames: Int64 = 0
    var ops: Int64 = 0
    var hotspots: Int64 = 0
    var widgets: Int64 = 0
    var textMeasureCalls: Int64 = 0
    var textMeasureMisses: Int64 = 0
    var ellipsizeCalls: Int64 = 0
    var ellipsizeCandidates: Int64 = 0
    var stringBuilds: Int64 = 0
    var focusableIdCalls: Int64 = 0
    /**
     * 日志周期：`-1` = 还没读环境变量，`0` = 关闭，`>0` = 每 N 帧打印一行。
     *
     * 环境变量只读一次：每帧 `getVariable` 自己也是一次分配 + 系统调用，把它放进
     * 「测量分配」的帧里会让观测量影响被观测量。
     */
    private var logEvery: Int64 = -1

    /** 归零（测试用；生产路径不调用）。 */
    func reset(): Unit {
        frames = 0
        ops = 0
        hotspots = 0
        widgets = 0
        textMeasureCalls = 0
        textMeasureMisses = 0
        ellipsizeCalls = 0
        ellipsizeCandidates = 0
        stringBuilds = 0
        focusableIdCalls = 0
    }

    func snapshot(): OkrMetricsSnapshot {
        OkrMetricsSnapshot(frames, ops, hotspots, widgets, textMeasureCalls, textMeasureMisses, ellipsizeCalls,
            ellipsizeCandidates, stringBuilds, focusableIdCalls)
    }

    /**
     * 记一帧：`okr_page.cj` 的 `OkrPage.layout` 末尾调用，参数是本帧画布的三个规模量。
     *
     * `ops` / `hotspots` / `widgets` 存**本帧值**（不是累计）：逐帧增长就是「批没有清空」或
     * 「子树在累积」的回归信号，`okr_metrics_test.cj` 用两条连续帧相等来钉住它。
     */
    func noteFrame(frameOps: Int64, frameHotspots: Int64, frameWidgets: Int64): Unit {
        frames += 1
        ops = frameOps
        hotspots = frameHotspots
        widgets = frameWidgets
        resolveLogPeriod()
        if (logEvery > 0 && frames % logEvery == 0) {
            println(snapshot().line())
        }
    }

    private func resolveLogPeriod(): Unit {
        if (logEvery >= 0) {
            return
        }
        logEvery = match (getVariable("TEXTURA_OKR_METRICS")) {
            case Some(value) => if (value == "1") {
                60
            } else {
                0
            }
            case None => 0
        }
    }
}

/** 进程内单例：埋点处直接 `okrMetrics.xxx += 1`。 */
let okrMetrics = OkrMetrics()
