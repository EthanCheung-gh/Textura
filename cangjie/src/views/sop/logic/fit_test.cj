package textura.views.sop.logic

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

let FIT_WIDE: FitBounds = FitBounds(40.0, 160.0, 1160.0, 224.0)
let FIT_VERTICAL: FitBounds = FitBounds(0.0, 0.0, 444.0, 664.0)

// 移植自 src/modules/sop/fit.test.ts

@Test
func testFitWideContentClampsToReadableMinimum(): Unit {
    // 横向内容：低于可读下限时取 0.7，并从左侧 margin 锚定起点
    let result = computeReadableViewport(ReadableFitOptions(526.0, 647.0, FIT_WIDE))
    @Expect(result.zoom, READABLE_MIN_ZOOM, delta: 1e-9)
    @Expect(result.clamped, true)
    @Expect(result.fitsWidth, false)
    // 流程起点仍在视口内（不会被居中裁掉）
    @Expect(result.viewport.x + FIT_WIDE.x * result.zoom, FIT_MARGIN, delta: 1e-9)
    @Assert(result.viewport.zoom >= 0.65)
}

@Test
func testFitVerticalContentIsFullyVisibleAndCentered(): Unit {
    // 纵向内容：高于下限、完整可见且水平居中
    let result = computeReadableViewport(ReadableFitOptions(526.0, 647.0, FIT_VERTICAL))
    let expected = 647.0 / (1.16 * FIT_VERTICAL.height)
    @Expect(result.zoom, expected, delta: 1e-6)
    @Assert(result.zoom > READABLE_MIN_ZOOM)
    @Assert(result.zoom <= 1.0)
    @Expect(result.fitsWidth, true)
    @Expect(result.fitsHeight, true)
    let center = result.viewport.x + (FIT_VERTICAL.x + FIT_VERTICAL.width / 2.0) * result.zoom
    @Expect(center, 526.0 / 2.0, delta: 1e-6)
    @Assert(FIT_VERTICAL.height * result.zoom / 647.0 > 0.7)
}

@Test
func testFitNarrowCanvasStillFitsContent(): Unit {
    // 1024 画布：可读下限生效但内容仍完整可见，不溢出
    let result = computeReadableViewport(ReadableFitOptions(478.0, 467.0, FIT_VERTICAL))
    @Expect(result.zoom, READABLE_MIN_ZOOM, delta: 1e-9)
    @Assert(FIT_VERTICAL.width * result.zoom <= 478.0)
    @Assert(FIT_VERTICAL.height * result.zoom <= 467.0)
    @Expect(result.fitsWidth, true)
    @Expect(result.fitsHeight, true)
    // 标题 13px × 0.7 ≈ 9.1px，满足可读要求
    @Assert(13.0 * result.zoom >= 9.0)
}

@Test
func testFitSmallGraphIsNotEnlarged(): Unit {
    let result = computeReadableViewport(ReadableFitOptions(800.0, 600.0, FitBounds(0.0, 0.0, 120.0, 80.0), maxZoom: 1.0))
    @Expect(result.zoom, 1.0)
    @Expect(result.clamped, false)
}

@Test
func testFitDegenerateBoundsStayFinite(): Unit {
    // 放不下时不会返回非法尺寸，degenerate bounds 也可计算
    let result = computeReadableViewport(ReadableFitOptions(0.0, 0.0, FitBounds(0.0, 0.0, 0.0, 0.0)))
    @Expect(isFiniteNumber(result.viewport.x), true)
    @Expect(isFiniteNumber(result.viewport.y), true)
    @Assert(result.zoom > 0.0)
}

@Test
func testBoundsOfPositions(): Unit {
    let positions = HashMap<String, SopPosition>()
    positions["a"] = SopPosition(40.0, 160.0)
    positions["b"] = SopPosition(280.0, 320.0)
    let boundsOpt = boundsOfPositions(positions, nodeWidth: 200.0, nodeHeight: 60.0)
    @Expect(boundsOpt.isSome(), true)
    let bounds = boundsOpt.getOrThrow()
    @Expect(bounds.x, 40.0)
    @Expect(bounds.y, 160.0)
    @Expect(bounds.width, 440.0)
    @Expect(bounds.height, 220.0)
}

@Test
func testBoundsOfPositionsEmpty(): Unit {
    let bounds = boundsOfPositions(HashMap<String, SopPosition>())
    @Expect(bounds.isNone(), true)
}

@Test
func testBoundsOfNodesUsesCanvasAnchor(): Unit {
    let nodes = [SopNode("a", canvasX: 10.0, canvasY: 20.0), SopNode("b", canvasX: 10.0, canvasY: 120.0)]
    let bounds = boundsOfNodes(nodes).getOrThrow()
    @Expect(bounds.x, 10.0)
    @Expect(bounds.y, 20.0)
    @Expect(bounds.width, 200.0)
    @Expect(bounds.height, 160.0)
}

@Test
func testIsWideLayout(): Unit {
    @Expect(isWideLayout(Some(FitBounds(0.0, 0.0, 1160.0, 224.0))), true)
    @Expect(isWideLayout(Some(FitBounds(0.0, 0.0, 444.0, 664.0))), false)
    @Expect(isWideLayout(None), false)
}

@Test
func testPreviewLayoutMatchesWebConstants(): Unit {
    @Expect(PREVIEW_LAYOUT.rankdir == RankDir.TopDown, true)
    @Expect(PREVIEW_LAYOUT.nodesep, 44.0)
    @Expect(PREVIEW_LAYOUT.ranksep, 60.0)
    @Expect(PREVIEW_LAYOUT.margin, 0.0)
    @Expect(FIT_NODE_HEIGHT, 64.0)
    @Expect(MIN_ZOOM, 0.25)
    @Expect(INITIAL_FIT_PADDING, 0.16)
}
