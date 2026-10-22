package textura.views.dashboard.logic

import std.collection.*

/**
 * `src/modules/dashboard/todayPaging.test.ts` 的逐条移植。
 *
 * 唯一无法照搬的断言是 Web 版对 `Number.NaN` 的处理：仓颉 `Int64` 参数不存在非有限值，
 * 这里用负数与 0 覆盖「非法 limit 按 0 处理」的等价分支。
 */
func pagingEntry(index: Int64): FocusEntry {
    let item = DashItem("a" + index.toString(), "行动 " + index.toString(), order: index)
    return FocusEntry(item, FocusBucket.Undated, None, 0, [item.title], None)
}

func pagingEntries(count: Int64): Array<FocusEntry> {
    let list = ArrayList<FocusEntry>()
    var index = 0
    while (index < count) {
        list.add(pagingEntry(index))
        index += 1
    }
    return list.toArray()
}

@Test
func paginateFocusEmptyTest(): Unit {
    let page = paginateFocus(Array<FocusEntry>(), FOCUS_PAGE_SIZE)
    @Expect(page.items.size, 0)
    @Expect(page.shown, 0)
    @Expect(page.total, 0)
    @Expect(page.remaining, 0)
    @Expect(page.hasMore, false)
}

@Test
func paginateFocusFullPageTest(): Unit {
    let page99 = paginateFocus(pagingEntries(99), FOCUS_PAGE_SIZE)
    @Expect(page99.shown, 99)
    @Expect(page99.total, 99)
    @Expect(page99.remaining, 0)
    @Expect(page99.hasMore, false)

    let page100 = paginateFocus(pagingEntries(100), FOCUS_PAGE_SIZE)
    @Expect(page100.shown, 100)
    @Expect(page100.items.size, 100)
    @Expect(page100.remaining, 0)
    @Expect(page100.hasMore, false)
}

@Test
func paginateFocusTruncatesTest(): Unit {
    let page = paginateFocus(pagingEntries(101), FOCUS_PAGE_SIZE)
    @Expect(page.items.size, 100)
    @Expect(page.items[99].item.id, "a99")
    @Expect(page.total, 101)
    @Expect(page.remaining, 1)
    @Expect(page.hasMore, true)
}

@Test
func paginateFocusInvalidLimitTest(): Unit {
    @Expect(paginateFocus([pagingEntry(0)], -5).items.size, 0)
    @Expect(paginateFocus([pagingEntry(0)], 0).items.size, 0)
    @Expect(paginateFocus([pagingEntry(0)], 1).items.size, 1)
}
