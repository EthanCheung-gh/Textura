package textura.views.gantt.logic

import std.unittest.*
import std.unittest.testmacro.*

/*
 * 甘特图滚轮：SDL 向下滚是 `wheelY = -1`，内容必须**向前**（offset 增加）；每格 72 逻辑 px，
 * 与 CUI `ScrollView` 完全一致（`scrolling.cj` 的 `CUI_SCROLL_WHEEL_STEP`）。
 */

@Test
func wheelDownMovesContentForwardByOneStep(): Unit {
    @Expect(ganttWheelDelta(-1.0), GANTT_WHEEL_STEP)
}

@Test
func wheelUpMovesContentBackwardByOneStep(): Unit {
    @Expect(ganttWheelDelta(1.0), -GANTT_WHEEL_STEP)
}

@Test
func wheelIdleChangesNothing(): Unit {
    @Expect(ganttWheelDelta(0.0), 0.0)
}

/** Shift+滚轮的水平增量走同一套符号与步长，避免两轴手感分裂。 */
@Test
func horizontalWheelUsesTheSameStep(): Unit {
    @Expect(ganttWheelDelta(-2.0), 2.0 * GANTT_WHEEL_STEP)
}