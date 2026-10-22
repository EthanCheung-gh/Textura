package textura.views.gantt.logic

/**
 * 刻度与几何：日期 ↔ 像素、吸附、任务条几何、拖拽、可视区间、任务条/依赖矩形。
 *
 * 与 TS `src/modules/gantt/scale.ts` 一一对应；像素一律 `Float64`（逻辑像素/px），
 * 日期一律 `YYYY-MM-DD` 日期键，内部换算走儒略日整数。
 */

/**
 * 日期 → 相对 `origin` 左边界的像素坐标。
 * 无法解析的日期键返回 0（TS 会得到 NaN 并在格式化时抛错，属于非法输入）。
 */
public func dateToX(key: String, origin: String, pxPerDay: Float64): Float64 {
    Float64(diffDays(origin, key)) * pxPerDay
}

/**
 * 像素坐标 → 该位置所在日期的键（左闭右开映射到所在天）。
 * 非有限 `x` 或非正 `pxPerDay` 退化为 `origin` 本身。
 */
public func xToKey(x: Float64, origin: String, pxPerDay: Float64): String {
    let originKey = toKey(origin)
    if (!isFiniteNumber(x) || !(pxPerDay > 0.0)) {
        return originKey
    }
    match (parseDateKey(originKey)) {
        case Some(number) =>
            let days = clampInt(tsFloorInt(x / pxPerDay), -2000000000, 2000000000)
            formatDateKey(number + days)
        case None => originKey
    }
}

/**
 * 吸附到日历天。三种缩放的吸附粒度都是 1 天（契约要求），返回日期键。
 * 粒度 >1 时按“当月第几天 % step”向回对齐，与 TS `snapDate` 的取模口径一致。
 */
public func snapKey(key: String, zoom: GanttZoom): String {
    let config = zoomConfig(zoom)
    let step = maxInt(1, config.snapDays)
    match (parseDateKey(toKey(key))) {
        case Some(number) =>
            if (step == 1) {
                return formatDateKey(number)
            }
            let (_, _, day) = civilFromDayNumber(number)
            let offset = if (day % step < 0) {
                day % step + step
            } else {
                day % step
            }
            formatDateKey(number - offset)
        case None => ""
    }
}

/** 保证 `start <= end`。 */
public func normalizeBar(start: String, end: String): BarRange {
    if (start <= end) {
        BarRange(start, end)
    } else {
        BarRange(end, start)
    }
}

/**
 * 条目有效的起止：缺一端时按 1 天补齐；两端都缺返回 None。
 * 入参是原始串（日期键或 ISO 时间戳），按 TS `dateKey` 语义取前 10 个字符。
 */
public func barRangeOf(start: ?String, end: ?String): ?BarRange {
    let startKey: ?String = match (start) {
        case Some(raw) => dateKeyOf(raw)
        case None => None
    }
    let endKey: ?String = match (end) {
        case Some(raw) => dateKeyOf(raw)
        case None => None
    }
    match ((startKey, endKey)) {
        case (None, None) => None
        case (Some(from), Some(to)) => Some(normalizeBar(from, to))
        case (Some(from), None) => Some(normalizeBar(from, from))
        case (None, Some(to)) => Some(normalizeBar(to, to))
    }
}

/** `GanttRow` 的有效区间。 */
public func itemRange(row: GanttRow): ?BarRange {
    barRangeOf(row.startDate, row.endDate)
}

/**
 * 进度展示口径（0..100 的整数）：
 * - `status == Done` 一律 100（toggleDone 不会回写 gantt.progress）；
 * - 其余取 `progress`，缺失 / 非有限按 0，四舍五入后夹到 0..100。
 * 只用于展示，不写回任何状态。
 */
public func displayProgress(row: GanttRow): Int64 {
    match (row.status) {
        case GanttStatus.Done => 100
        case _ => match (row.progress) {
            case Some(raw) =>
                if (!isFiniteNumber(raw)) {
                    0
                } else {
                    clampInt(tsRoundInt(raw), 0, 100)
                }
            case None => 0
        }
    }
}

/** 像素位置 + 缩放 → 绝对几何；`width` 至少一天。 */
public func barGeometry(range: BarRange, origin: String, pxPerDay: Float64): BarGeometry {
    let normalized = normalizeBar(range.start, range.end)
    let span = diffDays(normalized.start, normalized.end) + 1
    BarGeometry(
        normalized.start,
        normalized.end,
        Float64(diffDays(origin, normalized.start)) * pxPerDay,
        maxF64(pxPerDay, Float64(span) * pxPerDay),
        maxInt(1, span)
    )
}

/** 整体平移；`deltaDays` 按 TS `Math.round` 取整（半值向 +∞）。 */
public func moveBar(bar: BarRange, deltaDays: Float64): BarRange {
    let delta = tsRoundInt(deltaDays)
    BarRange(addDaysKey(bar.start, delta), addDaysKey(bar.end, delta))
}

/**
 * 拖左右边缘：保持 `start <= end`，最小 1 天。
 * 左边缘向右越过 end 时夹到 end；右边缘向左越过 start 时夹到 start。
 */
public func resizeBar(bar: BarRange, edge: BarEdge, deltaDays: Float64): BarRange {
    let delta = tsRoundInt(deltaDays)
    let normalized = normalizeBar(bar.start, bar.end)
    match (edge) {
        case BarEdge.Start =>
            let candidate = addDaysKey(normalized.start, delta)
            let start = if (candidate > normalized.end) {
                normalized.end
            } else {
                candidate
            }
            BarRange(start, normalized.end)
        case BarEdge.End =>
            let candidate = addDaysKey(normalized.end, delta)
            let end = if (candidate < normalized.start) {
                normalized.start
            } else {
                candidate
            }
            BarRange(normalized.start, end)
    }
}

/**
 * 时间轴总范围：
 * - 无排期条目：以 today 为中心按缩放留白；
 * - 有条目：覆盖最早开始 → 最晚结束，并加缓冲；today 始终在范围内；
 * - 周模式对齐到周一/周日，月模式对齐到月初/月末，保证表头从边界开始。
 */
public func buildRange(rows: Array<GanttRow>, zoom: GanttZoom, today!: String): DateRange {
    let config = zoomConfig(zoom)
    let todayKey = toKey(snapKey(today, zoom))
    var lowest = todayKey
    var highest = todayKey
    for (row in rows) {
        match (itemRange(row)) {
            case Some(range) =>
                if (range.start < lowest) {
                    lowest = range.start
                }
                if (range.end > highest) {
                    highest = range.end
                }
            case None => ()
        }
    }

    var start = addDaysKey(lowest, -config.paddingBefore)
    var end = addDaysKey(highest, config.paddingAfter)

    match (zoom) {
        case GanttZoom.Week =>
            start = startOfWeekKey(start)
            end = endOfWeekKey(end)
        case GanttZoom.Month =>
            start = startOfMonthKey(start)
            end = endOfMonthKey(end)
        case GanttZoom.Day => ()
    }
    DateRange(start, end)
}

/** 滚动窗口对应的日期范围（周末底色 / 区间标签用），已夹在总范围内。 */
public func visibleRange(range: DateRange, scrollLeft: Float64, width: Float64, pxPerDay: Float64): DateRange {
    let start = xToKey(maxF64(0.0, scrollLeft), range.start, pxPerDay)
    let end = xToKey(maxF64(0.0, scrollLeft + maxF64(1.0, width) - 1.0), range.start, pxPerDay)
    DateRange(clampKey(start, range), clampKey(end, range))
}

func clampKey(key: String, range: DateRange): String {
    if (key < range.start) {
        range.start
    } else if (key > range.end) {
        range.end
    } else {
        key
    }
}

/** 时间轴总宽（至少一天）。 */
public func totalWidth(range: DateRange, pxPerDay: Float64): Float64 {
    maxF64(pxPerDay, Float64(diffDays(range.start, range.end) + 1) * pxPerDay)
}

/** 「10月 20 – 11月 16」；跨年时两端都补年份。 */
public func formatRangeLabel(start: String, end: String): String {
    let sameYear = startOfYearKey(start) == startOfYearKey(end)
    "${rangeLabelPart(start, !sameYear)} – ${rangeLabelPart(end, !sameYear)}"
}

func startOfYearKey(key: String): String {
    match (parseDateKey(key)) {
        case Some(number) =>
            let (year, _, _) = civilFromDayNumber(number)
            formatDateKey(dayNumber(year, 1, 1))
        case None => ""
    }
}

func rangeLabelPart(key: String, withYear: Bool): String {
    match (parseDateKey(key)) {
        case Some(number) =>
            let (year, month, day) = civilFromDayNumber(number)
            if (withYear) {
                "${year}年${month}月 ${day}"
            } else {
                "${month}月 ${day}"
            }
        case None => "—"
    }
}

/** 任务条矩形：`y = rowIndex * ROW_HEIGHT + BAR_TOP_OFFSET`，里程碑固定 16 宽。 */
public func barRect(geometry: BarGeometry, rowIndex: Int64, milestone!: Bool = false): BarRect {
    let width = if (milestone) {
        MILESTONE_WIDTH
    } else {
        geometry.width
    }
    BarRect(geometry.x, Float64(rowIndex) * ROW_HEIGHT + BAR_TOP_OFFSET, width, BAR_HEIGHT)
}

/** 依赖连线端点矩形：左/右边缘 + 行中心线。 */
public func depRect(geometry: BarGeometry, rowIndex: Int64): DepRect {
    DepRect(geometry.x, geometry.x + geometry.width, Float64(rowIndex) * ROW_HEIGHT + ROW_HEIGHT / 2.0)
}
