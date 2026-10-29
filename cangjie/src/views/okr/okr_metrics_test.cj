package textura.views.okr

import std.unittest.*
import std.unittest.testmacro.*
import std.time.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.*

/*
 * P0 计数器门禁（`okr_metrics.cj`）：钉住「每帧的规模量不增长」，并把一行基线打到输出。
 *
 * 构造方式与 `okr_page_test.cj` / `okr_paint_reuse_test.cj` 相同：走 shell 的同一条构建路径
 * （`VStack { OkrPage(...) }`，框架负责 build → measure → layout → draw），不手工调 `layout`。
 *
 * 这里断言的是**行为不变量**，不是像素：
 *   1. 两次 `host.frame` 各自跑同样多次 `OkrPage.layout`（实测 1 帧 = **3 次** layout：
 *      CUI 的「先测、再布、必要时重布」，所以 `frames` 计的是 layout 调用数，不是窗口帧数）；
 *   2. 第二帧的绘制指令 / 命中区 / 子控件数与第一帧**相等**——任何「批没有 `clear()`」或
 *      「子树逐帧累积」都会让第二帧变大，这条就会红（像素本身由 parity 14/14 保证）；
 *   3. 演示数据下确实发生了文字测量与省略（否则计数器等于没接上）。
 *
 * 前提：`cjpm test` 串行执行用例（`cjpm.toml` 没有配 `--parallel`）。`okrMetrics` 是进程内
 * 单例，若将来开 `cjpm test --parallel N>1`，`frames` 会被其它用例的布局一起推高——那时要么把
 * 单例改成 `ThreadLocal`（照 `okr_ops.cj` 的 `OKR_WIDTH_MEMO`），要么只断言「相等」而丢掉
 * 绝对帧数，见 `okr_metrics.cj` 的文件头。
 */

private let METRICS_VIEWPORT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
/** `.shell-content` 的内容宽：1440 − 240 侧栏 − 48 内边距（与 parity 同一条算式）。 */
private let METRICS_PAGE_W: Float32 = 1152.0
private let METRICS_ANCHOR: Int64 = 1773626400000

/** 一帧的观测记录：帧耗时由**测试侧**计时（视图内不读时钟，见 `okr_metrics.cj` 文件头）。 */
private class MetricsFrame {
    /** 整个 `host.frame`（build + measure + layout + draw）的微秒数。 */
    let micros: Int64
    let snapshot: OkrMetricsSnapshot

    init(micros: Int64, snapshot: OkrMetricsSnapshot) {
        this.micros = micros
        this.snapshot = snapshot
    }
}

private func metricsStore(): AppStore {
    let clock = FixedClock(METRICS_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute("okr")
    store
}

/**
 * 与 shell 同一条构建路径：页面作为普通子树被框架 build + layout（不是手工调 layout）。
 *
 * `revision` 由测试在两次 `frame` 之间递增，用来**强制第二帧重建**：P2 之后 `OkrPage.layout`
 * 不再写任何 `State`（`focusTrack` 那套随卡片内联编辑器一起删掉了），所以「没有任何脏标记」
 * 的一帧会跳过重建，`OkrPage.layout` 一次都不会跑——那样就测不到「第二帧不增长」。
 */
private func metricsBody(viewCtx: ViewContext, revision: State<Int64>, width!: Float32 = METRICS_PAGE_W): () -> Unit {
    {=>
        let _ = revision.value
        VStack(spacing: vp(0.0)) {
            let _ = OkrPage(viewCtx, okrUiState())
        }
            .width(width)
            .height(METRICS_VIEWPORT.h)
    }
}

private func timedFrame(host: WidgetTestHost, body: () -> Unit): MetricsFrame {
    let started = MonoTime.now()
    let _ = host.frame(METRICS_VIEWPORT, body: body)
    let elapsed = (MonoTime.now() - started).toNanoseconds() / 1000
    MetricsFrame(elapsed, okrMetrics.snapshot())
}

@Test
func okrFrameCountersDoNotGrowAcrossLayouts(): Unit {
    // 单例归零：本用例只认自己两帧的增量。
    okrMetrics.reset()
    let store = metricsStore()
    let viewCtx = ViewContext(store, "light", "2026-01-01", 1440, 900, {_ => ()})
    let host = WidgetTestHost()
    let revision = State<Int64>(0)
    let body = metricsBody(viewCtx, revision)
    let first = timedFrame(host, body)
    revision.value = revision.value + 1
    let second = timedFrame(host, body)

    // `frames` = `OkrPage.layout` 的调用次数（实测 1 个窗口帧 = 3 次）；两次 `host.frame`
    // 必须走同样多次布局，否则「每帧相等」的比较口径就不成立了。
    @Expect(first.snapshot.frames > 0, true)
    let layoutsPerFrame = first.snapshot.frames
    let secondFrameLayouts = second.snapshot.frames - layoutsPerFrame
    @Expect(secondFrameLayouts, layoutsPerFrame)
    // 一帧确实画了东西（不然下面「相等」就没有意义）。
    @Expect(second.snapshot.ops > 0, true)
    @Expect(second.snapshot.hotspots > 0, true)
    // 无逐帧增长：绘制批跨帧复用（`OkrPaint.clear()`）、命中区与子控件都只属于本帧。
    @Expect(second.snapshot.ops, first.snapshot.ops)
    @Expect(second.snapshot.hotspots, first.snapshot.hotspots)
    @Expect(second.snapshot.widgets, first.snapshot.widgets)
    // 演示数据下确实走了文字测量与省略（计数器接上了）。
    @Expect(second.snapshot.textMeasureCalls > 0, true)
    @Expect(second.snapshot.ellipsizeCalls > 0, true)
    @Expect(second.snapshot.stringBuilds > 0, true)
    // 第二帧不再新增测量未命中：宽度缓存跨帧有效（第一帧 = 冷启动，含重复测量）。
    let secondFrameMisses = second.snapshot.textMeasureMisses - first.snapshot.textMeasureMisses
    @Expect(secondFrameMisses, 0)

    // 一行基线（`docs/OKR-P0-BASELINE.md` 的表格照这行填）：`ops/hotspots/widgets` 是快照里的
    // **单次 layout** 值，累计量用两次快照之差除以本帧 layout 次数换成「每次 layout」。
    let perLayoutMeasure = (second.snapshot.textMeasureCalls - first.snapshot.textMeasureCalls) / secondFrameLayouts
    let perLayoutEllipsize = (second.snapshot.ellipsizeCalls - first.snapshot.ellipsizeCalls) / secondFrameLayouts
    let perLayoutCandidates = (second.snapshot.ellipsizeCandidates - first.snapshot.ellipsizeCandidates) /
        secondFrameLayouts
    let perLayoutBuilds = (second.snapshot.stringBuilds - first.snapshot.stringBuilds) / secondFrameLayouts
    println("[okr-metrics] layouts=${secondFrameLayouts} ops=${second.snapshot.ops}" +
        " hotspots=${second.snapshot.hotspots} widgets=${second.snapshot.widgets}" +
        " textMeasure=${perLayoutMeasure} misses=${secondFrameMisses} ellipsize=${perLayoutEllipsize}" +
        " candidates=${perLayoutCandidates} stringBuilds=${perLayoutBuilds}" +
        " focusableIds=${second.snapshot.focusableIdCalls} frameUs=${second.micros} firstFrameUs=${first.micros}")
}

/**
 * 窄页面的省略计数：1152 宽的演示数据一行都不截断，`ellipsizeCandidates` 因此恒为 0；
 * 把页面压到 520 之后，KR 标题/提示行必须真的走到「构造候选串」那条循环里。
 *
 * 断言的是「计数器确实接到了逐字截断的那条路径」，不是具体条数（那个数字随文案变化）。
 */
@Test
func narrowPageReportsEllipsizeCandidates(): Unit {
    okrMetrics.reset()
    let store = metricsStore()
    let viewCtx = ViewContext(store, "light", "2026-01-01", 1440, 900, {_ => ()})
    let host = WidgetTestHost()
    let revision = State<Int64>(0)
    let body = metricsBody(viewCtx, revision, width: 520.0)
    let _ = host.frame(METRICS_VIEWPORT, body: body)
    revision.value = revision.value + 1
    let _ = host.frame(METRICS_VIEWPORT, body: body)
    let snapshot = okrMetrics.snapshot()
    @Expect(snapshot.ellipsizeCalls > 0, true)
    @Expect(snapshot.ellipsizeCandidates > 0, true)
    println("[okr-metrics] narrow=520 layouts=${snapshot.frames} ellipsize=${snapshot.ellipsizeCalls}" +
        " candidates=${snapshot.ellipsizeCandidates} textMeasure=${snapshot.textMeasureCalls}" +
        " stringBuilds=${snapshot.stringBuilds}")
}

/** `reset()` 归零所有累计量；本帧值（`ops`/`hotspots`/`widgets`）也一起清掉。 */
@Test
func resetZeroesEveryCounter(): Unit {
    okrMetrics.reset()
    okrMetrics.textMeasureCalls += 5
    okrMetrics.ellipsizeCandidates += 3
    okrMetrics.noteFrame(7, 11, 13)
    @Expect(okrMetrics.snapshot().frames, 1)
    @Expect(okrMetrics.snapshot().ops, 7)
    @Expect(okrMetrics.snapshot().hotspots, 11)
    @Expect(okrMetrics.snapshot().widgets, 13)
    okrMetrics.reset()
    let cleared = okrMetrics.snapshot()
    @Expect(cleared.frames, 0)
    @Expect(cleared.ops, 0)
    @Expect(cleared.hotspots, 0)
    @Expect(cleared.widgets, 0)
    @Expect(cleared.textMeasureCalls, 0)
    @Expect(cleared.textMeasureMisses, 0)
    @Expect(cleared.ellipsizeCalls, 0)
    @Expect(cleared.ellipsizeCandidates, 0)
    @Expect(cleared.stringBuilds, 0)
    @Expect(cleared.focusableIdCalls, 0)
}
