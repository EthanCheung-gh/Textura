/**
 * 演示数据：空库首次加载时播种，保证四个视图打开即有内容。
 * 所有日期都基于「今天」动态生成。
 */
import type {
  Area,
  Edge,
  GanttData,
  GtdData,
  Item,
  ItemKind,
  SopData,
  SopNodeType,
  SopRunEntry,
  Workspace,
} from './model';
import { WORKSPACE_VERSION } from './model';
import { currentQuarter, dayOffset, isoOffset, nowIso } from './utils';

interface ItemSeed extends Partial<Item> {
  id: string;
  kind: ItemKind;
  title: string;
}

function makeItem(seed: ItemSeed, index: number): Item {
  const now = nowIso();
  return {
    notes: '',
    parentId: null,
    order: index,
    status: 'next',
    tags: [],
    areaId: null,
    createdAt: now,
    updatedAt: now,
    completedAt: null,
    ...seed,
  } as Item;
}

function step(
  id: string,
  title: string,
  nodeType: SopNodeType,
  x: number,
  y: number,
  order: number,
  durationMin?: number,
  checklist: SopData['checklist'] = [],
): Item {
  return makeItem(
    {
      id,
      kind: 'step',
      title,
      parentId: 'sop_onboarding',
      order,
      status: 'next',
      areaId: 'area_ops',
      tags: ['onboarding'],
      sop: { nodeType, canvas: { x, y }, checklist, durationMin },
    },
    order,
  );
}

export function buildDemoWorkspace(): Workspace {
  const quarter = currentQuarter();
  const today = new Date();
  const at = (days: number) => isoOffset(days, today);
  const day = (days: number) => dayOffset(days, today);

  const areas: Area[] = [
    { id: 'area_product', name: '产品', color: '#C0663A', order: 0 },
    { id: 'area_ops', name: '运营', color: '#5B7C99', order: 1 },
    { id: 'area_personal', name: '个人', color: '#7C8A5D', order: 2 },
  ];

  const objective: Item = makeItem(
    {
      id: 'obj_activation',
      kind: 'objective',
      title: '让新用户在第一周就爱上织理',
      notes: '本季度聚焦激活与留存，所有 KR 以周为单位复盘。',
      status: 'active',
      tags: ['增长', 'Q1'],
      areaId: 'area_product',
      order: 0,
      createdAt: at(-40),
      updatedAt: at(-1),
      okr: { period: quarter, confidence: 6 },
    },
    0,
  );

  const keyResults: Item[] = [
    makeItem(
      {
        id: 'kr_nps',
        kind: 'keyresult',
        title: 'NPS 从 42 提升到 60',
        parentId: 'obj_activation',
        order: 0,
        status: 'active',
        tags: ['体验'],
        areaId: 'area_product',
        createdAt: at(-38),
        okr: {
          period: quarter,
          confidence: 4,
          metric: { start: 42, target: 60, current: 47, unit: '分' },
          krOwner: '林一',
        },
      },
      1,
    ),
    makeItem(
      {
        id: 'kr_wau',
        kind: 'keyresult',
        title: '周活跃用户 1200 → 2000',
        parentId: 'obj_activation',
        order: 1,
        status: 'active',
        tags: ['增长'],
        areaId: 'area_product',
        createdAt: at(-38),
        okr: {
          period: quarter,
          confidence: 6,
          metric: { start: 1200, target: 2000, current: 1450, unit: '人' },
          krOwner: '周然',
        },
      },
      2,
    ),
    makeItem(
      {
        id: 'kr_conversion',
        kind: 'keyresult',
        title: '付费转化率 2.1% → 3.0%',
        parentId: 'obj_activation',
        order: 2,
        status: 'active',
        tags: ['商业化'],
        areaId: 'area_product',
        createdAt: at(-38),
        okr: {
          period: quarter,
          confidence: 7,
          metric: { start: 2.1, target: 3.0, current: 2.35, unit: '%' },
          krOwner: '陈默',
        },
      },
      3,
    ),
  ];

  const sop: Item = makeItem(
    {
      id: 'sop_onboarding',
      kind: 'sop',
      title: '新用户 onboarding SOP',
      notes: '从注册到完成首次配置的标准流程，异常分支走「提醒补充」。',
      status: 'active',
      tags: ['流程', 'onboarding'],
      areaId: 'area_ops',
      order: 0,
      createdAt: at(-30),
      sop: { nodeType: 'action', canvas: { x: 0, y: 0 }, checklist: [] },
    },
    4,
  );

  const steps: Item[] = [
    step('step_start', '新用户注册', 'start', 40, 160, 0),
    step('step_welcome', '发送欢迎邮件', 'action', 280, 160, 1, 5),
    step('step_collect', '收集团队信息', 'action', 520, 160, 2, 10),
    step('step_decision', '信息是否完整？', 'decision', 760, 160, 3),
    step('step_check', '核对权限配置', 'check', 1000, 160, 4, 5, [
      { id: 'chk_1', text: '管理员账号已创建', done: false },
      { id: 'chk_2', text: '默认工作区已初始化', done: false },
    ]),
    step('step_remind', '提醒补充信息', 'action', 520, 320, 5, 5),
    step('step_end', '完成 onboarding', 'end', 1000, 320, 6),
  ];

  const flowEdges: Edge[] = [
    { id: 'edge_flow_1', from: 'step_start', to: 'step_welcome', type: 'flow', label: '' },
    { id: 'edge_flow_2', from: 'step_welcome', to: 'step_collect', type: 'flow', label: '' },
    { id: 'edge_flow_3', from: 'step_collect', to: 'step_decision', type: 'flow', label: '' },
    { id: 'edge_flow_4', from: 'step_decision', to: 'step_check', type: 'flow', label: '是' },
    { id: 'edge_flow_5', from: 'step_decision', to: 'step_remind', type: 'flow', label: '否' },
    { id: 'edge_flow_6', from: 'step_remind', to: 'step_collect', type: 'flow', label: '补充' },
    { id: 'edge_flow_7', from: 'step_check', to: 'step_end', type: 'flow', label: '通过' },
  ];

  const project: Item = makeItem(
    {
      id: 'proj_website',
      kind: 'project',
      title: '官网改版',
      notes: '把旧站的信息密度降下来，突出织理的工作流叙事。',
      status: 'active',
      tags: ['官网', '品牌'],
      areaId: 'area_product',
      order: 1,
      createdAt: at(-14),
      gantt: { start: day(-10), end: day(13), progress: 35 },
    },
    5,
  );

  const gantt = (start: number, end: number, progress: number): GanttData => ({
    start: day(start),
    end: day(end),
    progress,
  });

  const actions: Item[] = [
    makeItem(
      {
        id: 'act_research',
        kind: 'action',
        title: '需求梳理与竞品盘点',
        parentId: 'proj_website',
        order: 0,
        status: 'done',
        completedAt: at(-6),
        areaId: 'area_product',
        gantt: gantt(-10, -6, 100),
        createdAt: at(-14),
      },
      6,
    ),
    makeItem(
      {
        id: 'act_design',
        kind: 'action',
        title: '视觉稿评审',
        parentId: 'proj_website',
        order: 1,
        status: 'active',
        areaId: 'area_product',
        gantt: gantt(-5, 0, 70),
        createdAt: at(-12),
      },
      7,
    ),
    makeItem(
      {
        id: 'act_ia',
        kind: 'action',
        title: '信息架构重排',
        parentId: 'proj_website',
        order: 2,
        status: 'active',
        areaId: 'area_product',
        gantt: gantt(-2, 4, 40),
        createdAt: at(-9),
      },
      8,
    ),
    makeItem(
      {
        id: 'act_build',
        kind: 'action',
        title: '前端搭建',
        parentId: 'proj_website',
        order: 3,
        status: 'scheduled',
        areaId: 'area_product',
        gantt: gantt(1, 10, 0),
        createdAt: at(-8),
      },
      9,
    ),
    makeItem(
      {
        id: 'act_content',
        kind: 'action',
        title: '内容迁移',
        parentId: 'proj_website',
        order: 4,
        status: 'scheduled',
        areaId: 'area_product',
        gantt: gantt(5, 12, 0),
        createdAt: at(-7),
      },
      10,
    ),
    makeItem(
      {
        id: 'act_launch',
        kind: 'action',
        title: '上线检查',
        parentId: 'proj_website',
        order: 5,
        status: 'scheduled',
        areaId: 'area_product',
        gantt: gantt(11, 13, 0),
        createdAt: at(-6),
      },
      11,
    ),
  ];

  const dependsEdges: Edge[] = [
    { id: 'edge_dep_1', from: 'act_build', to: 'act_design', type: 'depends', label: '依赖视觉稿' },
    { id: 'edge_dep_2', from: 'act_launch', to: 'act_build', type: 'depends', label: '依赖前端' },
  ];

  const gtd = (
    daysAgo: number,
    extra: Omit<GtdData, 'capturedAt' | 'clarified'> = {},
  ): GtdData => ({ capturedAt: at(-daysAgo), clarified: false, ...extra });

  const inbox: Item[] = [
    makeItem(
      {
        id: 'inbox_call_finance',
        kind: 'action',
        title: '给财务回电确认发票抬头',
        status: 'inbox',
        tags: ['杂事'],
        createdAt: at(-1),
        gtd: gtd(1, { context: '电话', energy: 'low', twoMinuteCandidate: true }),
      },
      12,
    ),
    makeItem(
      {
        id: 'inbox_competitor',
        kind: 'reference',
        title: '整理竞品定价截图',
        status: 'inbox',
        notes: '看到三家竞品都在做年付折扣，适合放进定价复盘。',
        createdAt: at(-1),
        gtd: gtd(1, { context: '电脑', energy: 'medium' }),
      },
      13,
    ),
    makeItem(
      {
        id: 'inbox_meeting_notes',
        kind: 'note',
        title: '王敏的会议纪要待归档',
        status: 'inbox',
        createdAt: at(-2),
        gtd: gtd(2, { context: '会议', energy: 'low' }),
      },
      14,
    ),
    makeItem(
      {
        id: 'inbox_book',
        kind: 'note',
        title: '读《重来》第 4 章',
        status: 'inbox',
        areaId: 'area_personal',
        createdAt: at(-3),
        gtd: gtd(3, { context: '通勤', energy: 'medium' }),
      },
      15,
    ),
    makeItem(
      {
        id: 'inbox_dentist',
        kind: 'action',
        title: '预约牙医复查',
        status: 'inbox',
        areaId: 'area_personal',
        createdAt: at(-4),
        gtd: gtd(4, { context: '电话', energy: 'low', twoMinuteCandidate: true }),
      },
      16,
    ),
    makeItem(
      {
        id: 'inbox_podcast',
        kind: 'reference',
        title: '把「Lennys Podcast」加入稍后听',
        status: 'inbox',
        areaId: 'area_personal',
        createdAt: at(-5),
        gtd: gtd(5, { context: '手机', energy: 'low' }),
      },
      17,
    ),
  ];

  const nextItems: Item[] = [
    makeItem(
      {
        id: 'next_email_draft',
        kind: 'action',
        title: '写 onboarding 欢迎邮件初稿',
        parentId: 'sop_onboarding',
        status: 'next',
        areaId: 'area_ops',
        order: 7,
        tags: ['文案'],
        createdAt: at(-3),
        gtd: { capturedAt: at(-3), clarified: true, context: '电脑', energy: 'high' },
      },
      18,
    ),
    makeItem(
      {
        id: 'next_weekly_review',
        kind: 'action',
        title: '整理本周复盘',
        status: 'next',
        areaId: 'area_personal',
        order: 0,
        tags: ['复盘'],
        createdAt: at(-2),
        gtd: { capturedAt: at(-2), clarified: true, context: '电脑', energy: 'medium' },
      },
      19,
    ),
    makeItem(
      {
        id: 'next_pricing_copy',
        kind: 'action',
        title: '更新定价页文案',
        status: 'next',
        areaId: 'area_product',
        order: 1,
        tags: ['官网'],
        createdAt: at(-1),
        gtd: { capturedAt: at(-1), clarified: true, context: '电脑', energy: 'high' },
      },
      20,
    ),
  ];

  const waiting: Item = makeItem(
    {
      id: 'waiting_legal',
      kind: 'action',
      title: '等待法务审核隐私政策',
      status: 'waiting',
      areaId: 'area_product',
      createdAt: at(-6),
      updatedAt: at(-2),
      gtd: {
        capturedAt: at(-6),
        clarified: true,
        context: '邮件',
        energy: 'low',
        waitingFor: '法务 · 张律师',
      },
    },
    21,
  );

  const someday: Item = makeItem(
    {
      id: 'someday_rust',
      kind: 'action',
      title: '学习 Rust 宏与过程宏',
      status: 'someday',
      areaId: 'area_personal',
      createdAt: at(-9),
      gtd: { capturedAt: at(-9), clarified: true, context: '电脑', energy: 'high' },
    },
    22,
  );

  const runs: SopRunEntry[] = [
    {
      id: 'run_1',
      sopId: 'sop_onboarding',
      stepId: 'step_welcome',
      at: at(-2),
      result: 'pass',
      note: '欢迎邮件打开率 62%',
    },
    {
      id: 'run_2',
      sopId: 'sop_onboarding',
      stepId: 'step_collect',
      at: at(-2),
      result: 'pass',
      note: '',
    },
    {
      id: 'run_3',
      sopId: 'sop_onboarding',
      stepId: 'step_decision',
      at: at(-1),
      result: 'fail',
      note: '缺少手机号，已走提醒分支',
    },
  ];

  const okrEdges: Edge[] = keyResults.map((kr) => ({
    id: `edge_okr_${kr.id}`,
    from: 'obj_activation',
    to: kr.id,
    type: 'okr',
    label: '',
  }));

  const items: Item[] = [
    objective,
    ...keyResults,
    sop,
    ...steps,
    project,
    ...actions,
    ...inbox,
    ...nextItems,
    waiting,
    someday,
  ];

  return {
    version: WORKSPACE_VERSION,
    items,
    edges: [...okrEdges, ...flowEdges, ...dependsEdges],
    areas,
    runs,
    updatedAt: nowIso(),
  };
}

export function createSeedWorkspace(): Workspace {
  return buildDemoWorkspace();
}
