package textura.views.calendar.logic

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*
import std.sort.*

/**
 * 条目层验收：逐条移植 `calendarLogic.test.ts` 的
 * bucketItemsByDay / itemSpan / spanDayIndex / sortDayItems / visibleItems 断言，
 * 以及 `itemDisplay.ts` 的映射表。
 */
@Test
class ItemTest {
    @TestCase
    func itemSpanHasThreeDays(): Unit {
        let span = itemSpan(ganttItem("x", "x", "2026-10-01", "2026-10-03"))
        @Expect(span.isSome(), true)
        let range = span.getOrThrow()
        @Expect(range.start.key(), "2026-10-01")
        @Expect(range.end.key(), "2026-10-03")
        @Expect(range.days, 3)
    }

    @TestCase
    func itemSpanWithoutDates(): Unit {
        @Expect(itemSpan(makeItem("y", "y")).isNone(), true)
    }

    @TestCase
    func reversedSpanIsNormalized(): Unit {
        let span = itemSpan(ganttItem("z", "z", "2026-10-05", "2026-10-02"))
        @Expect(span.isSome(), true)
        let range = span.getOrThrow()
        @Expect(range.start.key(), "2026-10-02")
        @Expect(range.end.key(), "2026-10-05")
        @Expect(range.days, 4)
    }

    @TestCase
    func dueOnlySpanIsSingleDay(): Unit {
        let span = itemSpan(ganttItem("b", "只有截止日", "", "2026-10-05"))
        @Expect(span.isSome(), true)
        let range = span.getOrThrow()
        @Expect(range.start.key(), "2026-10-05")
        @Expect(range.end.key(), "2026-10-05")
        @Expect(range.days, 1)
    }

    @TestCase
    func itemSpanIgnoresShortDates(): Unit {
        // dateKey 长度 < 10 视为缺失（与 TS 一致）
        @Expect(itemSpan(CalItem("s", "s", "action", "next", "2026-1", "", "", false)).isNone(), true)
    }

    @TestCase
    func spanDayIndexCountsFromOne(): Unit {
        let item = ganttItem("x", "x", "2026-10-01", "2026-10-03")
        @Expect(spanDayIndex(item, "2026-10-01"), 1)
        @Expect(spanDayIndex(item, "2026-10-02"), 2)
        @Expect(spanDayIndex(item, "2026-10-03"), 3)
        @Expect(spanDayIndex(item, "2026-10-04"), 0)
        @Expect(spanDayIndex(item, "2026-09-30"), 0)
    }

    @TestCase
    func spanTextForMultiDay(): Unit {
        let item = ganttItem("x", "x", "2026-10-01", "2026-10-03")
        @Expect(spanText(item, "2026-10-01"), "第 1/3 天")
        @Expect(spanText(item, "2026-10-02"), "第 2/3 天")
        @Expect(spanText(item, "2026-10-04"), "")
    }

    @TestCase
    func spanTextForDueOnly(): Unit {
        let due = ganttItem("b", "只有截止日", "", "2026-10-05")
        @Expect(spanText(due, "2026-10-05"), "截止")
        let single = ganttItem("c", "单日", "2026-10-05", "2026-10-05")
        @Expect(spanText(single, "2026-10-05"), "")
    }

    @TestCase
    func bucketPlacesSpanningItemOnEveryDay(): Unit {
        let buckets = bucketItemsByDay(fixtureItems(), "2026-10-01", "2026-10-31")
        @Expect(buckets.contains("2026-09-29"), false)
        @Expect(idsOf(buckets, "2026-10-01"), "a")
        @Expect(idsOf(buckets, "2026-10-02"), "a")
        @Expect(buckets.contains("2026-10-03"), false)
    }

    @TestCase
    func bucketPlacesDueOnlyItemOnItsDay(): Unit {
        let buckets = bucketItemsByDay(fixtureItems(), "2026-10-01", "2026-10-31")
        @Expect(idsOf(buckets, "2026-10-05"), "b")
        @Expect(buckets.contains("2026-10-04"), false)
        @Expect(buckets.contains("2026-10-06"), false)
    }

    @TestCase
    func bucketIncludesRangeEdges(): Unit {
        let buckets = bucketItemsByDay(fixtureItems(), "2026-10-01", "2026-10-02")
        let keys = sortedKeys(buckets)
        @Expect(keys.size, 2)
        @Expect(keys[0], "2026-10-01")
        @Expect(keys[1], "2026-10-02")
    }

    @TestCase
    func bucketClipsCrossMonthItem(): Unit {
        let buckets = bucketItemsByDay(fixtureItems(), "2026-10-01", "2026-10-31")
        @Expect(idsOf(buckets, "2026-10-30"), "d")
        @Expect(idsOf(buckets, "2026-10-31"), "d,c")
        @Expect(buckets.contains("2026-11-01"), false)
    }

    @TestCase
    func bucketIgnoresUndatedAndOutOfRange(): Unit {
        let buckets = bucketItemsByDay(fixtureItems(), "2026-10-01", "2026-10-31")
        let seen = HashSet<String>()
        for ((_, list) in buckets) {
            for (item in list) {
                seen.add(item.id)
            }
        }
        @Expect(seen.contains("e"), false)
        @Expect(seen.contains("f"), false)
        @Expect(seen.contains("a"), true)
        @Expect(seen.contains("b"), true)
        @Expect(seen.contains("c"), true)
        @Expect(seen.contains("d"), true)
    }

    @TestCase
    func bucketSwapsReversedRange(): Unit {
        let forward = sortedKeys(bucketItemsByDay(fixtureItems(), "2026-10-01", "2026-10-02"))
        let reversed = sortedKeys(bucketItemsByDay(fixtureItems(), "2026-10-02", "2026-10-01"))
        @Expect(reversed.size, forward.size)
        for (index in 0..forward.size) {
            @Expect(reversed[index], forward[index])
        }
    }

    @TestCase
    func bucketRejectsInvalidRange(): Unit {
        @Expect(bucketItemsByDay(fixtureItems(), "", "2026-10-02").size, 0)
        @Expect(bucketItemsByDay(fixtureItems(), "2026-10-01", "").size, 0)
        @Expect(bucketItemsByDay(fixtureItems(), "bad", "2026-10-02").size, 0)
    }

    @TestCase
    func bucketSortsEachDay(): Unit {
        let buckets = bucketItemsByDay(fixtureItems(), "2026-10-01", "2026-10-31")
        // 2026-10-31 上，跨天条目 d 排在单日条目 c 之前
        @Expect(idsOf(buckets, "2026-10-31"), "d,c")
    }

    @TestCase
    func sortMultiDayFirstThenStartThenTitle(): Unit {
        let single = ganttItem("s", "B 单日", "2026-10-10", "2026-10-10")
        let sameDayA = ganttItem("sa", "A 单日", "2026-10-10", "2026-10-10")
        let span = ganttItem("sp", "跨天", "2026-10-08", "2026-10-11")
        let titles = titlesOf(sortDayItems([single, sameDayA, span]))
        @Expect(titles, "跨天|A 单日|B 单日")
    }

    @TestCase
    func sortIsStableForIdenticalItems(): Unit {
        let first = ganttItem("1", "同名", "2026-10-10", "2026-10-10")
        let second = ganttItem("2", "同名", "2026-10-10", "2026-10-10")
        let sorted = sortDayItems([first, second])
        @Expect(idsOfArray(sorted), "1,2")
    }

    @TestCase
    func sortByStartDateBeforeTitle(): Unit {
        let later = ganttItem("l", "A 晚", "2026-10-12", "2026-10-12")
        let earlier = ganttItem("e", "B 早", "2026-10-10", "2026-10-10")
        @Expect(idsOfArray(sortDayItems([later, earlier])), "e,l")
    }

    @TestCase
    func sortEmptyArray(): Unit {
        @Expect(sortDayItems(Array<CalItem>()).size, 0)
    }

    @TestCase
    func visibleItemsHidesDropped(): Unit {
        let done = makeItem("d", "已完成", "done")
        let dropped = makeItem("x", "已放弃", "dropped")
        @Expect(idsOfArray(visibleItems([done, dropped])), "d")
    }

    @TestCase
    func calendarItemsInRangeClipsAndFilters(): Unit {
        // 与 CalendarPage 的 visibleItems(scheduledItemsInRange(...)) 等价
        let kept = calendarItemsInRange(fixtureItems(), "2026-10-01", "2026-10-31")
        let ids = ArrayList<String>()
        for (item in kept) {
            ids.add(item.id)
        }
        @Expect(ids.size, 4)
        @Expect(ids.contains("a"), true)
        @Expect(ids.contains("b"), true)
        @Expect(ids.contains("c"), true)
        @Expect(ids.contains("d"), true)
        @Expect(ids.contains("e"), false)
        @Expect(ids.contains("f"), false)
    }

    @TestCase
    func statusLabels(): Unit {
        @Expect(statusLabel("inbox"), "收件箱")
        @Expect(statusLabel("next"), "下一步")
        @Expect(statusLabel("active"), "进行中")
        @Expect(statusLabel("waiting"), "等待中")
        @Expect(statusLabel("scheduled"), "已排期")
        @Expect(statusLabel("someday"), "将来")
        @Expect(statusLabel("done"), "已完成")
        @Expect(statusLabel("dropped"), "已放弃")
        @Expect(statusLabel("unknown"), "")
    }

    @TestCase
    func statusTones(): Unit {
        // 与 TS statusTone / statusColor 的语义令牌一一对应
        @Expect(statusTone("done"), "ok")
        @Expect(statusTone("waiting"), "warn")
        @Expect(statusTone("dropped"), "danger")
        @Expect(statusTone("scheduled"), "info")
        @Expect(statusTone("active"), "accent")
        @Expect(statusTone("next"), "neutral")
        @Expect(statusTone("inbox"), "neutral")
        @Expect(statusColorToken("done"), "ok")
        @Expect(statusColorToken("next"), "text-faint")
    }

    @TestCase
    func kindIcons(): Unit {
        @Expect(kindIcon("objective"), "target")
        @Expect(kindIcon("keyresult"), "target")
        @Expect(kindIcon("project"), "folder")
        @Expect(kindIcon("action"), "clock")
        @Expect(kindIcon("sop"), "workflow")
        @Expect(kindIcon("step"), "workflow")
        @Expect(kindIcon("milestone"), "flag")
        @Expect(kindIcon("reference"), "link")
        @Expect(kindIcon("note"), "edit")
        @Expect(kindIcon("unknown"), "edit")
    }

    @TestCase
    func routesForKind(): Unit {
        @Expect(routeForKind("project"), "gantt")
        @Expect(routeForKind("action"), "gantt")
        @Expect(routeForKind("milestone"), "gantt")
        @Expect(routeForKind("sop"), "sop")
        @Expect(routeForKind("step"), "sop")
        @Expect(routeForKind("objective"), "okr")
        @Expect(routeForKind("keyresult"), "okr")
        @Expect(routeForKind("note"), "gtd")
        @Expect(routeForKind("reference"), "gtd")
    }

    @TestCase
    func doneItemDetection(): Unit {
        @Expect(isDoneItem(makeItem("d", "d", "done")), true)
        @Expect(isDoneItem(makeItem("n", "n", "next")), false)
    }

    func fixtureItems(): Array<CalItem> {
        return [
            ganttItem("a", "跨天任务", "2026-09-29", "2026-10-02"),
            ganttItem("b", "只有截止日", "", "2026-10-05"),
            ganttItem("c", "月末单日", "2026-10-31", "2026-10-31"),
            ganttItem("d", "跨到下月", "2026-10-30", "2026-11-02"),
            ganttItem("e", "完全在区间外", "2026-11-10", "2026-11-12"),
            makeItem("f", "没有日期")
        ]
    }
}

/** 测试用条目：无日期。 */
func makeItem(id: String, title: String): CalItem {
    return CalItem(id, title, "action", "next", "", "", "", false)
}

/** 测试用条目：无日期，显式状态。 */
func makeItem(id: String, title: String, status: String): CalItem {
    return CalItem(id, title, "action", status, "", "", "", false)
}

/** 测试用条目：带起止日（相当于 `gantt: { start, end }`）。 */
func ganttItem(id: String, title: String, start: String, end: String): CalItem {
    return CalItem(id, title, "action", "next", start, end, "", false)
}

/** 分桶结果里某一天的条目 id（按顺序用 `,` 连接）。 */
func idsOf(buckets: HashMap<String, Array<CalItem>>, day: String): String {
    match (buckets.get(day)) {
        case Some(list) => return idsOfArray(list)
        case None => return ""
    }
}

func idsOfArray(items: Array<CalItem>): String {
    let ids = ArrayList<String>()
    for (item in items) {
        ids.add(item.id)
    }
    return String.join(ids.toArray(), delimiter: ",")
}

func titlesOf(items: Array<CalItem>): String {
    let titles = ArrayList<String>()
    for (item in items) {
        titles.add(item.title)
    }
    return String.join(titles.toArray(), delimiter: "|")
}

func sortedKeys(buckets: HashMap<String, Array<CalItem>>): Array<String> {
    let keys = ArrayList<String>()
    for ((key, _) in buckets) {
        keys.add(key)
    }
    let result = keys.toArray()
    sort<String>(result, lessThan: {left, right => left < right})
    return result
}
