package textura.views.sop.logic

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// 移植自 src/modules/sop/positions.test.ts

@Test
func testPositionsToPatchRoundsCanvasValues(): Unit {
    let patches = positionsToPatch(
        [
            CanvasPosition("step_a", 40.4, 159.6),
            CanvasPosition("step_b", 280.0, 160.0)
        ]
    )
    @Expect(patches.size, 2)
    @Expect(patches[0].id, "step_a")
    @Expect(patches[0].x, 40.0)
    @Expect(patches[0].y, 160.0)
    @Expect(patches[1].id, "step_b")
    @Expect(patches[1].x, 280.0)
    @Expect(patches[1].y, 160.0)
}

@Test
func testPositionsToPatchSkipsUnchanged(): Unit {
    let current = HashMap<String, SopPosition>()
    current["step_a"] = SopPosition(40.0, 160.0)
    current["step_b"] = SopPosition(280.0, 160.0)
    let patches = positionsToPatch(
        [
            CanvasPosition("step_a", 40.0, 160.0),
            CanvasPosition("step_b", 300.0, 160.0)
        ],
        current: current
    )
    @Expect(patches.size, 1)
    @Expect(patches[0].id, "step_b")
    @Expect(patches[0].x, 300.0)
    @Expect(patches[0].y, 160.0)
}

@Test
func testPositionsToPatchEmptyInput(): Unit {
    let patches = positionsToPatch(Array<CanvasPosition>())
    @Expect(patches.size, 0)
}

@Test
func testCanvasPatchesToUpdateItemsBuildsOneBatch(): Unit {
    let patches = positionsToPatch(
        [
            CanvasPosition("step_start", 0.0, 0.0),
            CanvasPosition("step_a", 0.0, 120.0),
            CanvasPosition("step_b", 0.0, 240.0)
        ]
    )
    let payload = canvasPatchesToUpdateItems(patches)
    @Expect(payload.size, 3)
    @Expect(payload[2].id, "step_b")
    @Expect(payload[2].patch.sop.canvas.x, 0.0)
    @Expect(payload[2].patch.sop.canvas.y, 240.0)

    // 调用方语义：整批一次 updateItems（=> 单条历史 + 单次防抖保存）由视图层保证；
    // 这里只需确认 N 个补丁产出 N 条载荷且顺序稳定。
    @Expect(payload[0].id, "step_start")
    @Expect(payload[1].id, "step_a")
    @Expect(payload[1].patch.sop.canvas.y, 120.0)
}

@Test
func testCanvasPatchesToUpdateItemsEmpty(): Unit {
    let payload = canvasPatchesToUpdateItems(Array<CanvasPosition>())
    @Expect(payload.size, 0)
}
