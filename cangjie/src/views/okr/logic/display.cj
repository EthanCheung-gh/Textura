package textura.views.okr.logic

import std.unicode.*

/*
 * 展示映射（只做格式化，不含业务判定），对应 `src/modules/okr/okrDisplay.ts`。
 * 色调用枚举表示，视图层再映射到 `textura.ui` 的 Badge / Progress 令牌；
 * 本包不 import `cui`，也不写十六进制颜色。
 */

/** 对应 `BadgeTone`。 */
public enum BadgeTone <: Equatable<BadgeTone> {
    | Neutral
    | Info
    | Accent
    | Warn
    | Ok
    | Danger

    public operator func ==(that: BadgeTone): Bool {
        badgeToneText(this) == badgeToneText(that)
    }

    public operator func !=(that: BadgeTone): Bool {
        !(this == that)
    }
}

public func badgeToneText(tone: BadgeTone): String {
    match (tone) {
        case BadgeTone.Neutral => "neutral"
        case BadgeTone.Info => "info"
        case BadgeTone.Accent => "accent"
        case BadgeTone.Warn => "warn"
        case BadgeTone.Ok => "ok"
        case BadgeTone.Danger => "danger"
    }
}

/** 对应 `ProgressTone`（进度条只用这四档）。 */
public enum ProgressTone <: Equatable<ProgressTone> {
    | Info
    | Accent
    | Ok
    | Danger

    public operator func ==(that: ProgressTone): Bool {
        progressToneText(this) == progressToneText(that)
    }

    public operator func !=(that: ProgressTone): Bool {
        !(this == that)
    }
}

public func progressToneText(tone: ProgressTone): String {
    match (tone) {
        case ProgressTone.Info => "info"
        case ProgressTone.Accent => "accent"
        case ProgressTone.Ok => "ok"
        case ProgressTone.Danger => "danger"
    }
}

/** `STATUS_TONE` 映射表。 */
public func statusTone(status: OkrItemStatus): BadgeTone {
    match (status) {
        case OkrItemStatus.Inbox => BadgeTone.Neutral
        case OkrItemStatus.Next => BadgeTone.Info
        case OkrItemStatus.Active => BadgeTone.Accent
        case OkrItemStatus.Waiting => BadgeTone.Warn
        case OkrItemStatus.Scheduled => BadgeTone.Info
        case OkrItemStatus.Someday => BadgeTone.Neutral
        case OkrItemStatus.Done => BadgeTone.Ok
        case OkrItemStatus.Dropped => BadgeTone.Neutral
    }
}

public func progressTone(progress: Float64, behind: Bool): ProgressTone {
    if (behind) {
        return ProgressTone.Danger
    }
    if (progress >= 100.0) {
        return ProgressTone.Ok
    }
    if (progress <= 0.0) {
        return ProgressTone.Info
    }
    ProgressTone.Accent
}

/** 非有限值显示破折号；整数不带小数点，其余四舍五入到 2 位并去掉末尾零。 */
public func formatNumber(value: Float64): String {
    if (!isFiniteNumber(value)) {
        return "—"
    }
    if (value == jsTrunc(value)) {
        return jsNumberToString(value)
    }
    jsFixedNumberToString(value, 2)
}

/** 百分号紧跟数字，其他单位用空格分隔。 */
public func unitSuffix(unit: String): String {
    if (unit.isEmpty()) {
        return ""
    }
    if (unit == "%") {
        return "%"
    }
    " " + unit
}

/** 指标摘要：`2.1 → 3%`；无指标时为「未设指标」。 */
public func formatMetric(metric: ?OkrMetric): String {
    if (metric.isNone()) {
        return "未设指标"
    }
    let value = metric.getOrThrow()
    formatNumber(value.start) + " → " + formatNumber(value.target) + unitSuffix(value.unit)
}

/** `YYYY-MM-DD(THH:mm…)` -> `MM/dd`；空或非法返回破折号（等价 `formatDateKey`）。 */
public func formatDateKeyMmDd(value: ?String): String {
    let raw = match (value) {
        case Some(text) => text
        case None => ""
    }
    if (raw.trim().isEmpty()) {
        return "—"
    }
    let dateOption = parseCivilDateKey(raw)
    if (dateOption.isNone()) {
        return "—"
    }
    let date = dateOption.getOrThrow()
    let month = if (date.month < 10) {
        "0" + date.month.toString()
    } else {
        date.month.toString()
    }
    let day = if (date.day < 10) {
        "0" + date.day.toString()
    } else {
        date.day.toString()
    }
    month + "/" + day
}

/** 排期摘要：`02/01 – 03/15`；两端都缺失时为「未排期」。 */
public func formatSchedule(schedule: ?OkrSchedule): String {
    if (schedule.isNone()) {
        return "未排期"
    }
    let value = schedule.getOrThrow()
    let startText = presentOrEmpty(value.start)
    let endText = presentOrEmpty(value.end)
    if (startText.isEmpty() && endText.isEmpty()) {
        return "未排期"
    }
    formatDateKeyMmDd(Some(startText)) + " – " + formatDateKeyMmDd(Some(endText))
}

/** JS 真值语义：`null` 与空串都当「没有」。 */
private func presentOrEmpty(value: ?String): String {
    match (value) {
        case Some(text) =>
            if (text.isEmpty()) {
                ""
            } else {
                text
            }
        case None => ""
    }
}
