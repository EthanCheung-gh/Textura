package textura.views.dashboard.logic

import std.collection.*
import std.deriving.*

/** 今日聚焦的三个分组；权重决定组间顺序（超期 → 今天 → 无日期）。 */
@Derive[Equatable]
public enum FocusBucket {
    | Overdue
    | Today
    | Undated
}

/** 条目来自 SOP / OKR 的标记。命名带 `Source` 前缀以避免与 `DashKind` 的构造器重名。 */
@Derive[Equatable]
public enum FocusSource {
    | SourceSop
    | SourceOkr
}

/** 今日聚焦首屏最多渲染的条数（Web 版 `FOCUS_PAGE_SIZE`）。 */
public const FOCUS_PAGE_SIZE: Int64 = 100

/** 一条今日聚焦条目。`due`/`daysLate`/`pathTitles`/`source` 均为展示派生值。 */
public struct FocusEntry {
    public let item: DashItem
    public let bucket: FocusBucket
    /** 截止日期 `YYYY-MM-DD`。 */
    public let due: ?String
    /** 超期天数；仅 `Overdue` 分组有值，且至少为 1。 */
    public let daysLate: Int64
    /** 根 → 自身。 */
    public let pathTitles: Array<String>
    public let source: ?FocusSource

    public init(
        item: DashItem,
        bucket: FocusBucket,
        due: ?String,
        daysLate: Int64,
        pathTitles: Array<String>,
        source: ?FocusSource
    ) {
        this.item = item
        this.bucket = bucket
        this.due = due
        this.daysLate = daysLate
        this.pathTitles = pathTitles
        this.source = source
    }
}

/** `countFocusBuckets` 的结果。 */
@Derive[Equatable]
public struct FocusCounts {
    public let overdue: Int64
    public let today: Int64
    public let undated: Int64

    public init(overdue: Int64, today: Int64, undated: Int64) {
        this.overdue = overdue
        this.today = today
        this.undated = undated
    }
}

/** `paginateFocus` 的结果。 */
public struct FocusPage {
    public let items: Array<FocusEntry>
    public let shown: Int64
    public let total: Int64
    public let remaining: Int64
    public let hasMore: Bool

    public init(items: Array<FocusEntry>, shown: Int64, total: Int64, remaining: Int64, hasMore: Bool) {
        this.items = items
        this.shown = shown
        this.total = total
        this.remaining = remaining
        this.hasMore = hasMore
    }
}

/** 与 `getWorkspaceIndex` 等价的极简索引：`byId` 后者覆盖、插入序取首次出现。 */
class DashIndex {
    let byId: HashMap<String, DashItem>
    let insertionOrder: ArrayList<String>

    init(items: Array<DashItem>) {
        this.byId = HashMap<String, DashItem>()
        this.insertionOrder = ArrayList<String>()
        for (item in items) {
            if (this.byId.contains(item.id)) {
                this.byId[item.id] = item
            } else {
                this.byId[item.id] = item
                this.insertionOrder.add(item.id)
            }
        }
    }

    func item(id: String): ?DashItem {
        return this.byId.get(id)
    }

    /** 祖先链：从直接父级到根（最近优先），带环保护——与 `selectors.ancestorsOf` 一致。 */
    func ancestorsOf(id: String): Array<DashItem> {
        let result = ArrayList<DashItem>()
        let seen = HashSet<String>()
        seen.add(id)
        var currentId: ?String = None
        if (let Some(item) <- this.byId.get(id)) {
            currentId = item.parentId
        }
        while (let Some(parentId) <- currentId) {
            if (seen.contains(parentId)) {
                break
            }
            if (let Some(parent) <- this.byId.get(parentId)) {
                result.add(parent)
                seen.add(parentId)
                currentId = parent.parentId
            } else {
                break
            }
        }
        return result.toArray()
    }
}

func bucketWeight(bucket: FocusBucket): Int64 {
    match (bucket) {
        case Overdue => 0
        case Today => 1
        case Undated => 2
    }
}

func sourceOf(item: DashItem, ancestors: Array<DashItem>): ?FocusSource {
    if (item.kind == DashKind.Sop || item.kind == DashKind.Step) {
        return Some(FocusSource.SourceSop)
    }
    if (item.kind == DashKind.Objective || item.kind == DashKind.KeyResult) {
        return Some(FocusSource.SourceOkr)
    }
    for (ancestor in ancestors) {
        if (ancestor.kind == DashKind.Sop) {
            return Some(FocusSource.SourceSop)
        }
    }
    for (ancestor in ancestors) {
        if (ancestor.kind == DashKind.Objective || ancestor.kind == DashKind.KeyResult) {
            return Some(FocusSource.SourceOkr)
        }
    }
    return None
}

/** 最终的组间 / 组内排序规则（与 Web 版比较器等价）。 */
func compareFocus(left: FocusEntry, right: FocusEntry): Int64 {
    let weightDiff = bucketWeight(left.bucket) - bucketWeight(right.bucket)
    if (weightDiff != 0) {
        return weightDiff
    }
    if (left.bucket == FocusBucket.Overdue) {
        let dueDiff = compareText(orEmpty(left.due), orEmpty(right.due))
        if (dueDiff != 0) {
            return dueDiff
        }
    }
    let orderDiff = left.item.order - right.item.order
    if (orderDiff != 0) {
        return orderDiff
    }
    return compareText(left.item.createdAt, right.item.createdAt)
}

/**
 * 今日聚焦：超期 + 今日到期 + 无 end 的下一步，按 id 去重（超期 > 今天 > 无日期），
 * 再按分组与组内规则排序。
 *
 * 「今天」由调用方注入（`YYYY-MM-DD` 或 ISO 时间串），不读系统时钟。
 */
public func buildTodayFocus(items: Array<DashItem>, today: String): Array<FocusEntry> {
    let todayKey = match (dateKeyOf(today)) {
        case Some(key) => key
        case None => today
    }
    let index = DashIndex(items)

    // 超期：end < today 且未完成/未放弃；候选顺序按 byId 插入序，随后按 due 升序稳定排序。
    let overdue = ArrayList<DashItem>()
    for (id in index.insertionOrder) {
        if (let Some(item) <- index.item(id)) {
            if (let Some(end) <- dateKeyOf(item.dueDate)) {
                if (end < todayKey && isOpen(item.status)) {
                    overdue.add(item)
                }
            }
        }
    }
    let overdueSorted = stableSortBy<DashItem>(
        overdue.toArray(),
        {
            left, right => return compareText(orEmpty(dateKeyOf(left.dueDate)), orEmpty(dateKeyOf(right.dueDate)))
        }
    )

    // 今天到期：end == today 且未完成/未放弃，保持 byId 插入序。
    let dueToday = ArrayList<DashItem>()
    for (id in index.insertionOrder) {
        if (let Some(item) <- index.item(id)) {
            if (let Some(end) <- dateKeyOf(item.dueDate)) {
                if (end == todayKey && isOpen(item.status)) {
                    dueToday.add(item)
                }
            }
        }
    }

    // 下一步：action / project 且 status == next；有截止日期的已归入超期/今天或属于未来排期。
    let undated = ArrayList<DashItem>()
    for (item in items) {
        if (item.status != DashStatus.Next) {
            continue
        }
        if (item.kind != DashKind.Action && item.kind != DashKind.Project) {
            continue
        }
        if (dateKeyOf(item.dueDate).isSome()) {
            continue
        }
        undated.add(item)
    }
    let undatedSorted = stableSortBy<DashItem>(
        undated.toArray(),
        {
            left, right =>
                let orderDiff = left.order - right.order
                if (orderDiff != 0) {
                    return orderDiff
                }
                return compareText(left.createdAt, right.createdAt)
        }
    )

    let candidates = ArrayList<(DashItem, FocusBucket)>()
    for (item in overdueSorted) {
        candidates.add((item, FocusBucket.Overdue))
    }
    for (item in dueToday) {
        candidates.add((item, FocusBucket.Today))
    }
    for (item in undatedSorted) {
        candidates.add((item, FocusBucket.Undated))
    }

    let entries = ArrayList<FocusEntry>()
    let seen = HashSet<String>()
    for (pair in candidates) {
        let item = pair[0]
        let bucket = pair[1]
        if (seen.contains(item.id)) {
            continue
        }
        seen.add(item.id)
        let due = dateKeyOf(item.dueDate)
        let ancestorsNearestFirst = index.ancestorsOf(item.id)
        let titles = ArrayList<String>()
        var position = ancestorsNearestFirst.size - 1
        while (position >= 0) {
            titles.add(ancestorsNearestFirst[position].title)
            position -= 1
        }
        titles.add(item.title)
        let daysLate = if (bucket == FocusBucket.Overdue) {
            daysLateFor(todayKey, due)
        } else {
            0
        }
        entries.add(FocusEntry(item, bucket, due, daysLate, titles.toArray(), sourceOf(item, ancestorsNearestFirst)))
    }

    return stableSortBy<FocusEntry>(entries.toArray(), compareFocus)
}

/** 各分组的条目数。 */
public func countFocusBuckets(entries: Array<FocusEntry>): FocusCounts {
    var overdue = 0
    var today = 0
    var undated = 0
    for (entry in entries) {
        match (entry.bucket) {
            case Overdue => overdue += 1
            case Today => today += 1
            case Undated => undated += 1
        }
    }
    return FocusCounts(overdue, today, undated)
}

/**
 * 取前 `limit` 条；`limit` 为负数时按 0 处理。
 *
 * Web 版额外用 `Number.isFinite(limit)` 拦截 `NaN`/`Infinity`；仓颉的 `Int64` 参数在编译期
 * 就不可能出现非有限值，因此该分支不存在，可表示输入上的行为完全一致。
 */
public func paginateFocus(entries: Array<FocusEntry>, limit: Int64): FocusPage {
    let total = entries.size
    let safeLimit = if (limit < 0) {
        0
    } else {
        limit
    }
    let shown = if (safeLimit < total) {
        safeLimit
    } else {
        total
    }
    let page = ArrayList<FocusEntry>()
    var index = 0
    while (index < shown) {
        page.add(entries[index])
        index += 1
    }
    return FocusPage(page.toArray(), shown, total, total - shown, shown < total)
}
