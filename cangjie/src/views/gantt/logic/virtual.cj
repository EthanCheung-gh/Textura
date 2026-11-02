package textura.views.gantt.logic

/**
 * 虚拟化窗口计算（纯函数）。语义对齐 TS `src/modules/gantt/virtual.ts`：
 * - 返回的 `end` / `last` 是**排他上界**，可直接用于 `slice(first, last)`；
 * - 调用方负责把滚动坐标换成容器内坐标（例如扣掉 52px 吸顶表头）。
 */

/**
 * 行窗口。
 *
 * - `scrollTop`：行区域滚动偏移（不含吸顶表头高度）；
 * - `viewportH`：行区域可视高度；
 * - `rowH`：固定行高（<=0 或非有限按 1）；
 * - `buffer`：上下各预取的行数；
 * - `total`：总行数；`None` 表示未知（返回不封顶窗口）。
 */
public func visibleRows(
    scrollTop: Float64,
    viewportH: Float64,
    rowH: Float64,
    buffer: Float64,
    total!: ?Int64 = None
): WindowRange {
    var count: Int64 = -1
    match (total) {
        case Some(value) =>
            count = maxInt(0, value)
            if (count == 0) {
                return WindowRange(0, 0)
            }
        case None => ()
    }

    let height = maxF64(1.0, finiteOr(rowH, 1.0))
    let top = maxF64(0.0, finiteOr(scrollTop, 0.0))
    let view = maxF64(0.0, finiteOr(viewportH, 0.0))
    let firstVisible = tsFloorInt(top / height)
    // 视口底部恰好落在行边界时，下一行不算可见。
    let lastVisibleExclusive = if (view == 0.0) {
        firstVisible
    } else {
        tsCeilInt((top + view) / height)
    }
    let pad = maxInt(0, tsFloorInt(finiteOr(buffer, 0.0)))

    let rawStart = maxInt(0, firstVisible - pad)
    let rawEnd = maxInt(rawStart, lastVisibleExclusive + pad)
    if (count < 0) {
        return WindowRange(rawStart, rawEnd)
    }
    let start = minInt(count, rawStart)
    WindowRange(start, minInt(count, maxInt(start, rawEnd)))
}

/**
 * 列窗口（支持非等宽列）。
 *
 * - `scrollLeft`：横向滚动偏移；
 * - `viewportW`：横向可视宽度；
 * - `colWidths`：每一列的宽度（必须与列的 x 偏移一致）；
 * - `buffer`：左右各预取的列数。
 */
public func visibleColumns(
    scrollLeft: Float64,
    viewportW: Float64,
    colWidths: Array<Float64>,
    buffer: Float64
): WindowRange {
    let count = colWidths.size
    if (count == 0) {
        return WindowRange(0, 0)
    }

    let left = maxF64(0.0, finiteOr(scrollLeft, 0.0))
    let width = maxF64(0.0, finiteOr(viewportW, 0.0))
    let right = left + width

    var offset = 0.0
    var firstVisible: Int64 = -1
    var lastVisibleExclusive: Int64 = 0
    for (index in 0..count) {
        let columnWidth = maxF64(0.0, finiteOr(colWidths[index], 0.0))
        let next = offset + columnWidth
        if (firstVisible < 0 && next > left) {
            firstVisible = index
        }
        if (offset < right) {
            lastVisibleExclusive = index + 1
        }
        offset = next
    }

    // 滚动到最右侧之外时没有“可见列”，退化为末尾 buffer 列。
    if (firstVisible < 0) {
        firstVisible = count
    }
    let pad = maxInt(0, tsFloorInt(finiteOr(buffer, 0.0)))
    let start = maxInt(0, minInt(count, firstVisible - pad))
    let end = maxInt(start, minInt(count, lastVisibleExclusive + pad))
    WindowRange(start, end)
}

/**
 * 行窗口的可绘制形式：`last` 排他，`offsetY` = 第一条可见行在视口内的 y 偏移
 * （Canvas 直接用 `translate(0, offsetY)` 再按行号绘制）。
 */
public func rowWindow(
    scrollTop: Float64,
    viewportH: Float64,
    rowH: Float64,
    buffer: Float64,
    total!: ?Int64 = None
): RowWindow {
    let window = visibleRows(scrollTop, viewportH, rowH, buffer, total: total)
    let height = maxF64(1.0, finiteOr(rowH, 1.0))
    RowWindow(window.start, window.end, Float64(window.start) * height)
}
