package textura.views.gtd

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.gtd.logic as gl

/*
 * GTD 视图入口（Web 版 src/modules/gtd/GtdPage.tsx 的仓颉移植）。
 *
 * 结构照搬 Web：
 *   页头（h1 + 副标题 + 流程台/周回顾分段 + 快速收集）
 *   → 流程概览条（收集 → 澄清，组织 → 执行，委派与跟进，暂时不做）
 *   → 两栏：左（收件箱、下一步）／右（等待中、某天/搁置、项目健康度）
 *   或 周回顾视图（收件箱清零度／本周完成／超期／停滞项目／等待超期／无日期／停滞领域）
 *
 * 事实只从 `ctx.store.state.value()` 读；行内动作先由 `logic` 算出意图，
 * 再经 `applyGtdChange` 落到 store（见 gtd_model.cj）。
 */

public func bootstrapTitle(): String {
    "GTD"
}

public func bootstrapNote(): String {
    "GTD 视图：收集 → 澄清 → 组织 → 回顾 → 执行。"
}

/** 一次渲染用到的全部事实与派生数据（每帧重建，读取同一 store 快照）。 */
class GtdScene {
    let ctx: ViewContext
    let tokens: ThemeTokens
    let theme: Theme
    let today: String
    let workspace: Workspace
    let gws: gl.GtdWorkspace
    let state: GtdState
    let inbox: Array<gl.GtdItem>
    let next: Array<gl.GtdItem>
    let waiting: Array<gl.GtdItem>
    let someday: Array<gl.GtdItem>
    let projectCount: Int64

    init(ctx: ViewContext, tokens: ThemeTokens, theme: Theme, today: String, workspace: Workspace,
        gws: gl.GtdWorkspace, state: GtdState) {
        this.ctx = ctx
        this.tokens = tokens
        this.theme = theme
        this.today = today
        this.workspace = workspace
        this.gws = gws
        this.state = state
        this.inbox = gl.sortInboxItems(mapItems(inboxItems(workspace)))
        this.next = mapItems(nextActions(workspace))
        this.waiting = mapItems(waitingItems(workspace))
        this.someday = mapItems(somedayItems(workspace))
        this.projectCount = itemsOfKind(workspace, ItemKind.Project).size
    }

    /** 当前领域色；领域色是数据（`Area.color`），不是设计令牌。 */
    func areaColor(areaId: ?String): ?Color {
        match (areaId) {
            case Some(value) => match (areaById(workspace, value)) {
                case Some(area) => Some(parseAreaColor(area.color))
                case None => None
            }
            case None => None
        }
    }

    func areaName(areaId: ?String): String {
        match (areaId) {
            case Some(value) => match (areaById(workspace, value)) {
                case Some(area) => area.name
                case None => ""
            }
            case None => ""
        }
    }

    /** 把 `logic` 产出的意图序列落库（顺序即意图顺序）。 */
    func run(change: gl.GtdChange): Unit {
        let created = applyGtdChange(ctx.store, change)
        match (change.resultId) {
            case Some(id) =>
                if (!created.isEmpty()) {
                    ctx.store.select(id)
                } else {
                    ctx.store.select(id)
                }
            case None => ()
        }
    }

    /** 新建条目 id 的占位（store 会分配真实 id，见 gtd_model.cj 的 id 改写）。 */
    func placeholder(prefix: String): String {
        placeholderId(workspace, prefix)
    }

    /** 当前时刻（来自注入时钟，不读系统时钟）。 */
    func now(): String {
        nowIso(ctx.store.clock)
    }

    func item(id: String): ?Item {
        itemById(workspace, id)
    }

    /** 分区聚焦（GtdPage.tsx `focusSection`）：切回流程台并高亮该分区。 */
    func focusSection(key: String): Unit {
        state.viewMode.value = 0
        state.highlight.value = key
    }

    /** 打开澄清弹窗并把表单重置为该条目的当前值（ClarifyDialog `createClarifyForm`）。 */
    func openClarify(id: String): Unit {
        openClarifyState(this, id)
    }
}

func mapItems(items: Array<Item>): Array<gl.GtdItem> {
    let mapped = ArrayList<gl.GtdItem>()
    for (item in items) {
        mapped.add(toGtdItem(item))
    }
    mapped.toArray()
}

/** `.page { max-width: 1280px }`（shell.css:262）：内容区宽 = 窗口 - 侧栏 - 两侧 24 内边距。 */
func pageWidth(ctx: ViewContext, tokens: ThemeTokens): Float32 {
    let available = Float32(ctx.width) - tokens.metrics.sidebarWidth - CONTENT_PAD * 2.0
    min(max(available, 0.0), PAGE_MAX_WIDTH)
}

public func render(ctx: ViewContext): Unit {
    let tokens = if (ctx.theme == "dark") {
        ThemeTokens.dark()
    } else {
        ThemeTokens.light()
    }
    let theme = tokens.theme()
    let state = gtdState()
    let workspace = ctx.store.state.value()
    let scene = GtdScene(ctx, tokens, theme, ctx.today, workspace, toGtdWorkspace(workspace), state)
    ZStack {
        EventHandler(onEvent: {event => gtdKeyHandler(scene, event)}) {
        VStack(spacing: vp(PAGE_GAP)) {
            gtdPageHeader(scene)
            if (state.viewMode.value == 1) {
                gtdWeeklyReview(scene)
            } else {
                gtdFlowBar(scene)
                gtdFlowLayout(scene)
            }
        }.hug().width(pageWidth(ctx, tokens))
        }
        gtdOverlays(scene)
    }
}

/* ---------------------------------------------------------------- 页头 */

/** `.page-header`（shell.css:270-290）：标题列 + 右侧分段与快速收集。 */
func gtdPageHeader(scene: GtdScene): Unit {
    let tokens = scene.tokens
    HStack(spacing: vp(HEADER_ACTIONS_GAP)) {
        GtdPageTitles(tokens, "GTD · 织理", "收集、澄清、组织、回顾、执行 —— 让每件事都有归处。")
        Spacer()
        Ui.segmentedWithGlyphs(
            scene.theme,
            [
                SegmentedItem("流程台", glyph: IconGlyph.Workflow),
                SegmentedItem("周回顾", glyph: IconGlyph.Calendar)
            ],
            scene.state.viewMode,
            size: ControlSize.Sm
        )
        Ui.button(
            scene.theme,
            "快速收集",
            {=> quickCapture(scene)},
            variant: ButtonVariant.Primary,
            size: ControlSize.Md,
            iconLeft: IconGlyph.Plus
        )
    }
        .crossAxisAlignment(CrossAxisAlignment.Start)
        .hug()
        .fillWidth()
}

/** GtdPage.tsx `setUi({ quickCaptureOpen: true })`：快速收集弹窗归 shell 所有。 */
func quickCapture(scene: GtdScene): Unit {
    scene.ctx.store.setUi({ui => ui.quickCaptureOpen = true})
    scene.ctx.store.notify("已打开快速收集（⌘/Ctrl+N）", tone: NoticeTone.Info)
}

/* ---------------------------------------------------------------- 流程概览条 */

/**
 * `.gtd-flowbar`（gtd.css:18-22）：四等分卡片，间距 12。
 *
 * 卡片宽度按 `.page` 的设计宽度算成定值而不是 `.flex()`：shell 的 `.shell-content` 是
 * CUI `ScrollView`，内容溢出时会预留 10px 滚动条槽，可用宽度比浏览器窄 10px；用定值
 * 可以让前三张卡与左栏、右栏起点分别与参考图对齐，只有最右一列少 10px。
 */
func gtdFlowBar(scene: GtdScene): Unit {
    let tokens = scene.tokens
    let cardWidth = (pageWidth(scene.ctx, tokens) - FLOW_GAP * 3.0) / 4.0
    HStack(spacing: vp(FLOW_GAP)) {
        flowCard(scene, "inbox", IconGlyph.Inbox, "收件箱待澄清", scene.inbox.size, "收集 → 澄清",
            tokens.color.accent, tokens.color.accent, cardWidth)
        flowCard(scene, "next", IconGlyph.Play, "下一步", scene.next.size, "组织 → 执行", tokens.color.ok,
            tokens.color.ok, cardWidth)
        flowCard(scene, "waiting", IconGlyph.Clock, "等待中", scene.waiting.size, "委派与跟进", tokens.color.info,
            tokens.color.info, cardWidth)
        flowCard(scene, "someday", IconGlyph.Flag, "某天 / 搁置", scene.someday.size, "暂时不做",
            tokens.color.textMuted, tokens.color.borderStrong, cardWidth)
    }.hug()
}

func flowCard(scene: GtdScene, key: String, glyph: IconGlyph, label: String, value: Int64, hint: String,
    glyphColor: Color, leadColor: Color, cardWidth: Float32): Unit {
    GtdFlowCard(scene.tokens, glyph, glyphColor, label, value, hint, leadColor, "gtd-flow:${key}",
        {=> scene.focusSection(key)})
        .width(cardWidth)
}

/* ---------------------------------------------------------------- 两栏布局 */

/** `.gtd-layout`（gtd.css:96-101）：左 1.65fr / 右 1fr，间距 16，交叉轴起点对齐。 */
func gtdFlowLayout(scene: GtdScene): Unit {
    // `grid-template-columns: minmax(0, 1.65fr) minmax(0, 1fr); gap: 16`（gtd.css:96-101）
    // 用定值：左栏与右栏起点与参考图一致，右栏右边缘受滚动条槽影响少 10px。
    let total = pageWidth(scene.ctx, scene.tokens)
    let leftWidth = (total - LAYOUT_GAP) * LAYOUT_LEFT_FR / (LAYOUT_LEFT_FR + LAYOUT_RIGHT_FR)
    let rightWidth = total - LAYOUT_GAP - leftWidth
    HStack(spacing: vp(LAYOUT_GAP)) {
        VStack(spacing: vp(COLUMN_GAP)) {
            gtdInboxSection(scene)
            gtdNextSection(scene)
        }.hug().width(leftWidth)
        VStack(spacing: vp(COLUMN_GAP)) {
            gtdWaitingSection(scene)
            gtdSomedaySection(scene)
            gtdProjectsSection(scene)
        }.hug().width(rightWidth)
    }
        .crossAxisAlignment(CrossAxisAlignment.Start)
        .hug()
}
