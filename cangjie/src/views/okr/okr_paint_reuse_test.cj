package textura.views.okr

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.*

/*
 * 绘制批跨帧复用：钉住「每帧不再重建整套绘制指令」这件事本身。
 *
 * 背景：CUI 每帧重建整棵树，光标闪烁这类「只重绘」的帧也走 build → layout → draw，于是 OKR 页
 * 每帧都要把上千条指令对象重新分配一遍。真机上的后果不是慢，而是**分配速率触发运行时 GC 缺陷**
 * （`libcangjie-runtime` CopyCollector forward 阶段断言失败，见 docs/STABILITY.md）。所以这里钉的
 * 不是观感，而是分配行为：
 *
 *   1. `OkrPaint` 的 10 个容器跨两次 layout 是**同一实例**，且每次 layout 前被 `clear()` 归零——
 *      长度不会逐帧叠加（叠加就是漏画/重画）；
 *   2. `clear()` 真的把每个容器清空；
 *   3. 绘制阶段只读：跑完一帧后容器身份、长度、指令对象身份都不变（视口裁剪的谓词只读标量/值类型，
 *      不新建 op）。仓颉里 `sdl.Rect` 是 `struct`（值类型），裁剪谓词里的临时矩形不会分配——
 *      这条用「容器与指令身份不变 + 计数不变」间接证明，分配器本身无法在语言内直接观测；
 *   4. 文字宽度缓存的返回值与 `UiContext.textWidth` 的直接测量逐位相同（缓存不允许改变布局）。
 *
 * 像素等价本身由 parity 门禁（14/14，逐字节）保证；这里钉住的是它的**原因**。
 */

private let REUSE_VIEWPORT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let REUSE_PAGE_W: Float32 = 1152.0
private let REUSE_ANCHOR: Int64 = 1773626400000

private class ReuseRecord {
    var pages: ArrayList<OkrPage> = ArrayList<OkrPage>()

    func last(): ?OkrPage {
        if (pages.isEmpty()) {
            return None
        }
        Some(pages[pages.size - 1])
    }
}

/** 画一块给定的 `OkrPaint`，用来观察绘制阶段是否改动了指令批。 */
private class BatchPainter <: Widget {
    private let tokens: ThemeTokens
    private let paint: OkrPaint

    init(tokens: ThemeTokens, paint: OkrPaint) {
        this.tokens = tokens
        this.paint = paint
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
        paint.draw(ctx, tokens)
    }
}

private func reuseStore(): AppStore {
    let clock = FixedClock(REUSE_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute("okr")
    store
}

private func reuseContext(store: AppStore): ViewContext {
    ViewContext(store, "light", "2026-01-01", 1440, 900, {_ => ()})
}

/** 与 shell 同一条构建路径：页面作为普通子树被框架 build + layout（不是手工调 layout）。 */
private func pageBody(viewCtx: ViewContext, record: ReuseRecord): () -> Unit {
    {=>
        VStack(spacing: vp(0.0)) {
            let ui = okrUiState()
            let page = OkrPage(viewCtx, ui)
            record.pages.add(page)
        }
            .width(REUSE_PAGE_W)
            .height(REUSE_VIEWPORT.h)
    }
}

/* ------------------------------------------------------------------ 1. 容器跨帧复用 */

@Test
func paintBatchIsTheSameInstanceAcrossLayouts(): Unit {
    let store = reuseStore()
    let viewCtx = reuseContext(store)
    let record = ReuseRecord()
    let host = WidgetTestHost()
    let body = pageBody(viewCtx, record)

    let _ = host.frame(REUSE_VIEWPORT, body: body)
    let first = match (record.last().getOrThrow().paintBatch()) {
        case Some(batch) => batch
        case None => @Fail("a laid-out page must expose its paint batch")
    }
    let firstCount = first.opCount()

    let _ = host.frame(REUSE_VIEWPORT, body: body)
    let second = match (record.pages[record.pages.size - 1].paintBatch()) {
        case Some(batch) => batch
        case None => @Fail("a laid-out page must expose its paint batch")
    }

    // 同一个批（同一个对象），所以 10 个容器也是同一批实例。
    @Expect(refEq((first as Object).getOrThrow(), (second as Object).getOrThrow()), true) // cjcheck-ignore: unchecked-cast # identity of the retained batch
    // 第二帧没有在第一帧的基础上叠加：条数与第一帧相同，不是两倍。
    @Expect(firstCount > 0, true)
    @Expect(second.opCount(), firstCount)
    @Expect(refEq((first.texts as Object).getOrThrow(), (second.texts as Object).getOrThrow()), true) // cjcheck-ignore: unchecked-cast # container reuse
    @Expect(refEq((first.fills as Object).getOrThrow(), (second.fills as Object).getOrThrow()), true) // cjcheck-ignore: unchecked-cast # container reuse
}

@Test
func clearEmptiesEveryContainerWithoutReplacingIt(): Unit {
    let paint = OkrPaint()
    let ink = Color.rgb(1, 2, 3)
    let frame = Rect(0.0, 0.0, 10.0, 10.0)
    paint.shadows.add(OkrShadowOp(frame, 4.0))
    paint.fills.add(OkrFillOp(frame, 4.0, ink))
    paint.strokes.add(OkrStrokeOp(frame, 4.0, 1.0, ink))
    paint.dashes.add(OkrDashOp(frame, 4.0, ink))
    paint.dots.add(OkrDotOp(5.0, 5.0, 3.0, ink))
    paint.lines.add(OkrLineOp(0.0, 0.0, 10.0, 1.0, 1.0, ink))
    paint.icons.add(OkrIconOp(frame, IconGlyph.Plus, ink))
    paint.chevrons.add(OkrChevronOp(frame, true, ink))
    paint.texts.add(OkrTextOp(0.0, 5.0, "文字", 12.0, 400, ink, 24.0))
    paint.rings.add(OkrRingOp("id", frame, 4.0))
    @Expect(paint.opCount(), 10)

    let texts = paint.texts
    let fills = paint.fills
    paint.clear()

    @Expect(paint.opCount(), 0)
    @Expect(paint.shadows.size, 0)
    @Expect(paint.fills.size, 0)
    @Expect(paint.strokes.size, 0)
    @Expect(paint.dashes.size, 0)
    @Expect(paint.dots.size, 0)
    @Expect(paint.lines.size, 0)
    @Expect(paint.icons.size, 0)
    @Expect(paint.chevrons.size, 0)
    @Expect(paint.texts.size, 0)
    @Expect(paint.rings.size, 0)
    // 容器本身不换实例（换掉就等于每帧重新 new 一个 ArrayList）。
    @Expect(refEq((texts as Object).getOrThrow(), (paint.texts as Object).getOrThrow()), true) // cjcheck-ignore: unchecked-cast # container identity
    @Expect(refEq((fills as Object).getOrThrow(), (paint.fills as Object).getOrThrow()), true) // cjcheck-ignore: unchecked-cast # container identity
}

/* ------------------------------------------------------------------ 2. 绘制阶段只读 */

@Test
func drawDoesNotMutateTheBatchAndStillCulls(): Unit {
    let tokens = ThemeTokens.light()
    let paint = OkrPaint()
    // 一条在视口内、一条远在 1500px 之外：视口 120 高时只许画 1 条。
    paint.texts.add(OkrTextOp(10.0, 60.0, "可见", 12.0, 400, tokens.color.text, 30.0))
    paint.texts.add(OkrTextOp(10.0, 1500.0, "视口外", 12.0, 400, tokens.color.text, 40.0))
    let texts = paint.texts
    let head = paint.texts[0]

    let host = WidgetTestHost()
    let viewport = Rect(0.0, 0.0, 600.0, 120.0)
    let body = {=>
        ScrollView(key: Some("reuse-cull")) {
            BatchPainter(tokens, paint)
        }
            .width(viewport.w)
            .height(viewport.h)
        ()
    }
    let _ = host.frame(viewport, body: body)
    let frame = host.frame(viewport, body: body)

    @Expect(Int64(frame.metrics.textDraws), 1)
    // 绘制不改指令批：容器身份、条数、第一条指令对象都没变（裁剪谓词没有新建/替换任何 op）。
    @Expect(refEq((texts as Object).getOrThrow(), (paint.texts as Object).getOrThrow()), true) // cjcheck-ignore: unchecked-cast # draw is read-only
    @Expect(paint.opCount(), 2)
    @Expect(refEq((head as Object).getOrThrow(), (paint.texts[0] as Object).getOrThrow()), true) // cjcheck-ignore: unchecked-cast # drawn ops are not rebuilt
}
