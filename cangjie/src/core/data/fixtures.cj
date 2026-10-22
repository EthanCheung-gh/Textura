package textura.core.data

import std.collection.*

/**
 * Demo data seeded into an empty database, ported from `src/core/fixtures.ts`.
 *
 * Every date is relative to the injected `Clock`, so the parity fixture
 * (`docs/PARITY.md`: anchor `2026-03-16T10:00:00+08:00`) is reproducible: seed
 * with `FixedClock` and the output never drifts.
 */
public func buildDemoWorkspace(clock: Clock): Workspace {
    let quarter = currentQuarter(clock)
    let now = clock.nowMillis()
    let anchor = nowIso(clock)
    let areas: Array<Area> = [
        Area("area_product", "产品", "#C0663A", order: 0),
        Area("area_ops", "运营", "#5B7C99", order: 1),
        Area("area_personal", "个人", "#7C8A5D", order: 2)
    ]

    let items = ArrayList<Item>()

    items.add(Item(
        "obj_activation",
        ItemKind.Objective,
        "让新用户在第一周就爱上织理",
        notes: "本季度聚焦激活与留存，所有 KR 以周为单位复盘。",
        order: 0,
        status: ItemStatus.Active,
        tags: ["增长", "Q1"],
        areaId: "area_product",
        createdAt: isoOffset(-40, now),
        updatedAt: isoOffset(-1, now),
        okr: OkrData(quarter, 6)
    ))

    items.add(Item(
        "kr_nps",
        ItemKind.KeyResult,
        "NPS 从 42 提升到 60",
        parentId: "obj_activation",
        order: 0,
        status: ItemStatus.Active,
        tags: ["体验"],
        areaId: "area_product",
        createdAt: isoOffset(-38, now),
        updatedAt: anchor,
        okr: OkrData(quarter, 4, metric: Metric(42.0, 60.0, 47.0, "分"), krOwner: "林一")
    ))
    items.add(Item(
        "kr_wau",
        ItemKind.KeyResult,
        "周活跃用户 1200 → 2000",
        parentId: "obj_activation",
        order: 1,
        status: ItemStatus.Active,
        tags: ["增长"],
        areaId: "area_product",
        createdAt: isoOffset(-38, now),
        updatedAt: anchor,
        okr: OkrData(quarter, 6, metric: Metric(1200.0, 2000.0, 1450.0, "人"), krOwner: "周然")
    ))
    items.add(Item(
        "kr_conversion",
        ItemKind.KeyResult,
        "付费转化率 2.1% → 3.0%",
        parentId: "obj_activation",
        order: 2,
        status: ItemStatus.Active,
        tags: ["商业化"],
        areaId: "area_product",
        createdAt: isoOffset(-38, now),
        updatedAt: anchor,
        okr: OkrData(quarter, 7, metric: Metric(2.1, 3.0, 2.35, "%"), krOwner: "陈默")
    ))

    items.add(Item(
        "sop_onboarding",
        ItemKind.Sop,
        "新用户 onboarding SOP",
        notes: "从注册到完成首次配置的标准流程，异常分支走「提醒补充」。",
        order: 0,
        status: ItemStatus.Active,
        tags: ["流程", "onboarding"],
        areaId: "area_ops",
        createdAt: isoOffset(-30, now),
        updatedAt: anchor,
        sop: SopData(SopNodeType.Action)
    ))

    items.add(seedStep("step_start", "新用户注册", SopNodeType.Start, 40.0, 160.0, 0, None, [], anchor))
    items.add(seedStep("step_welcome", "发送欢迎邮件", SopNodeType.Action, 280.0, 160.0, 1, Some(5), [], anchor))
    items.add(seedStep("step_collect", "收集团队信息", SopNodeType.Action, 520.0, 160.0, 2, Some(10), [], anchor))
    items.add(seedStep("step_decision", "信息是否完整？", SopNodeType.Decision, 760.0, 160.0, 3, None, [], anchor))
    items.add(seedStep(
        "step_check",
        "核对权限配置",
        SopNodeType.Check,
        1000.0,
        160.0,
        4,
        Some(5),
        [
            ChecklistEntry("chk_1", "管理员账号已创建", false),
            ChecklistEntry("chk_2", "默认工作区已初始化", false)
        ],
        anchor
    ))
    items.add(seedStep("step_remind", "提醒补充信息", SopNodeType.Action, 520.0, 320.0, 5, Some(5), [], anchor))
    items.add(seedStep("step_end", "完成 onboarding", SopNodeType.End, 1000.0, 320.0, 6, None, [], anchor))

    items.add(Item(
        "proj_website",
        ItemKind.Project,
        "官网改版",
        notes: "把旧站的信息密度降下来，突出织理的工作流叙事。",
        order: 1,
        status: ItemStatus.Active,
        tags: ["官网", "品牌"],
        areaId: "area_product",
        createdAt: isoOffset(-14, now),
        updatedAt: anchor,
        gantt: GanttData(start: dayOffset(-10, now), end: dayOffset(13, now), progress: 35.0)
    ))

    items.add(seedAction("act_research", "需求梳理与竞品盘点", 0, ItemStatus.Done, -14, Some(-10), Some(-6), 100.0, Some(isoOffset(-6, now)), anchor, now))
    items.add(seedAction("act_design", "视觉稿评审", 1, ItemStatus.Active, -12, Some(-5), Some(0), 70.0, None, anchor, now))
    items.add(seedAction("act_ia", "信息架构重排", 2, ItemStatus.Active, -9, Some(-2), Some(4), 40.0, None, anchor, now))
    items.add(seedAction("act_build", "前端搭建", 3, ItemStatus.Scheduled, -8, Some(1), Some(10), 0.0, None, anchor, now))
    items.add(seedAction("act_content", "内容迁移", 4, ItemStatus.Scheduled, -7, Some(5), Some(12), 0.0, None, anchor, now))
    items.add(seedAction("act_launch", "上线检查", 5, ItemStatus.Scheduled, -6, Some(11), Some(13), 0.0, None, anchor, now))

    items.add(Item(
        "inbox_call_finance",
        ItemKind.Action,
        "给财务回电确认发票抬头",
        order: 12,
        status: ItemStatus.Inbox,
        tags: ["杂事"],
        createdAt: isoOffset(-1, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-1, now), false, context: "电话", energy: Energy.Low, twoMinuteCandidate: true)
    ))
    items.add(Item(
        "inbox_competitor",
        ItemKind.Reference,
        "整理竞品定价截图",
        notes: "看到三家竞品都在做年付折扣，适合放进定价复盘。",
        order: 13,
        status: ItemStatus.Inbox,
        createdAt: isoOffset(-1, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-1, now), false, context: "电脑", energy: Energy.Medium)
    ))
    items.add(Item(
        "inbox_meeting_notes",
        ItemKind.Note,
        "王敏的会议纪要待归档",
        order: 14,
        status: ItemStatus.Inbox,
        createdAt: isoOffset(-2, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-2, now), false, context: "会议", energy: Energy.Low)
    ))
    items.add(Item(
        "inbox_book",
        ItemKind.Note,
        "读《重来》第 4 章",
        order: 15,
        status: ItemStatus.Inbox,
        areaId: "area_personal",
        createdAt: isoOffset(-3, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-3, now), false, context: "通勤", energy: Energy.Medium)
    ))
    items.add(Item(
        "inbox_dentist",
        ItemKind.Action,
        "预约牙医复查",
        order: 16,
        status: ItemStatus.Inbox,
        areaId: "area_personal",
        createdAt: isoOffset(-4, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-4, now), false, context: "电话", energy: Energy.Low, twoMinuteCandidate: true)
    ))
    items.add(Item(
        "inbox_podcast",
        ItemKind.Reference,
        "把「Lennys Podcast」加入稍后听",
        order: 17,
        status: ItemStatus.Inbox,
        areaId: "area_personal",
        createdAt: isoOffset(-5, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-5, now), false, context: "手机", energy: Energy.Low)
    ))

    items.add(Item(
        "next_email_draft",
        ItemKind.Action,
        "写 onboarding 欢迎邮件初稿",
        parentId: "sop_onboarding",
        order: 7,
        status: ItemStatus.Next,
        tags: ["文案"],
        areaId: "area_ops",
        createdAt: isoOffset(-3, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-3, now), true, context: "电脑", energy: Energy.High)
    ))
    items.add(Item(
        "next_weekly_review",
        ItemKind.Action,
        "整理本周复盘",
        order: 0,
        status: ItemStatus.Next,
        tags: ["复盘"],
        areaId: "area_personal",
        createdAt: isoOffset(-2, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-2, now), true, context: "电脑", energy: Energy.Medium)
    ))
    items.add(Item(
        "next_pricing_copy",
        ItemKind.Action,
        "更新定价页文案",
        order: 1,
        status: ItemStatus.Next,
        tags: ["官网"],
        areaId: "area_product",
        createdAt: isoOffset(-1, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-1, now), true, context: "电脑", energy: Energy.High)
    ))
    items.add(Item(
        "waiting_legal",
        ItemKind.Action,
        "等待法务审核隐私政策",
        order: 21,
        status: ItemStatus.Waiting,
        areaId: "area_product",
        createdAt: isoOffset(-6, now),
        updatedAt: isoOffset(-2, now),
        gtd: GtdData(isoOffset(-6, now), true, context: "邮件", energy: Energy.Low, waitingFor: "法务 · 张律师")
    ))
    items.add(Item(
        "someday_rust",
        ItemKind.Action,
        "学习 Rust 宏与过程宏",
        order: 22,
        status: ItemStatus.Someday,
        areaId: "area_personal",
        createdAt: isoOffset(-9, now),
        updatedAt: anchor,
        gtd: GtdData(isoOffset(-9, now), true, context: "电脑", energy: Energy.High)
    ))

    let edges = ArrayList<Edge>()
    edges.add(Edge("edge_okr_kr_nps", "obj_activation", "kr_nps", EdgeType.Okr))
    edges.add(Edge("edge_okr_kr_wau", "obj_activation", "kr_wau", EdgeType.Okr))
    edges.add(Edge("edge_okr_kr_conversion", "obj_activation", "kr_conversion", EdgeType.Okr))
    edges.add(Edge("edge_flow_1", "step_start", "step_welcome", EdgeType.Flow))
    edges.add(Edge("edge_flow_2", "step_welcome", "step_collect", EdgeType.Flow))
    edges.add(Edge("edge_flow_3", "step_collect", "step_decision", EdgeType.Flow))
    edges.add(Edge("edge_flow_4", "step_decision", "step_check", EdgeType.Flow, label: "是"))
    edges.add(Edge("edge_flow_5", "step_decision", "step_remind", EdgeType.Flow, label: "否"))
    edges.add(Edge("edge_flow_6", "step_remind", "step_collect", EdgeType.Flow, label: "补充"))
    edges.add(Edge("edge_flow_7", "step_check", "step_end", EdgeType.Flow, label: "通过"))
    edges.add(Edge("edge_dep_1", "act_build", "act_design", EdgeType.Depends, label: "依赖视觉稿"))
    edges.add(Edge("edge_dep_2", "act_launch", "act_build", EdgeType.Depends, label: "依赖前端"))

    let runs: Array<SopRunEntry> = [
        SopRunEntry("run_1", "sop_onboarding", "step_welcome", isoOffset(-2, now), RunResult.Pass, note: "欢迎邮件打开率 62%"),
        SopRunEntry("run_2", "sop_onboarding", "step_collect", isoOffset(-2, now), RunResult.Pass),
        SopRunEntry("run_3", "sop_onboarding", "step_decision", isoOffset(-1, now), RunResult.Fail, note: "缺少手机号，已走提醒分支")
    ]

    Workspace(
        version: WORKSPACE_VERSION,
        items: items.toArray(),
        edges: edges.toArray(),
        areas: areas,
        runs: runs,
        updatedAt: anchor
    )
}

func seedStep(
    id: String,
    title: String,
    nodeType: SopNodeType,
    x: Float64,
    y: Float64,
    order: Int64,
    durationMin: ?Int64,
    checklist: Array<ChecklistEntry>,
    anchor: String
): Item {
    Item(
        id,
        ItemKind.Step,
        title,
        parentId: "sop_onboarding",
        order: order,
        status: ItemStatus.Next,
        tags: ["onboarding"],
        areaId: "area_ops",
        createdAt: anchor,
        updatedAt: anchor,
        sop: SopData(nodeType, canvas: CanvasPos(x, y), checklist: checklist, durationMin: durationMin)
    )
}

func seedAction(
    id: String,
    title: String,
    order: Int64,
    status: ItemStatus,
    createdAtDays: Int64,
    startDays: ?Int64,
    endDays: ?Int64,
    progress: Float64,
    completedAt: ?String,
    anchor: String,
    now: Int64
): Item {
    let start: ?String = match (startDays) {
        case Some(days) => Some(dayOffset(days, now))
        case None => None
    }
    let end: ?String = match (endDays) {
        case Some(days) => Some(dayOffset(days, now))
        case None => None
    }
    Item(
        id,
        ItemKind.Action,
        title,
        parentId: "proj_website",
        order: order,
        status: status,
        areaId: "area_product",
        createdAt: isoOffset(createdAtDays, now),
        updatedAt: anchor,
        completedAt: completedAt,
        gantt: GanttData(start: start, end: end, progress: progress)
    )
}

public func createSeedWorkspace(clock: Clock): Workspace {
    buildDemoWorkspace(clock)
}
