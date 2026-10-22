package textura.views.gantt.logic

import std.collection.*

/**
 * 依赖连线几何（纯折线点，等价于 TS `GanttDependencies.tsx` 里的 SVG path）。
 *
 * 语义约定：`from` 依赖 `to`（`to` 是前置）。常规情况从前置终点右侧出发，
 * 折线进入依赖方起点左侧；当中间行有任务条挡住竖直通道时，改走行间空隙（gutter），
 * 避免直角线穿过任务条。调用方传入的 `blockers` 可以是全部可见任务条
 * （与端点同行的条会被 `betweenRows` 过滤掉，等价于 TS 的引用相等判断）。
 */

/** 折线顶点序列；Canvas 依次 `moveTo` + `lineTo` 即可，末点即箭头位置。 */
public func dependencyPath(
    dependent: DepRect,
    prerequisite: DepRect,
    blockers: Array<DepRect>,
    width: Float64
): Array<Point> {
    let sameRowTolerance = 2.0
    let low = minF64(dependent.cy, prerequisite.cy)
    let high = maxF64(dependent.cy, prerequisite.cy)
    let intermediate = ArrayList<DepRect>()
    for (rect in blockers) {
        if (rect.cy > low + sameRowTolerance && rect.cy < high - sameRowTolerance) {
            intermediate.add(rect)
        }
    }
    let blocked = {
        x: Float64 =>
            var hit = false
            for (rect in intermediate) {
                if (x >= rect.x1 - 2.0 && x <= rect.x2 + 2.0) {
                    hit = true
                    break
                }
            }
            hit
    }

    let gap = dependent.x1 - prerequisite.x2
    let startX = prerequisite.x2
    let startY = prerequisite.cy
    let endX = dependent.x1
    let endY = dependent.cy

    if (gap >= 8.0) {
        let candidates: Array<Float64> = [startX + gap / 2.0, startX + 6.0, endX - 6.0]
        for (candidate in candidates) {
            if (candidate > startX && candidate < endX && !blocked(candidate)) {
                return [
                    Point(startX, startY),
                    Point(candidate, startY),
                    Point(candidate, endY),
                    Point(endX, endY)
                ]
            }
        }
    } else if (gap >= 0.0 && !blocked(startX)) {
        // 前置结束与依赖开始相邻：直接竖向连接。
        return [Point(startX, startY), Point(maxF64(startX, endX), endY)]
    }

    // 绕行：先进入前置行下方的空隙，横移到空闲通道，再沿依赖行的上侧空隙接入左边缘。
    let direction = if (endY >= startY) {
        1.0
    } else {
        -1.0
    }
    let gutterStart = startY + direction * 18.0
    let gutterEnd = endY - direction * 18.0
    let candidates = ArrayList<Float64>([endX - 8.0, endX - 16.0, startX + 8.0, startX + 16.0, endX - 28.0])
    for (rect in intermediate) {
        candidates.add(rect.x1 - 10.0)
        candidates.add(rect.x2 + 10.0)
    }
    var channel = maxF64(4.0, endX - 8.0)
    for (candidate in candidates) {
        if (candidate > 2.0 && candidate < width - 2.0 && !blocked(candidate)) {
            channel = candidate
            break
        }
    }

    [
        Point(startX, startY),
        Point(startX, gutterStart),
        Point(channel, gutterStart),
        Point(channel, gutterEnd),
        Point(endX, gutterEnd),
        Point(endX, endY)
    ]
}
