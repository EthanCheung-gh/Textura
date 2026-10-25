package textura.views.okr

import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.ui.*

/*
 * 视口裁剪：`ScrollView` 裁掉的部分不再下发绘制命令，但**可见像素一个都不许变**。
 *
 * 这两件事分开验证，所以下面两组用例各管一半：
 *
 *   1. 几何判据（`okrPaintBounds` / `okrClipped`）：外扩量正好是 `OKR_CULL_MARGIN`，且只有与可见区
 *      **严格分离**的矩形才会被跳过——仅仅贴住边界（也就是说还差 32px 才可能落进真正的视口）的
 *      op 仍然会画。这钉住的是「宁可多画、绝不漏画」。
 *   2. 真实绘制计数：把一个只画 `OkrPaint` 指令表的画布放进 `ScrollView`，用
 *      `TestFrameMetrics.textDraws` 数本帧真正提交了几次文字绘制。视口外那条必须 0 次，视口内那条
 *      必须照旧 1 次。
 *
 * 像素等价本身由 parity 门禁（14/14）保证；这里钉住的是它的**原因**。
 */

private let CULL_VIEWPORT: Rect = Rect(0.0, 0.0, 600.0, 120.0)

/** 记录一次 draw 里看到的可见区，用来断言外扩量确实是 32。 */
private class BoundsSink {
    var value: ?Rect = None
    var seen: Bool = false
}

/** 一个只负责把 `OkrPaint` 指令表画出来的画布，用来数「到底提交了几条」。 */
private class PaintHarness <: Widget {
    private let tokens: ThemeTokens
    private let paint: OkrPaint
    private let sink: ?BoundsSink

    init(tokens: ThemeTokens, paint: OkrPaint, sink!: ?BoundsSink = None) {
        this.tokens = tokens
        this.paint = paint
        this.sink = sink
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, 4000.0)
    }

    public func layout(_: UiContext, _: Rect): Unit {}

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    public func draw(ctx: UiContext): Unit {
        match (sink) {
            case Some(target) =>
                target.seen = true
                target.value = okrPaintBounds(ctx)
            case None => ()
        }
        paint.draw(ctx, tokens)
    }
}

/* ------------------------------------------------------------------ 1. 几何判据 */

@Test
func cullBoundsInflateTheViewportBy32(): Unit {
    let sink = BoundsSink()
    drawOneFrame(CULL_VIEWPORT, oneTextPaint(), Some(sink))
    @Expect(sink.seen, true)
    match (sink.value) {
        case Some(bounds) =>
            @Expect(bounds.x, -OKR_CULL_MARGIN)
            @Expect(bounds.y, -OKR_CULL_MARGIN)
            @Expect(bounds.w, CULL_VIEWPORT.w + OKR_CULL_MARGIN * 2.0)
            @Expect(bounds.h, CULL_VIEWPORT.h + OKR_CULL_MARGIN * 2.0)
        case None => @Fail("a drawn scroll viewport must expose a clip")
    }
}

@Test
func cullBoundsAreAbsentOutsideAScrollViewport(): Unit {
    let sink = BoundsSink()
    let testHost = WidgetTestHost()
    let tokens = ThemeTokens.light()
    let _ = testHost.frame(CULL_VIEWPORT,
        body: {=> PaintHarness(tokens, oneTextPaint(), sink: Some(sink))})
    let _ = testHost.frame(CULL_VIEWPORT,
        body: {=> PaintHarness(tokens, oneTextPaint(), sink: Some(sink))})
    @Expect(sink.seen, true)
    @Expect(sink.value.isNone(), true)
}

@Test
func cullKeepsOpsThatOnlyTouchTheMarginBoundary(): Unit {
    let bounds = Rect(0.0, 0.0, 600.0, 200.0)
    // 贴在边界上：仍然画。
    @Expect(okrClipped(Some(bounds), Rect(10.0, bounds.bottom(), 100.0, 20.0)), false)
    @Expect(okrClipped(Some(bounds), Rect(bounds.right(), 10.0, 20.0, 20.0)), false)
    // 越界一像素：跳过。
    @Expect(okrClipped(Some(bounds), Rect(10.0, bounds.bottom() + 1.0, 100.0, 20.0)), true)
    @Expect(okrClipped(Some(bounds), Rect(bounds.right() + 1.0, 10.0, 20.0, 20.0)), true)
    // 上方对称。
    @Expect(okrClipped(Some(bounds), Rect(10.0, bounds.y - 20.0, 100.0, 20.0)), false)
    @Expect(okrClipped(Some(bounds), Rect(10.0, bounds.y - 21.0, 100.0, 20.0)), true)
}

@Test
func cullNeverSkipsInsideOrWithoutAClip(): Unit {
    let bounds = Rect(0.0, 0.0, 600.0, 200.0)
    @Expect(okrClipped(Some(bounds), Rect(10.0, 10.0, 20.0, 20.0)), false)
    @Expect(okrClipped(Some(bounds), Rect(-1000.0, 10.0, 100.0, 20.0)), true)
    let unclipped: ?Rect = None
    @Expect(okrClipped(unclipped, Rect(-1000.0, 10.0, 100.0, 20.0)), false)
}

/* ------------------------------------------------------------------ 2. 真实绘制计数 */

@Test
func cullSkipsTextOpsTheViewportClipsAway(): Unit {
    // 两条 op：一条在顶部，一条在 1500px 处。整页可见时是 2 次，120px 视口里只剩 1 次。
    @Expect(textDrawsIn(4000.0), 2)
    @Expect(textDrawsIn(CULL_VIEWPORT.h), 1)
}

@Test
func cullDrawsAnOpThatSitsOnTheMarginBoundary(): Unit {
    // 文字 op 的盒子是 `centerY ± size`（这里 size = 12），可见区下边界在 120 + 32 = 152：
    // 盒子顶边正好压在 152 上时仍然画；再往下 1px 就整条跳过。
    let boundary = CULL_VIEWPORT.h + OKR_CULL_MARGIN + 12.0
    @Expect(textDrawsAt(boundary, CULL_VIEWPORT.h), 2)
    @Expect(textDrawsAt(boundary + 1.0, CULL_VIEWPORT.h), 1)
}

/* ------------------------------------------------------------------ 3. 滚轮滚动后必须重排重画 */

/*
 * 契约：「滚轮滚一次，下一帧画面就动」。OKR 的 op 表是在 `layout` 里按 `rect.y` 生成的
 * （`OkrPage.layout` → `layoutPage`），所以这条用例的画布也照着做：`layout` 收到什么偏移，
 * `draw` 就画在哪。任何一环断掉——偏移没写、布局没重跑、绘制命中缓存——都会让可见 op 数量停在
 * 滚之前的值，也就是真机上「滚轮像坏了、切路由回来才看到滚动结果」的那个现象。
 *
 * 根因在 CUI 的失效传播（补丁 CUI-P12，`core/state_phase_dependency.cj`）：保留布局阶段的
 * 依赖可能在 reconcile 时被误关，偏移 State 从此没有监听者，布局再也不会被失效。
 */
private class WheelCanvasRecord {
    var layoutCalls: Int64 = 0
    var layoutY: Float32 = 0.0
}

/** 按 layout 收到的矩形生成 op 表的画布；`farY` 是第二条 op 的中心 y（偏移量的基准）。 */
private class ScrollingPaintCanvas <: Widget {
    private let tokens: ThemeTokens
    private let record: WheelCanvasRecord
    private let farY: Float32
    private var paint = OkrPaint()

    init(tokens: ThemeTokens, record: WheelCanvasRecord, farY: Float32) {
        this.tokens = tokens
        this.record = record
        this.farY = farY
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, 4000.0)
    }

    public func layout(_: UiContext, assigned: Rect): Unit {
        record.layoutCalls += 1
        record.layoutY = assigned.y
        let next = OkrPaint()
        // 第一条留在可见区里（滚一格之后仍在），这样「绘制次数」只反映第二条的进出。
        next.texts.add(OkrTextOp(10.0, assigned.y + 60.0, "顶部", 12.0, 400, tokens.color.text, 30.0))
        next.texts.add(OkrTextOp(10.0, assigned.y + farY, "远端", 12.0, 400, tokens.color.text, 30.0))
        paint = next
    }

    public func draw(ctx: UiContext): Unit {
        paint.draw(ctx, tokens)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

@Test
func wheelScrollReLaysOutTheCanvasAndChangesTheVisibleOps(): Unit {
    let record = WheelCanvasRecord()
    let tokens = ThemeTokens.light()
    // 第二条 op 在滚之前正好落在裁剪余量之外（盒子上边 153 > 可见区下边界 152），滚一格后进入可见区。
    let farY = CULL_VIEWPORT.h + OKR_CULL_MARGIN + 13.0
    let testHost = WidgetTestHost()
    let body = {=>
        ScrollView(key: Some("okr-wheel")) {
            ScrollingPaintCanvas(tokens, record, farY)
        }.width(CULL_VIEWPORT.w).height(CULL_VIEWPORT.h)
        ()
    }

    let warm = testHost.frame(CULL_VIEWPORT, body: body)
    @Expect(Int64(warm.metrics.textDraws), 1)
    @Expect(record.layoutY, Float32(0.0))
    let layoutsBefore = record.layoutCalls

    // SDL 把「向下滚一格」报成 y 轴 -1。
    let scrolled = testHost.frame(CULL_VIEWPORT,
        events: [UiEvent.MouseWheel(0.0, -1.0, 200.0, 60.0)], body: body)

    @Expect(record.layoutY, -72.0)
    @Expect(record.layoutCalls > layoutsBefore, true)
    @Expect(Int64(scrolled.metrics.textDraws), 2)
}

/* ------------------------------------------------------------------ helpers */

private func oneTextPaint(): OkrPaint {
    let tokens = ThemeTokens.light()
    let paint = OkrPaint()
    paint.texts.add(OkrTextOp(10.0, 10.0, "可见", 12.0, 400, tokens.color.text, 30.0))
    paint
}

private func twoTextPaint(secondY: Float32): OkrPaint {
    let tokens = ThemeTokens.light()
    let paint = oneTextPaint()
    paint.texts.add(OkrTextOp(10.0, secondY, "视口外", 12.0, 400, tokens.color.text, 40.0))
    paint
}

/** 画两帧（第一帧提交构建、第二帧取指标），返回第二帧提交的文字绘制次数。 */
private func drawOneFrame(viewport: Rect, paint: OkrPaint, sink: ?BoundsSink): Int64 {
    let testHost = WidgetTestHost()
    let tokens = ThemeTokens.light()
    let body = {=>
        ScrollView(key: Some("cull-harness")) {
            PaintHarness(tokens, paint, sink: sink)
        }.width(viewport.w).height(viewport.h)
        ()
    }
    let _ = testHost.frame(viewport, body: body)
    let frame = testHost.frame(viewport, body: body)
    Int64(frame.metrics.textDraws)
}

private func textDrawsIn(viewportHeight: Float32): Int64 {
    let noSink: ?BoundsSink = None
    drawOneFrame(Rect(0.0, 0.0, CULL_VIEWPORT.w, viewportHeight), twoTextPaint(1500.0), noSink)
}

private func textDrawsAt(secondY: Float32, viewportHeight: Float32): Int64 {
    let noSink: ?BoundsSink = None
    drawOneFrame(Rect(0.0, 0.0, CULL_VIEWPORT.w, viewportHeight), twoTextPaint(secondY), noSink)
}
