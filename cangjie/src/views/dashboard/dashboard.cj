package textura.views.dashboard

import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.dashboard.logic as dash

/*
 * 今日视图 —— Web 版 `src/modules/dashboard/DashboardPage.tsx` 的 1:1 移植。
 *
 * 写入范围：本包只做渲染与交互接线；领域事实全部来自 `ctx.store`，
 * 聚合算法全部来自 `textura.views.dashboard.logic`（见 docs/DASHBOARD-LOGIC.md）。
 *
 * 布局骨架（每条都对应 Web 的 CSS）：
 *   `.page`(gap 24, max-width 1280, shell.css:262-268)
 *     `.page-header.dash-header`(dashboard.css:6-39)
 *     `.dash-stats`(4 列 / gap 12, dashboard.css:42-46)
 *     `.dash-grid`(1.55fr / 1fr / gap 16 / align-items: start, dashboard.css:128-133)
 * 两条级联事实由参考图钉住：`dashboard.css` 先于 `shell.css` 加载，因此
 * `.page { gap: 24px }` 与 `.page-header h1 { font-size: 22px }` 生效。
 */

/*
 * `.dash-grid { grid-template-columns: minmax(0, 1.55fr) minmax(0, 1fr) }` 的换算。
 *
 * CUI 的 flex 分发会为每条权重轨道吸收 `gap × (权重 − 1)`，因此 `1.55 : 1` 的权重
 * 并不能得到 1.55 : 1 的轨道。按 1152px 页宽、16px 间距解出的等价权重是
 * 691px : 445px（参考图实测左卡 264..954、右卡 971..1415），即下面两个常数。
 * 见 docs/PARITY 报告：右列左边缘 971px 与参考图一致。
 */
let LEFT_TRACK_WEIGHT: Float32 = 1.5435
let RIGHT_TRACK_WEIGHT: Float32 = 1.0065

/** `暂存` 的今日视图标题（shell 侧栏文案）。 */
public func bootstrapTitle(): String {
    "今日"
}

/** shell 派发切换前的占位说明。 */
public func bootstrapNote(): String {
    "今日视图：四张状态卡 + 今日聚焦 + OKR 概览 + SOP 快速启动 + 最近活动。"
}

public func render(ctx: ViewContext): Unit {
    let theme = if (ctx.theme == "dark") {
        texturaDark()
    } else {
        texturaLight()
    }
    let tokens = tokensOf(theme)
    let data = loadDashboardData(ctx)
    let store = ctx.store
    let navigate = ctx.navigate
    let limit = rememberState<Int64>("dashboard-focus-limit") {dash.FOCUS_PAGE_SIZE}
    // `.dash-focus-list { max-height: 380px; overflow-y: auto }`（dashboard.css:200-206）的内滚位置
    let focusScroll = rememberState<Float32>("dashboard-focus-scroll") {0.0}

    // 行内勾完成：写回 store（`toggleDone` 维护 `completedAt`）。
    let onToggle = {id: String => store.toggleDone(id)}
    // 点击条目：选中 + 跳到该 kind 对应视图（navigation.ts `routeForItemKind`）。
    let onOpenItem = {item: dash.DashItem =>
        store.select(item.id)
        match (itemById(ctx.store.state.value(), item.id)) {
            case Some(source) => match (source.okr) {
                case Some(okr) => store.setOkrPeriod(okr.period)
                case None => ()
            }
            case None => ()
        }
        navigate(routeForKind(item.kind))
    }
    let onOpenOkrRow = {id: String =>
        store.select(id)
        navigate("okr")
    }
    let onOpenSopRow = {id: String =>
        store.select(id)
        navigate("sop")
    }
    let onShowMore = {=> limit.value = limit.value + dash.FOCUS_PAGE_SIZE}

    VStack(spacing: vp(24.0)) {
        // `.page-header`（shell.css:270-296）
        PageHeaderView(tokens, data.eyebrow, data.title, data.summary,
            {=> store.setUi({state => state.paletteOpen = true})}).fillWidth()
        if (data.workspaceEmpty) {
            onboardingCard(theme, tokens, store, navigate, data.okrPeriod)
        } else {
            statsRow(tokens, data, store, navigate)
            mainGrid(theme, tokens, data, limit.value, focusScroll, onToggle, onOpenItem, onOpenOkrRow, onOpenSopRow,
                onShowMore, store, navigate)
        }
    }.hug().fillWidth()
}

/** `.dash-stats`（dashboard.css:42-46）：四列等宽，`gap: var(--space-3)`。 */
func statsRow(tokens: ThemeTokens, data: DashboardData, store: AppStore, navigate: (String) -> Unit): Unit {
    HStack(spacing: vp(tokens.space.s3)) {
        StatCardView(tokens, "收件箱待澄清", "${data.inboxCount}", "条",
            if (data.inboxCount > 0) {
                "先澄清，再决定下一步"
            } else {
                "收件箱已清空"
            }, IconGlyph.Inbox,
            if (data.inboxCount > 0) {
                StatTone.Accent
            } else {
                StatTone.Ok
            }, {=> navigate("gtd")}).fillWidth()
        StatCardView(tokens, "近 7 天完成", "${data.completedCount}", "项", "按 completedAt 的近 7 天滚动窗口",
            IconGlyph.Check, StatTone.Ok, {=> navigate("gtd")}).fillWidth()
        StatCardView(tokens, "活跃 OKR 平均进度", "${data.okrAverage}", "%",
            "${data.objectives.size} 个目标 · ${data.okrPeriod}", IconGlyph.Target, StatTone.Info,
            {=> navigate("okr")}).fillWidth()
        StatCardView(tokens, "最近 SOP 运行", data.newestRunLabel, "", data.newestRunMeta, IconGlyph.Play,
            data.newestRunTone, {=>
                match (data.newestRunSopId) {
                    case Some(id) => store.select(id)
                    case None => ()
                }
                navigate("sop")
            }).fillWidth()
    }.hug().fillWidth()
}

/** `.dash-grid`（dashboard.css:128-133）：1.55fr / 1fr，`gap: var(--space-4)`，交叉轴 `start`。 */
func mainGrid(theme: Theme, tokens: ThemeTokens, data: DashboardData, limit: Int64, focusScroll: State<Float32>,
    onToggle: (String) -> Unit, onOpenItem: (dash.DashItem) -> Unit, onOpenOkrRow: (String) -> Unit,
    onOpenSopRow: (String) -> Unit, onShowMore: () -> Unit, store: AppStore, navigate: (String) -> Unit): Unit {
    HStack(spacing: vp(tokens.space.s4)) {
        // 左列：今日聚焦 + 最近活动（`.dash-column { gap: var(--space-4) }`，dashboard.css:135-140）
        VStack(spacing: vp(tokens.space.s4)) {
            focusCard(theme, tokens, data, limit, focusScroll, onToggle, onOpenItem, onShowMore)
            activityCard(theme, tokens, data)
        }.flex(LEFT_TRACK_WEIGHT)
        // 右列：OKR 概览 + SOP 快速启动
        VStack(spacing: vp(tokens.space.s4)) {
            okrCard(theme, tokens, data, onOpenOkrRow, store, navigate)
            sopCard(theme, tokens, data, onOpenSopRow, navigate)
        }.flex(RIGHT_TRACK_WEIGHT)
    }.crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}


/** `.dash-card` + `.dash-card-head` + `.dash-focus-list`（dashboard.css:142-320）。 */
func focusCard(theme: Theme, tokens: ThemeTokens, data: DashboardData, limit: Int64, focusScroll: State<Float32>,
    onToggle: (String) -> Unit, onOpenItem: (dash.DashItem) -> Unit, onShowMore: () -> Unit): Unit {
    let sub = "${data.focusCounts.overdue} 超期 · ${data.focusCounts.today} 今天 · ${data.focusCounts.undated} 无日期"
    let page = dash.paginateFocus(data.focus, limit)
    if (data.focus.isEmpty()) {
        cardShell(VStack(spacing: vp(0.0)) {
            CardHeadView(tokens, IconGlyph.Flag, "今日聚焦", sub, trailingText: "0 项")
            Ui.emptyState(theme, "今天没有截止或下一步",
                description: "清空了。可以收集一点新想法，或者去 SOP / OKR 视图补充长期工作。",
                glyph: IconGlyph.Check, compact: true)
        }.hug().fillWidth(), tokens).fillWidth()
    } else {
        cardShell(VStack(spacing: vp(0.0)) {
            CardHeadView(tokens, IconGlyph.Flag, "今日聚焦", sub, trailingText: "${data.focus.size} 项")
            FocusRowsView(tokens, page.items, page.shown, page.total, page.remaining, onToggle, onOpenItem, onShowMore,
                focusScroll).fillWidth()
        }.hug().fillWidth(), tokens).fillWidth()
    }
}

/** `.dash-okr-list`（dashboard.css:322-363）。 */
func okrCard(theme: Theme, tokens: ThemeTokens, data: DashboardData, onOpen: (String) -> Unit, store: AppStore,
    navigate: (String) -> Unit): Unit {
    let sub = "${data.okrPeriod} · 平均 ${data.okrAverage}%"
    if (data.objectives.isEmpty()) {
        cardShell(VStack(spacing: vp(0.0)) {
            CardHeadView(tokens, IconGlyph.Target, "OKR 概览", sub, trailingText: "打开 OKR", asLink: true,
                onLink: {=> navigate("okr")})
            Ui.emptyState(theme, "本季度还没有目标", description: "在 OKR 视图里创建目标与关键结果。",
                glyph: IconGlyph.Target, compact: true,
                action: {=>
                    Ui.button(theme, "新建目标", {=> createObjective(store, navigate, data.okrPeriod)},
                        variant: ButtonVariant.Secondary, size: ControlSize.Sm)
                })
        }.hug().fillWidth(), tokens).fillWidth()
    } else {
        cardShell(VStack(spacing: vp(0.0)) {
            CardHeadView(tokens, IconGlyph.Target, "OKR 概览", sub, trailingText: "打开 OKR", asLink: true,
                onLink: {=> navigate("okr")})
            OkrRowsView(tokens, data.objectives, onOpen).fillWidth()
        }.hug().fillWidth(), tokens).fillWidth()
    }
}

/** `.dash-sop-list`（dashboard.css:365-423）。 */
func sopCard(theme: Theme, tokens: ThemeTokens, data: DashboardData, onOpen: (String) -> Unit,
    navigate: (String) -> Unit): Unit {
    if (data.sops.isEmpty()) {
        cardShell(VStack(spacing: vp(0.0)) {
            CardHeadView(tokens, IconGlyph.Workflow, "SOP 快速启动", "最多显示 4 个流程", trailingText: "打开 SOP",
                asLink: true, onLink: {=> navigate("sop")})
            Ui.emptyState(theme, "还没有 SOP", description: "把重复动作画成流程图，之后一键运行。",
                glyph: IconGlyph.Workflow, compact: true)
        }.hug().fillWidth(), tokens).fillWidth()
    } else {
        cardShell(VStack(spacing: vp(0.0)) {
            CardHeadView(tokens, IconGlyph.Workflow, "SOP 快速启动", "最多显示 4 个流程", trailingText: "打开 SOP",
                asLink: true, onLink: {=> navigate("sop")})
            SopRowsView(tokens, data.sops, data.nowIso, onOpen).fillWidth()
        }.hug().fillWidth(), tokens).fillWidth()
    }
}

/** `.dash-activity-list`（dashboard.css:425-508）。 */
func activityCard(theme: Theme, tokens: ThemeTokens, data: DashboardData): Unit {
    if (data.activity.isEmpty()) {
        cardShell(VStack(spacing: vp(0.0)) {
            CardHeadView(tokens, IconGlyph.Clock, "最近活动", "SOP 运行与完成记录，按时间倒序")
            Ui.emptyState(theme, "还没有活动记录",
                description: "完成一个行动，或在 SOP 视图里运行一次流程，这里就会出现时间线。",
                glyph: IconGlyph.Clock, compact: true)
        }.hug().fillWidth(), tokens).fillWidth()
    } else {
        cardShell(VStack(spacing: vp(0.0)) {
            CardHeadView(tokens, IconGlyph.Clock, "最近活动", "SOP 运行与完成记录，按时间倒序")
            ActivityRowsView(tokens, data.activity, data.nowIso).fillWidth()
        }.hug().fillWidth(), tokens).fillWidth()
    }
}

/** 空工作区引导：`.dash-onboarding`（dashboard.css:510-523）。 */
func onboardingCard(theme: Theme, tokens: ThemeTokens, store: AppStore, navigate: (String) -> Unit,
    okrPeriod: String): Unit {
    VStack(spacing: vp(0.0)) {
        Ui.emptyState(theme, "从第一条记录开始",
            description: "工作区还是空的。先去 GTD 收件箱收集一条想法，或者建立第一个目标 / 流程，今日视图会自动聚合它们。",
            glyph: IconGlyph.Workflow,
            action: {=>
                Ui.button(theme, "去 GTD 收集", {=> openGtdCapture(store, navigate)}, variant: ButtonVariant.Primary,
                    size: ControlSize.Sm, iconLeft: IconGlyph.Inbox)
                Ui.button(theme, "创建第一个目标", {=> createObjective(store, navigate, okrPeriod)},
                    variant: ButtonVariant.Secondary, size: ControlSize.Sm, iconLeft: IconGlyph.Target)
                Ui.button(theme, "创建第一个 SOP", {=> createSop(store, navigate)}, variant: ButtonVariant.Secondary,
                    size: ControlSize.Sm, iconLeft: IconGlyph.Workflow)
            })
    }
        .hug()
        .fillWidth()
        .padding(tokens.space.s4)
        .background(tokens.color.surface, tokens.radius.lg)
        .dashedBorder(tokens.color.borderStrong, width: tokens.metrics.borderWidth, radius: tokens.radius.lg,
            dash: 4.0, gap: 3.0)
        .fillWidth()
}

/* ------------------------------------------------------------------ */
/* 空态动作（DashboardPage.tsx:110-133）                               */
/* ------------------------------------------------------------------ */

/** 「去 GTD 收集」：先切到 GTD，再打开快速收集。 */
func openGtdCapture(store: AppStore, navigate: (String) -> Unit): Unit {
    store.setUi({state =>
        state.route = "gtd"
        state.quickCaptureOpen = true
    })
    navigate("gtd")
}

/** 「创建第一个目标」：建 active 目标 → 选中 → 跳 OKR → 通知。 */
func createObjective(store: AppStore, navigate: (String) -> Unit, okrPeriod: String): Unit {
    let patch = OkrPatch()
    patch.period = SetValue<String>.Value(okrPeriod)
    let item = store.createItem(NewItemInput(ItemKind.Objective, "第一个目标",
        status: Some(ItemStatus.Active), okr: Some(patch)))
    store.select(item.id)
    navigate("okr")
    store.notify("目标已创建，接着添加关键结果吧", tone: NoticeTone.Success)
}

/** 「创建第一个 SOP」。 */
func createSop(store: AppStore, navigate: (String) -> Unit): Unit {
    let item = store.createItem(NewItemInput(ItemKind.Sop, "第一个 SOP", status: Some(ItemStatus.Active)))
    store.select(item.id)
    navigate("sop")
    store.notify("SOP 已创建，去画布上添加步骤吧", tone: NoticeTone.Success)
}
