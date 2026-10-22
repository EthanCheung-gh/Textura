package textura.views.gtd

import std.collection.*
import std.unicode.*
import cui.*

/*
 * GTD 视图的几何常量与文本绘制原语。
 *
 * 所有数值逐值来自 Web 版 CSS（只读参考），出处写在每条注释里：
 *   gtd.css   src/modules/gtd/gtd.css
 *   shell.css src/styles/shell.css
 *   ui.css    src/ui/ui.css
 *   base.css  src/styles/base.css
 * 单位是 CSS px：布局走 `vp`/逻辑像素，字号走 `fp`（见 CUI-PRIMER §10）。
 */

// ---------------------------------------------------------------- 页面骨架
// shell.css:262 `.page { max-width: 1280px; margin: 0 auto }`
let PAGE_MAX_WIDTH: Float32 = 1280.0
// shell.css:245 `.shell-content { padding: var(--space-5) }` = 24
let CONTENT_PAD: Float32 = 24.0
// gtd.css:4 `.page.gtd-page { gap: var(--space-4) }` = 16
let PAGE_GAP: Float32 = 16.0
// gtd.css:99 `.gtd-layout { gap: var(--space-4) }` / gtd.css:98 `1.65fr minmax(0,1fr)`
let LAYOUT_GAP: Float32 = 16.0
let LAYOUT_LEFT_FR: Float32 = 1.65
let LAYOUT_RIGHT_FR: Float32 = 1.0
// gtd.css:106 `.gtd-column { gap: var(--space-4) }`
let COLUMN_GAP: Float32 = 16.0

// ---------------------------------------------------------------- 页头
// shell.css:284 `.page-header h1 { font-size: 22px }`；base.css:14 line-height 1.5
let H1_SIZE: Float32 = 22.0
let H1_WEIGHT: Int64 = 650
let LINE_HEIGHT: Float32 = 1.5
// shell.css:288 `.page-header p { font-size: 13px; color: text-muted }`
let SUB_SIZE: Float32 = 13.0
// shell.css:278 `.page-header-titles { gap: var(--space-1) }` = 4
let HEADER_TITLE_GAP: Float32 = 4.0
// shell.css:293 `.page-actions { gap: var(--space-2) }` = 8
let HEADER_ACTIONS_GAP: Float32 = 8.0

// ---------------------------------------------------------------- 流程条
// gtd.css:21 `.gtd-flowbar { gap: var(--space-3) }` = 12
let FLOW_GAP: Float32 = 12.0
// gtd.css:29 `.gtd-flow-card { padding: var(--space-3) var(--space-4) }` = 12 16
let FLOW_PAD_V: Float32 = 12.0
let FLOW_PAD_H: Float32 = 16.0
// gtd.css:32 `border-left: 3px solid`
let FLOW_LEAD: Float32 = 3.0
// gtd.css:61-67 `.gtd-flow-card-top { gap: 6px; font-size: 11.5px; font-weight: 600 }`
let FLOW_TOP_SIZE: Float32 = 11.5
let FLOW_TOP_WEIGHT: Int64 = 600
let FLOW_TOP_GAP: Float32 = 6.0
// GtdPage.tsx `<Icon name={card.icon} size={14} />`
let FLOW_TOP_ICON: Float32 = 14.0
// gtd.css:82-87 `.gtd-flow-card-value { font-size: 24px; font-weight: 680; line-height: 1.15 }`
let FLOW_VALUE_SIZE: Float32 = 24.0
let FLOW_VALUE_LH: Float32 = 1.15
let FLOW_VALUE_WEIGHT: Int64 = 680
// gtd.css:90-93 `.gtd-flow-card-hint { font-size: 11px; color: text-faint }`
let FLOW_HINT_SIZE: Float32 = 11.0
// gtd.css:27 `gap: 1px`；gtd.css:33 `border-radius: var(--radius-md)` = 8
let FLOW_INNER_GAP: Float32 = 1.0
let FLOW_RADIUS: Float32 = 8.0

// ---------------------------------------------------------------- 分区外壳
// gtd.css:114 `border-radius: var(--radius-lg)` = 14
let SECTION_RADIUS: Float32 = 14.0
// gtd.css:131 `.gtd-section-header { padding: 10px var(--space-4) }` = 10 16
let SECTION_HEADER_PAD_V: Float32 = 10.0
let SECTION_HEADER_PAD_H: Float32 = 16.0
// gtd.css:139 `.gtd-section-heading { gap: var(--space-2) }` = 8
let SECTION_HEADING_GAP: Float32 = 8.0
// GtdSection.tsx `<Icon name={icon} size={15} />`
let SECTION_ICON: Float32 = 15.0
// gtd.css:152-155 `.gtd-section-title { font-size: 13.5px; font-weight: 650 }`
let SECTION_TITLE_SIZE: Float32 = 13.5
let SECTION_TITLE_WEIGHT: Int64 = 650
// gtd.css:158-171 `.gtd-count { min-width: 20px; height: 18px; padding: 0 6px; font-size: 11px }`
let COUNT_H: Float32 = 18.0
let COUNT_MIN_W: Float32 = 20.0
let COUNT_PAD_H: Float32 = 6.0
let COUNT_SIZE: Float32 = 11.0
// gtd.css:173-186 `.gtd-section-hint { margin-left: var(--space-2); gap: 4px 8px }`
let HINT_MARGIN: Float32 = 8.0
let HINT_GAP: Float32 = 8.0
// gtd.css:182-186 `.gtd-section-note { font-size: 10.5px; color: text-faint }`
let NOTE_SIZE: Float32 = 10.5
// gtd.css:204-224 `.gtd-kbd-hint { gap: 3px; font-size: 10.5px }` /
// `kbd { padding: 0 4px; border: 1px solid; border-bottom-width: 2px; font-size: 10px; line-height: 1.5 }`
let KBD_HINT_SIZE: Float32 = 10.5
let KBD_SIZE: Float32 = 10.0
let KBD_LINE: Float32 = 1.5
let KBD_PAD_H: Float32 = 4.0
let KBD_GAP: Float32 = 3.0
let KBD_RADIUS: Float32 = 4.0
// gtd.css:195-201 `.gtd-section-body { padding: var(--space-3) var(--space-4) }` /
// `.gtd-empty-body { padding: var(--space-3) }`
let SECTION_BODY_PAD_V: Float32 = 12.0
let SECTION_BODY_PAD_H: Float32 = 16.0
let EMPTY_BODY_PAD: Float32 = 12.0

// ---------------------------------------------------------------- 列表行
// gtd.css:243 `padding: 10px var(--space-4)`；gtd.css:241 `gap: var(--space-3)` = 12
let ROW_PAD_V: Float32 = 10.0
let ROW_PAD_H: Float32 = 16.0
let ROW_GAP: Float32 = 12.0
// gtd.css:245 `border-left: 2px solid transparent`
let ROW_EDGE: Float32 = 2.0
// gtd.css:268-269 `.gtd-row-title { font-size: 13.5px; font-weight: 560; line-height: 1.35 }`
let ROW_TITLE_SIZE: Float32 = 13.5
let ROW_TITLE_LH: Float32 = 1.35
let ROW_TITLE_WEIGHT: Int64 = 560
// gtd.css:289-294 `.gtd-row-meta { gap: 6px; margin-top: 4px; font-size: 11.5px }`
let META_GAP: Float32 = 6.0
let META_MARGIN_TOP: Float32 = 4.0
let META_SIZE: Float32 = 11.5
// gtd.css:301 `.gtd-row-time { gap: 4px; font-size: inherit(11.5) }`
let META_ICON: Float32 = 12.0
let CHIP_GAP: Float32 = 4.0
// gtd.css:328-331 `.gtd-check { width: 20px; height: 20px; border: 1.5px }`
let CHECK_SIZE: Float32 = 20.0
// ui.css:243-251 `.badge { gap: 5px; padding: 2px 7px; font-size: 11px; font-weight: 550;
// line-height: 1.6; border: 1px solid }` → 边框盒高 11*1.6 + 4 + 2 = 23.6
let BADGE_SIZE: Float32 = 11.0
let BADGE_LINE: Float32 = 1.6
let BADGE_PAD_V: Float32 = 2.0
let BADGE_PAD_H: Float32 = 7.0
let BADGE_HEIGHT: Float32 = 23.6
// gtd.css:370-380 `.gtd-breadcrumb { gap: 4px; max-width: 260px; font-size: 11px }`
let BREADCRUMB_SIZE: Float32 = 11.0
let BREADCRUMB_MAX: Float32 = 260.0
// gtd.css:410-415 `.gtd-area-dot { width: 7px; height: 7px }`
let AREA_DOT: Float32 = 7.0
// gtd.css:426-442 `.gtd-inline-select { width: 98px }` / `.gtd-inline-date { width: 124px }`，
// 两者 `height: 30px; padding: 4px 6px; font-size: 11.5px`
let INLINE_H: Float32 = 30.0
let INLINE_SELECT_W: Float32 = 98.0
let INLINE_DATE_W: Float32 = 124.0
let INLINE_PAD_H: Float32 = 6.0
let INLINE_FONT: Float32 = 11.5
let INLINE_GAP: Float32 = 4.0

// ---------------------------------------------------------------- 筛选栏
// gtd.css:445-452 `.gtd-filterbar { padding: 9px var(--space-4); gap: var(--space-2) }` = 9 16 / 8
let FILTER_PAD_V: Float32 = 9.0
let FILTER_PAD_H: Float32 = 16.0
let FILTER_GAP: Float32 = 8.0
// gtd.css:455-463 `.gtd-filter-select { min-width: 108px; max-width: 150px; height: 30px;
// padding: 4px 26px 4px 8px; font-size: 12px }`
let FILTER_SELECT_MIN: Float32 = 108.0
let FILTER_SELECT_MAX: Float32 = 150.0
let FILTER_SELECT_PAD_L: Float32 = 8.0
let FILTER_SELECT_PAD_R: Float32 = 26.0
let FILTER_SELECT_FONT: Float32 = 12.0
// gtd.css:466-487 `.gtd-toggle { gap: 6px; padding: 5px 7px; font-size: 12px }` /
// `.gtd-toggle input { width: 15px; height: 15px }`
let TOGGLE_PAD_V: Float32 = 5.0
let TOGGLE_PAD_H: Float32 = 7.0
let TOGGLE_GAP: Float32 = 6.0
let TOGGLE_SIZE: Float32 = 12.0
let TOGGLE_BOX: Float32 = 15.0
// gtd.css:489-494 `.gtd-filter-count { font-size: 11px; color: text-faint }`
let FILTER_COUNT_SIZE: Float32 = 11.0

// ---------------------------------------------------------------- 场景分组
// gtd.css:505-516 `.gtd-group-header { gap: 6px; padding: 6px var(--space-4); font-size: 11.5px;
// font-weight: 600; letter-spacing: .05em; background: surface-2 }`
let GROUP_PAD_V: Float32 = 6.0
let GROUP_PAD_H: Float32 = 16.0
let GROUP_GAP: Float32 = 6.0
let GROUP_SIZE: Float32 = 11.5
let GROUP_WEIGHT: Int64 = 600
// GtdSection 中 `<Icon name="chevron-right" size={13} />`
let GROUP_CHEVRON: Float32 = 13.0

// ---------------------------------------------------------------- 侧栏列表
// gtd.css:557-563 `.gtd-side-row { gap: var(--space-2); padding: 9px var(--space-4) }` = 8 / 9 16
let SIDE_PAD_V: Float32 = 9.0
let SIDE_PAD_H: Float32 = 16.0
let SIDE_GAP: Float32 = 8.0

// ---------------------------------------------------------------- 项目健康度
// gtd.css:581-587 `.gtd-project { gap: 6px; padding: var(--space-3) var(--space-4) }` = 6 / 12 16
let PROJECT_PAD_V: Float32 = 12.0
let PROJECT_PAD_H: Float32 = 16.0
let PROJECT_GAP: Float32 = 6.0
// gtd.css:601-606 `.gtd-project-name { font-size: 13px; font-weight: 620 }`
let PROJECT_NAME_SIZE: Float32 = 13.0
let PROJECT_NAME_WEIGHT: Int64 = 620
// gtd.css:608-624 `.gtd-project-stats { gap: var(--space-2); font-size: 11px; color: text-faint }`
let PROJECT_STATS_SIZE: Float32 = 11.0
let PROJECT_STATS_GAP: Float32 = 8.0
// gtd.css:626-631 `.gtd-project-actions { gap: var(--space-1); margin-top: 2px }` = 4 / 2
let PROJECT_ACTIONS_GAP: Float32 = 4.0
let PROJECT_ACTIONS_MT: Float32 = 2.0

// ---------------------------------------------------------------- 周回顾
// gtd.css:641-651 `.gtd-review-overview { gap: var(--space-5); padding: var(--space-4) var(--space-5) }
//   = 24 / 16 24`
let REVIEW_OVERVIEW_GAP: Float32 = 24.0
let REVIEW_OVERVIEW_PAD_V: Float32 = 16.0
let REVIEW_OVERVIEW_PAD_H: Float32 = 24.0
// gtd.css:658-666 `.gtd-review-eyebrow { gap: 6px; font-size: 11px; font-weight: 600 }`
let REVIEW_EYEBROW_SIZE: Float32 = 11.0
let REVIEW_EYEBROW_WEIGHT: Int64 = 600
// gtd.css:668-671 `.gtd-review-overview h2 { margin-top: 2px; font-size: 20px }`
let REVIEW_H2_SIZE: Float32 = 20.0
let REVIEW_H2_WEIGHT: Int64 = 620
// gtd.css:673-677 `.gtd-review-overview p { margin-top: 2px; font-size: 12px }`
let REVIEW_P_SIZE: Float32 = 12.0
let REVIEW_TEXT_MT: Float32 = 2.0
// gtd.css:679-682 `.gtd-review-overview-progress { width: 240px }`
let REVIEW_PROGRESS_W: Float32 = 240.0
// gtd.css:690-697 `.gtd-review-grid { gap: var(--space-4) }` = 16（两列）
let REVIEW_GRID_GAP: Float32 = 16.0
// gtd.css:699-709 `.gtd-review-card { gap: 10px; padding: var(--space-4) }` = 10 / 16
let REVIEW_CARD_GAP: Float32 = 10.0
let REVIEW_CARD_PAD: Float32 = 16.0
// gtd.css:726-735 `.gtd-review-card-titles h3 { font-size: 14px; font-weight: 650 }` /
// `p { margin-top: 2px; font-size: 11.5px }`
let REVIEW_CARD_TITLE_SIZE: Float32 = 14.0
let REVIEW_CARD_TITLE_WEIGHT: Int64 = 650
let REVIEW_CARD_KICKER_SIZE: Float32 = 11.5
// gtd.css:743-753 `.gtd-review-metric strong { font-size: 28px; font-weight: 680; line-height: 1 }` /
// `span { font-size: 11.5px }`
let REVIEW_METRIC_SIZE: Float32 = 28.0
let REVIEW_METRIC_WEIGHT: Int64 = 680
let REVIEW_METRIC_UNIT_SIZE: Float32 = 11.5
let REVIEW_METRIC_GAP: Float32 = 6.0
// gtd.css:794-830 `.gtd-review-item { gap: 6px; padding: 3px 0; font-size: 12px }` /
// `.gtd-review-item-meta { font-size: 11px }`
let REVIEW_ITEM_PAD_V: Float32 = 3.0
let REVIEW_ITEM_GAP: Float32 = 6.0
let REVIEW_ITEM_SIZE: Float32 = 12.0
let REVIEW_ITEM_META_SIZE: Float32 = 11.0
// gtd.css:808-814 `.gtd-review-dot { width: 5px; height: 5px }`
let REVIEW_DOT: Float32 = 5.0
// gtd.css:837-844 `.gtd-linkbtn { gap: 2px; font-size: 11.5px; color: accent }`
let LINKBTN_SIZE: Float32 = 11.5
let LINKBTN_GAP: Float32 = 2.0
// gtd.css:851-864 `.gtd-show-more { gap: var(--space-2); padding: var(--space-2) var(--space-3) }` = 8 12
let SHOW_MORE_PAD_V: Float32 = 8.0
let SHOW_MORE_PAD_H: Float32 = 12.0
let SHOW_MORE_GAP: Float32 = 8.0
let SHOW_MORE_NOTE_SIZE: Float32 = 11.0

// ---------------------------------------------------------------- 澄清弹窗
// ui.css:489 `.modal { width: 520 }`；ClarifyDialog.tsx `width={660}`
let CLARIFY_WIDTH: Float32 = 660.0
// gtd.css:867-879 `.gtd-form { gap: var(--space-2) }` / `.textarea { min-height: 58px }`
let FORM_GAP: Float32 = 8.0
let FORM_TEXTAREA_H: Float32 = 58.0
// gtd.css:881-889 `.gtd-form-grid { gap: var(--space-2) var(--space-4) }` = 8 16
let FORM_GRID_GAP_V: Float32 = 8.0
let FORM_GRID_GAP_H: Float32 = 16.0
// gtd.css:891-900 `.gtd-form-checks { gap: 8 16; padding: var(--space-2) var(--space-3) }` = 8 12
let FORM_CHECKS_PAD_V: Float32 = 8.0
let FORM_CHECKS_PAD_H: Float32 = 12.0
// gtd.css:902-909 `.gtd-checkline { gap: 6px; font-size: 12.5px }`
let CHECKLINE_SIZE: Float32 = 12.5
let CHECKLINE_GAP: Float32 = 6.0
// gtd.css:916-926 `.gtd-clarify-callout { gap: 6px; margin-top: var(--space-2);
// padding: var(--space-2) var(--space-3); font-size: 12px }`
let CALLOUT_GAP: Float32 = 6.0
let CALLOUT_PAD_V: Float32 = 8.0
let CALLOUT_PAD_H: Float32 = 12.0
let CALLOUT_SIZE: Float32 = 12.0

// ---------------------------------------------------------------- 文本原语
/** 行盒高度：CSS `line-height` 的 px 值。 */
public func lineBox(size: Float32, ratio!: Float32 = LINE_HEIGHT): Float32 {
    size * ratio
}

/** 无法解析的领域色回退到中性灰（只出现在脏数据上）。 */
private let FALLBACK_AREA_COLOR: Color = Color.rgb(160, 150, 140)

/**
 * 解析 `#rrggbb` / `#rrggbbaa`。领域色（`core.data.Area.color`）是**数据**，不是设计令牌，
 * 因此这里只做数据解码，不引入任何硬编码颜色。
 */
func parseAreaColor(value: String): Color {
    var text = value.trim()
    if (text.startsWith("#")) {
        text = text[1..]
    }
    let runes = text.toRuneArray()
    if (runes.size < 6) {
        return FALLBACK_AREA_COLOR
    }
    var channels = ArrayList<Int64>()
    var index = 0
    while (index + 1 < runes.size && channels.size < 3) {
        let high = hexDigit(runes[index])
        let low = hexDigit(runes[index + 1])
        if (high < 0 || low < 0) {
            return FALLBACK_AREA_COLOR
        }
        channels.add(high * 16 + low)
        index += 2
    }
    if (channels.size < 3) {
        return FALLBACK_AREA_COLOR
    }
    Color.rgb(channels[0], channels[1], channels[2])
}

private func hexDigit(value: Rune): Int64 {
    let code = Int64(UInt32(value))
    if (code >= 48 && code <= 57) {
        return code - 48
    }
    if (code >= 97 && code <= 102) {
        return code - 87
    }
    if (code >= 65 && code <= 70) {
        return code - 55
    }
    -1
}
