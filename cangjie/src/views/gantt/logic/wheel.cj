package textura.views.gantt.logic

/**
 * 滚轮每格的位移，必须与 CUI `ScrollView` 一致：
 * `third_party/CUI/src/core/scrolling.cj` 的 `CUI_SCROLL_WHEEL_STEP = 72.0`。
 */
public let GANTT_WHEEL_STEP: Float32 = 72.0

/**
 * SDL 的 `MouseWheel` 载荷是 `(wheelX, wheelY, mouseX, mouseY)`，向下滚时 `wheelY < 0`。
 * CUI 的滚动容器统一按 `offset - wheel * step` 处理；甘特图主体是自绘的，必须套同一个符号与步长，
 * 否则上下方向会反、速率也和其他页签不一致。
 */
public func ganttWheelDelta(wheel: Float32): Float32 {
    -wheel * GANTT_WHEEL_STEP
}