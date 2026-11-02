package textura.views.calendar

import std.collection.*
import textura.core.data.*
import textura.views.calendar.logic.*

/*
 * `core.data.Workspace` -> 日历渲染输入。
 *
 * 映射规则见 docs/CALENDAR-LOGIC.md §3：视图层只做字段投影，不复制领域事实。
 * 所有派生（区间裁剪、分桶、排序、农历标签）都由 `textura.views.calendar.logic`
 * 的纯函数给出，这里只负责把 `Item` / `Area` 塞进去。
 */

/** 工作区全部条目 -> `CalItem`（含领域色解析；无日期的条目也会映射，由 logic 过滤）。 */
func calItemsOf(workspace: Workspace): Array<CalItem> {
    let colors = HashMap<String, String>()
    for (area in workspace.areas) {
        colors[area.id] = area.color
    }
    let items = Array<CalItem>(workspace.items.size, repeat: CalItem("", "", "", "", "", "", "", false))
    for (index in 0..workspace.items.size) {
        let item = workspace.items[index]
        let start = match (item.gantt) {
            case Some(value) => value.start.getOrDefault({=> ""})
            case None => ""
        }
        let end = match (item.gantt) {
            case Some(value) => value.end.getOrDefault({=> ""})
            case None => ""
        }
        let areaColor = match (item.areaId) {
            case Some(id) => colors.get(id).getOrDefault({=> ""})
            case None => ""
        }
        let kind = itemKindWire(item.kind)
        items[index] = CalItem(item.id, item.title, kind, itemStatusWire(item.status), start, end, areaColor,
            kind == "milestone")
    }
    return items
}

/** `areaId -> Area`，面板要显示领域名与色点。 */
func areaMapOf(workspace: Workspace): HashMap<String, Area> {
    let areas = HashMap<String, Area>()
    for (area in workspace.areas) {
        areas[area.id] = area
    }
    return areas
}

/** 某一天的可见条目（Web: `buckets.get(selected) ?? []`）。 */
func dayItemsOf(items: Array<CalItem>, key: String): Array<CalItem> {
    let buckets = bucketItemsByDay(calendarItemsInRange(items, key, key), key, key)
    return match (buckets.get(key)) {
        case Some(list) => list
        case None => Array<CalItem>()
    }
}

/** `3月16日`（DayPanel 的 `shortDate`）。 */
func shortDateLabel(key: String): String {
    return match (parseKey(key)) {
        case Some(value) => "${value.month.toString()}月${value.day.toString()}日"
        case None => ""
    }
}

/**
 * 面板里的区间副标题（DayPanel.tsx `spanText`）：
 * 跨天 -> `第 n 天 · 3月6日 – 3月29日`；只有截止日 -> `截止当天`；否则空串。
 */
func panelSpanText(item: CalItem, dayKey: String): String {
    let span = itemSpan(item)
    if (span.isNone()) {
        return ""
    }
    let range = span.getOrThrow()
    if (range.days > 1) {
        let index = spanDayIndex(item, dayKey)
        return "第 ${index.toString()} 天 · ${shortDateLabel(range.start.key())} – ${shortDateLabel(range.end.key())}"
    }
    let onlyDue = dateKeyOf(item.startDate).isEmpty() && !dateKeyOf(item.endDate).isEmpty()
    return if (onlyDue) {
        "截止当天"
    } else {
        ""
    }
}

/** `星期一` 等短名（周视图列头）。 */
func weekdayNameOf(key: String): String {
    return WEEKDAY_FULL_CN[weekdayOfKey(key)]
}

/** `itemId -> Area`：面板卡片要显示领域名与色点（`CalItem` 只带颜色）。 */
func itemAreasOf(workspace: Workspace): HashMap<String, Area> {
    let byId = HashMap<String, Area>()
    for (area in workspace.areas) {
        byId[area.id] = area
    }
    let map = HashMap<String, Area>()
    for (item in workspace.items) {
        match (item.areaId) {
            case Some(id) =>
                match (byId.get(id)) {
                    case Some(area) => map[item.id] = area
                    case None => ()
                }
            case None => ()
        }
    }
    return map
}
