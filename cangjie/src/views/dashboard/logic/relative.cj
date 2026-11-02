package textura.views.dashboard.logic

/**
 * 相对时间（中文）。
 *
 * 逐行移植 `date-fns@4 formatDistance` + `zh-CN` locale 的 `formatDistanceToNow(date, { addSuffix: true })`：
 * 同样的分钟取整、分档阈值、月份/年份措辞与「前 / 内」后缀。「现在」由调用方注入。
 *
 * 与 Web 版的唯一输入差异：Web 版走 `new Date(iso)`，可解析非 ISO 串；这里只接受
 * `date.cj` 里 `parseInstantMs` 支持的 ISO 形式，其余返回 `—`（与 Web 版非法输入的输出一致）。
 */
public func relativeTime(iso: ?String, nowIso: String): String {
    if (isNonEmpty(iso)) {
        if (let Some(dateMs) <- parseInstantMs(orEmpty(iso))) {
            if (let Some(nowMs) <- parseInstantMs(nowIso)) {
                return formatDistanceZh(dateMs, nowMs)
            }
        }
    }
    return "—"
}

func compareMs(left: Int64, right: Int64): Int64 {
    if (left < right) {
        return -1
    }
    if (left > right) {
        return 1
    }
    return 0
}

/** `Math.round(seconds / 60)`；`seconds` 非负。 */
func minutesOf(seconds: Int64): Int64 {
    return (seconds * 2 + 60) / 120
}

/**
 * `date-fns differenceInMonths`：完整月份数（不完整月不计），带 JS `Date.setMonth` 的溢出规则。
 */
func differenceInMonths(laterMs: Int64, earlierMs: Int64): Int64 {
    let sign = compareMs(laterMs, earlierMs)
    let later = localDateTimeOf(laterMs)
    let earlier = localDateTimeOf(earlierMs)
    let laterMonths = later.date.year * 12 + (later.date.month - 1)
    let earlierMonths = earlier.date.year * 12 + (earlier.date.month - 1)
    let difference = if (laterMonths >= earlierMonths) {
        laterMonths - earlierMonths
    } else {
        earlierMonths - laterMonths
    }
    if (difference < 1) {
        return 0
    }

    var workingMs = laterMs
    let working = localDateTimeOf(workingMs)
    // date-fns：2 月 28 日之后统一按 30 日回退，避免"2 月 28 日 - 1 个月"落到 1 月 28 日。
    if (working.date.month == 2 && working.date.day > 27) {
        workingMs = withLocalDay(workingMs, 30)
    }
    workingMs = addLocalMonths(workingMs, -sign * difference)

    var isLastMonthNotFull = compareMs(workingMs, earlierMs) == -sign
    if (isLastDayOfMonth(laterMs) && difference == 1 && compareMs(laterMs, earlierMs) == 1) {
        isLastMonthNotFull = false
    }
    let notFull = if (isLastMonthNotFull) {
        1
    } else {
        0
    }
    let result = sign * (difference - notFull)
    return if (result == 0) {
        0
    } else {
        result
    }
}

/** `zh-CN` 的 `lessThanXMinutes` / `xMinutes` / … / `almostXYears` 文案与「前 / 内」后缀。 */
func formatDistanceZh(dateMs: Int64, nowMs: Int64): String {
    let comparison = compareMs(dateMs, nowMs)
    let laterMs = if (comparison > 0) {
        dateMs
    } else {
        nowMs
    }
    let earlierMs = if (comparison > 0) {
        nowMs
    } else {
        dateMs
    }
    let seconds = (laterMs - earlierMs) / 1000
    let minutes = minutesOf(seconds)
    let suffix = if (comparison > 0) {
        "内"
    } else {
        "前"
    }

    var text = ""
    if (minutes < 2) {
        if (minutes == 0) {
            text = "不到 1 分钟"
        } else {
            text = minutes.toString() + " 分钟"
        }
    } else if (minutes < 45) {
        text = minutes.toString() + " 分钟"
    } else if (minutes < 90) {
        text = "大约 1 小时"
    } else if (minutes < 1440) {
        text = "大约 " + roundHalfUp(minutes, 60).toString() + " 小时"
    } else if (minutes < 2520) {
        text = "1 天"
    } else if (minutes < 43200) {
        text = roundHalfUp(minutes, 1440).toString() + " 天"
    } else if (minutes < 86400) {
        text = "大约 " + roundHalfUp(minutes, 43200).toString() + " 个月"
    } else {
        let months = differenceInMonths(laterMs, earlierMs)
        if (months < 12) {
            text = roundHalfUp(minutes, 43200).toString() + " 个月"
        } else {
            let monthsSinceStartOfYear = months % 12
            let years = months / 12
            if (monthsSinceStartOfYear < 3) {
                text = "大约 " + years.toString() + " 年"
            } else if (monthsSinceStartOfYear < 9) {
                text = "超过 " + years.toString() + " 年"
            } else {
                text = "将近 " + (years + 1).toString() + " 年"
            }
        }
    }
    return text + suffix
}
