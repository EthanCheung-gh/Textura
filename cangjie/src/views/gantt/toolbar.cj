package textura.views.gantt

import cui.*
import textura.ui.*
import textura.views.gantt.logic.*

/*
 * 工具栏（GanttToolbar.tsx:42-101，gantt.css:15-56）。
 *
 * 这一层用 `textura.ui` 的控件：分段缩放、导航（上一段/今天/下一段）、区间标签、
 * 已排期计数、新建任务 / 适配窗口 / 详情按钮，尺寸与 Web 版逐值一致
 * （ControlSize.Sm：高 28、左右 10；IconButton.Sm：26×26；Segmented：托盘 30）。
 *
 * 盒模型：`.gantt-toolbar { padding: 8px 12px; border: 1px; radius: 14; gap: 8 }`
 * → 外框 48 高（8+30+8+2 描边）。CUI 的 `.border()` 只画不占位，所以纵向内边距取 9，
 * 让 30 高的控件带落在 48 盒内的 y=9..39（= 1 描边 + 8 内边距），与浏览器一致。
 */

func buildToolbar(
    theme: Theme,
    tokens: ThemeTokens,
    zoom: GanttZoom,
    rangeLabel: String,
    scheduled: Int64,
    total: Int64,
    inspectorOpen: Bool,
    zoomSelection: Bindable<Int64>,
    onPrev!: () -> Unit,
    onNext!: () -> Unit,
    onToday!: () -> Unit,
    onFit!: () -> Unit,
    onCreate!: () -> Unit,
    onToggleInspector!: () -> Unit
): Unit {
    HStack(spacing: vp(tokens.space.s2)) {
        // GanttToolbar.tsx:44-50 —— 日 / 周 / 月
        Ui.segmented(theme, ["日", "周", "月"], zoomSelection, size: ControlSize.Sm)

        // GanttToolbar.tsx:52-62 —— `.gantt-nav`：左右 1px 描边 + 2px 间隙 + 4px 内边距
        HStack(spacing: vp(0.0)) {
            navDivider(theme, tokens)
            HStack(spacing: vp(2.0)) {
                Ui.iconButton(theme, IconGlyph.ChevronLeft, onPrev, size: ControlSize.Sm, tooltip: "上一段")
                Ui.button(theme, "今天", onToday, variant: ButtonVariant.Ghost, size: ControlSize.Sm)
                Ui.iconButton(theme, IconGlyph.ChevronRight, onNext, size: ControlSize.Sm, tooltip: "下一段")
            }.hug().padding(vp(tokens.space.s1), vp(0.0))
            navDivider(theme, tokens)
        }.hug()

        // GanttToolbar.tsx:64-66 —— `.gantt-range-label { font-size: 12.5px; color: text-muted }`
        Label(rangeLabel).fontSize(fp(TOOLBAR_RANGE_SIZE)).foregroundColor(tokens.color.textMuted)
            .padding(vp(tokens.space.s1), vp(0.0), vp(0.0), vp(0.0))

        Spacer()

        // GanttToolbar.tsx:70-72 —— `.gantt-count { font-size: 11.5px; color: text-faint }`
        Label("${scheduled}/${total} 已排期").fontSize(fp(TOOLBAR_COUNT_SIZE)).foregroundColor(tokens.color.textFaint)

        Ui.button(theme, "新建任务", onCreate, variant: ButtonVariant.Primary, size: ControlSize.Sm,
            iconLeft: IconGlyph.Plus)
        Ui.button(theme, "适配窗口", onFit, size: ControlSize.Sm, iconLeft: IconGlyph.ZoomOut)
        Ui.button(theme, if (inspectorOpen) {
            "收起详情"
        } else {
            "详情"
        }, onToggleInspector,
            variant: if (inspectorOpen) {
                ButtonVariant.Secondary
            } else {
                ButtonVariant.Ghost
            }, size: ControlSize.Sm, iconLeft: IconGlyph.Edit)
    }
        .hug()
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .padding(vp(tokens.space.s3), vp(TOOLBAR_BORDER + tokens.space.s2), vp(tokens.space.s3),
            vp(TOOLBAR_BORDER + tokens.space.s2))
        .height(TOOLBAR_HEIGHT)
        .fillWidth()
        .background(tokens.color.surface, tokens.radius.lg)
        .border(tokens.color.border, width: tokens.metrics.borderWidth, radius: tokens.radius.lg)
}

/** `.gantt-nav` 的左右 1px 描边（CUI 没有单边 border，用竖直分隔线表达）。 */
private func navDivider(theme: Theme, tokens: ThemeTokens): Unit {
    let _ = theme
    Box(tokens.color.border).width(tokens.metrics.borderWidth).height(28.0)
}

/** 1×N 的纯色块（单边描边 / 细分隔线的替身）。 */
class Box <: Widget {
    private let color: Color
    private var frame = Rect.zero()

    init(color: Color) {
        this.color = color
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(1.0, available.w), min(28.0, available.h))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fill(frame, color)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}
