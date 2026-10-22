package textura.views.calendar.logic

import std.collection.*

/**
 * 日历文案层：农历标签优先级、星期/月/周标题、无障碍标签、相对日期。
 * 与 `src/modules/calendar/calendarLogic.ts` 中的同名函数逐条对应。
 */

/** 窄视口断点：≤1180 时日程面板折叠为底部抽屉。 */
public let PANEL_BREAKPOINT: Int64 = 1180

/** 月视图 / 周视图。 */
public enum CalendarViewMode {
    | Month
    | Week
}

/** 星期短名（周一为首）。 */
public let WEEKDAY_LABELS: Array<String> = ["一", "二", "三", "四", "五", "六", "日"]

/** 星期全名。 */
public let WEEKDAY_FULL_CN: Array<String> = [
    "星期一",
    "星期二",
    "星期三",
    "星期四",
    "星期五",
    "星期六",
    "星期日"
]

/** 月份选择器文案。 */
public let MONTH_NAMES_CN: Array<String> = [
    "一月",
    "二月",
    "三月",
    "四月",
    "五月",
    "六月",
    "七月",
    "八月",
    "九月",
    "十月",
    "十一月",
    "十二月"
]

/** 农历标签类别。 */
public enum LunarLabelKind <: Equatable<LunarLabelKind> {
    /** 传统节日（含除夕、清明）。 */
    | Festival
    /** 二十四节气。 */
    | Term
    /** 农历日 / 初一显示月名。 */
    | Lunar
    /** 超出农历支持范围，只显示公历。 */
    | NoLabel

    /** 判别序号（用于相等比较与排序）。 */
    public func index(): Int64 {
        return match (this) {
            case Festival => 0
            case Term => 1
            case Lunar => 2
            case NoLabel => 3
        }
    }

    public operator func ==(other: LunarLabelKind): Bool {
        return index() == other.index()
    }

    public operator func !=(other: LunarLabelKind): Bool {
        return index() != other.index()
    }
}

/** 农历标签。 */
public struct LabelTone <: Equatable<LabelTone> {
    public let kind: LunarLabelKind
    public let text: String

    public init(kind: LunarLabelKind, text: String) {
        this.kind = kind
        this.text = text
    }

    public operator func ==(other: LabelTone): Bool {
        return kind == other.kind && text == other.text
    }

    public operator func !=(other: LabelTone): Bool {
        return !(this == other)
    }

    public func toString(): String {
        return text
    }
}

/** 下拉选项。 */
public struct SelectOption <: Equatable<SelectOption> {
    public let value: String
    public let label: String

    public init(value: String, label: String) {
        this.value = value
        this.label = label
    }

    public operator func ==(other: SelectOption): Bool {
        return value == other.value && label == other.label
    }

    public operator func !=(other: SelectOption): Bool {
        return !(this == other)
    }
}

/**
 * 窄屏选中日期时是否应自动展开日程面板。
 *
 * 规则：面板当前收起、视口处于窄屏（≤ breakpoint）、且本次会话中用户没有手动收起过。
 */
public func shouldAutoOpenPanel(
    panelOpen: Bool,
    viewportWidth: Int64,
    userCollapsed: Bool
): Bool {
    return shouldAutoOpenPanel(panelOpen, viewportWidth, userCollapsed, PANEL_BREAKPOINT)
}

/** 同上，显式指定断点（含边界）。 */
public func shouldAutoOpenPanel(
    panelOpen: Bool,
    viewportWidth: Int64,
    userCollapsed: Bool,
    breakpoint: Int64
): Bool {
    if (panelOpen) {
        return false
    }
    if (userCollapsed) {
        return false
    }
    return viewportWidth <= breakpoint
}

/** 星期全名（`星期一` … `星期日`）；非法日期键按 TS 返回 `星期一`。 */
public func weekdayLabel(key: String): String {
    return WEEKDAY_FULL_CN[weekdayOfKey(key)]
}

/** 月份标题：`2026年10月`。 */
public func monthLabel(year: Int64, month: Int64): String {
    return "${year.toString()}年${month.toString()}月"
}

/** 周区间标题：`10月19日 – 25日`（跨年时带上年份）。 */
public func weekLabel(key: String): String {
    let range = weekRange(key)
    let start = range.start
    let finish = range.end
    let prefix = if (range.year == finish.year) {
        ""
    } else {
        "${range.year.toString()}年"
    }
    if (start.month == finish.month) {
        return "${prefix}${start.month.toString()}月${start.day.toString()}日 – ${finish.day.toString()}日"
    }
    return "${prefix}${start.month.toString()}月${start.day.toString()}日 – ${finish.month.toString()}月${finish.day.toString()}日"
}

/** 日期键 → 农历；非法或超出范围返回 `None`。 */
public func lunarOf(key: String): ?LunarDate {
    return solarToLunar(key)
}

/**
 * 农历标签优先级：传统节日 > 节气 > 农历日（初一显示月名）。
 * 超出农历支持范围时返回 `NoLabel`（只显示公历）。
 */
public func lunarLabelOf(lunar: ?LunarDate): LabelTone {
    if (lunar.isNone()) {
        return LabelTone(LunarLabelKind.NoLabel, "")
    }
    let date = lunar.getOrThrow()
    if (let Some(festival) <- date.festival) {
        return LabelTone(LunarLabelKind.Festival, festival)
    }
    if (let Some(term) <- date.solarTerm) {
        return LabelTone(LunarLabelKind.Term, term)
    }
    if (date.day == 1) {
        return LabelTone(LunarLabelKind.Lunar, date.monthName)
    }
    return LabelTone(LunarLabelKind.Lunar, date.dayName)
}

/** 农历标签（内部只换算一次农历）。 */
public func lunarLabelInfo(key: String): LabelTone {
    return lunarLabelOf(lunarOf(key))
}

/** 农历标签文本。 */
public func lunarLabel(key: String): String {
    return lunarLabelInfo(key).text
}

/** 农历全称：`丙午年 九月十二`。 */
public func lunarFullLabel(lunar: LunarDate): String {
    return "${lunar.ganzhiYear}年 ${lunar.monthName}${lunar.dayName}"
}

/** `2026年10月21日 星期三`。 */
public func fullDateLabel(key: String): String {
    match (parseKey(key)) {
        case Some(date) => return "${date.year.toString()}年${date.month.toString()}月${date.day.toString()}日 ${weekdayLabel(key)}"
        case None => return ""
    }
}

/**
 * 网格单元格的无障碍名称：`2026年10月21日，星期三，农历九月十二，今天`。
 * 节日优先于节气；今天是节气时写「秋分节气」。
 */
public func cellAriaLabelOf(key: String, lunar: ?LunarDate, today: String): String {
    let date = match (parseKey(key)) {
        case Some(value) => value
        case None => return ""
    }
    let parts = ArrayList<String>()
    parts.add("${date.year.toString()}年${date.month.toString()}月${date.day.toString()}日")
    parts.add(weekdayLabel(key))
    if (let Some(info) <- lunar) {
        parts.add("农历${info.monthName}${info.dayName}")
        let festival = info.festival
        if (festival.isSome() && festival != info.solarTerm) {
            parts.add(festival.getOrThrow())
        } else if (let Some(term) <- info.solarTerm) {
            parts.add("${term}节气")
        }
    }
    if (today.size > 0 && key == today) {
        parts.add("今天")
    }
    return String.join(parts.toArray(), delimiter: "，")
}

/** 便捷版本：内部换算一次农历。 */
public func cellAriaLabel(key: String, today: String): String {
    return cellAriaLabelOf(key, lunarOf(key), today)
}

/** 相对今天的文案：今天 / 明天 / 昨天 / n 天后 / n 天前。 */
public func relativeDayLabel(key: String, today: String): String {
    let target = dayNumberOfKey(key)
    let base = dayNumberOfKey(today)
    if (target.isNone() || base.isNone()) {
        return ""
    }
    let diff = target.getOrThrow() - base.getOrThrow()
    if (diff == 0) {
        return "今天"
    }
    if (diff == 1) {
        return "明天"
    }
    if (diff == -1) {
        return "昨天"
    }
    return if (diff > 0) {
        "${diff.toString()} 天后"
    } else {
        "${(-diff).toString()} 天前"
    }
}

/** 月份选择器选项 1..12。 */
public func monthOptions(): Array<SelectOption> {
    let options = Array<SelectOption>(12, repeat: SelectOption("", ""))
    for (index in 0..12) {
        options[index] = SelectOption((index + 1).toString(), MONTH_NAMES_CN[index])
    }
    return options
}

/** 年份选择器选项 1900..2100。 */
public func yearOptions(): Array<SelectOption> {
    let options = Array<SelectOption>(201, repeat: SelectOption("", ""))
    for (index in 0..=200) {
        let year = 1900 + index
        options[index] = SelectOption(year.toString(), "${year.toString()}年")
    }
    return options
}
