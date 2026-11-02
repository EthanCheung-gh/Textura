package textura.views.gantt

import cui.*
import textura.ui.*

/*
 * gantt.css 里用 `color-mix()` 表达、设计令牌里没有直接对应的派生色。
 *
 * `color-mix(in srgb, A p%, B)` 在 sRGB 空间做线性插值；`color-mix(in srgb, A p%,
 * transparent)` 等价于“同色 + p% alpha”（与 textura.ui 的 `tint()` 同义），因此这里分成两类：
 * - 与另一种**不透明**颜色混合 → `mixColor()` 直接算出结果色（CSS 也是不透明结果）；
 * - 与 `transparent` 混合 → `tint()`，保留 alpha 交给合成器叠加（与浏览器一致）。
 *
 * 每项都标注 gantt.css 行号，改样式请同步改这里。
 */
class GanttInk {
    /** gantt.css:7 `--gantt-strong-border: color-mix(in srgb, text-faint 55%, border-strong)` */
    let strongBorder: Color

    /** gantt.css:132 `.gantt-tree-row` 底部细线 `color-mix(border 55%, transparent)` */
    let treeRowLine: Color

    /** gantt.css:468 `.gantt-row` 底部细线 `color-mix(border 45%, transparent)` */
    let timelineRowLine: Color

    /** gantt.css:518 `.gantt-grid-line` `color-mix(border 55%, transparent)` */
    let gridLine: Color

    /** gantt.css:414 `.gantt-header-col` 左边线 `color-mix(border 60%, transparent)` */
    let columnLine: Color

    /** gantt.css:496 `.gantt-past` `background: bg-subtle; opacity: .45` */
    let past: Color

    /** gantt.css:505 `.gantt-weekend` `background: bg-subtle; opacity: .62` */
    let weekend: Color

    /** gantt.css:477 `.gantt-row.is-group` `color-mix(bg-subtle 72%, transparent)` */
    let groupRow: Color

    /** gantt.css:486 `.gantt-row.is-group.is-selected` `color-mix(accent-soft 78%, bg-subtle)` */
    let groupRowSelected: Color

    /** gantt.css:586 `.gantt-bar-fill` `color-mix(accent 26%, transparent)` */
    let barFill: Color

    /** gantt.css:591 `.gantt-bar.is-done .gantt-bar-fill` `color-mix(ok 30%, transparent)` */
    let barFillDone: Color

    /** gantt.css:566 `.gantt-bar.is-overdue` 外环 `color-mix(danger 50%, transparent)` */
    let overdueRing: Color

    /** gantt.css:706 `.gantt-summary-bar.is-selected` 外环 `color-mix(accent-ink 45%, transparent)` */
    let summaryRing: Color

    init(tokens: ThemeTokens) {
        let c = tokens.color
        strongBorder = mixColor(c.textFaint, c.borderStrong, 55.0)
        treeRowLine = tint(c.border, 55.0)
        timelineRowLine = tint(c.border, 45.0)
        gridLine = tint(c.border, 55.0)
        columnLine = tint(c.border, 60.0)
        past = tint(c.bgSubtle, 45.0)
        weekend = tint(c.bgSubtle, 62.0)
        groupRow = tint(c.bgSubtle, 72.0)
        groupRowSelected = mixColor(c.accentSoft, c.bgSubtle, 78.0)
        barFill = tint(c.accent, 26.0)
        barFillDone = tint(c.ok, 30.0)
        overdueRing = tint(c.danger, 50.0)
        summaryRing = tint(c.accentInk, 45.0)
    }
}

/** `color-mix(in srgb, a weight%, b)`：按 sRGB 通道线性插值并四舍五入到 0..255。 */
func mixColor(a: Color, b: Color, weight: Float32): Color {
    let p = clampUnit(weight / 100.0)
    let q = 1.0 - p
    Color.rgb(
        Int64(Float32(a.r) * p + Float32(b.r) * q + 0.5),
        Int64(Float32(a.g) * p + Float32(b.g) * q + 0.5),
        Int64(Float32(a.b) * p + Float32(b.b) * q + 0.5)
    )
}

func clampUnit(value: Float32): Float32 {
    if (value < 0.0) {
        0.0
    } else if (value > 1.0) {
        1.0
    } else {
        value
    }
}

/** `theme` 名称 → 令牌；未知主题回退浅色（与 parity CLI 的默认值一致）。 */
func tokensFor(themeName: String): ThemeTokens {
    if (themeName == "dark") {
        ThemeTokens.dark()
    } else {
        ThemeTokens.light()
    }
}
