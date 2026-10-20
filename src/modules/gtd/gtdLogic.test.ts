import { describe, expect, it } from 'vitest';
import type { Area, Item, Workspace } from '../../core/model';
import { dayOffset, nowIso } from '../../core/utils';
import { completedThisWeek } from '../dashboard/today';
import {
  NO_CONTEXT,
  NO_CONTEXT_FILTER,
  buildClarifyNewItem,
  buildClarifyPatch,
  clarifyTargetStatus,
  createClarifyForm,
  currentDateKey,
  filterNextActions,
  groupByContext,
  isStuckProject,
  isWaitingOverdue,
  localDayKey,
  relativeTimeLabel,
  sortNextActions,
  validateClarifyForm,
  waitingDays,
  weeklyReview,
} from './gtdLogic';
import type { ClarifyFormState } from './gtdLogic';

/** 用本地日历日构造时间戳，避免测试依赖跑测机器的时区。 */
function atDay(offset: number, hour = 12): string {
  const base = new Date();
  return new Date(base.getFullYear(), base.getMonth(), base.getDate() + offset, hour, 0, 0).toISOString();
}

function expectedLocalKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function makeItem(seed: Partial<Item> & Pick<Item, 'id' | 'kind' | 'title'>): Item {
  const now = nowIso();
  return {
    notes: '',
    parentId: null,
    order: 0,
    status: 'next',
    tags: [],
    areaId: null,
    createdAt: now,
    updatedAt: now,
    completedAt: null,
    ...seed,
  };
}

function makeWorkspace(items: Item[], areas: Area[] = []): Workspace {
  return { version: 1, items, edges: [], areas, runs: [], updatedAt: nowIso() };
}

describe('groupByContext', () => {
  it('把 null/空场景归入「无场景」，空组不出现', () => {
    const phone = makeItem({
      id: 'a',
      kind: 'action',
      title: '打电话',
      gtd: { capturedAt: atDay(-1), clarified: true, context: '电话' },
    });
    const none = makeItem({ id: 'b', kind: 'action', title: '无场景任务' });
    const computer = makeItem({
      id: 'c',
      kind: 'action',
      title: '写文档',
      gtd: { capturedAt: atDay(-2), clarified: true, context: '电脑' },
    });
    const phone2 = makeItem({
      id: 'd',
      kind: 'action',
      title: '再打一个电话',
      gtd: { capturedAt: atDay(-3), clarified: true, context: '电话' },
    });

    const groups = groupByContext([phone, none, computer, phone2]);
    expect(groups.map((group) => group.context)).toEqual(['电脑', '电话', NO_CONTEXT]);
    expect(groups.find((group) => group.context === '电话')?.items.map((item) => item.id)).toEqual([
      'a',
      'd',
    ]);
    expect(groups.find((group) => group.context === NO_CONTEXT)?.items.map((item) => item.id)).toEqual([
      'b',
    ]);
  });

  it('组顺序稳定，与输入顺序无关', () => {
    const phone = makeItem({
      id: 'a',
      kind: 'action',
      title: '电话',
      gtd: { capturedAt: atDay(-1), clarified: true, context: '电话' },
    });
    const computer = makeItem({
      id: 'b',
      kind: 'action',
      title: '电脑',
      gtd: { capturedAt: atDay(-1), clarified: true, context: '电脑' },
    });
    const custom = makeItem({
      id: 'c',
      kind: 'action',
      title: '通勤',
      gtd: { capturedAt: atDay(-1), clarified: true, context: '通勤' },
    });
    const none = makeItem({ id: 'd', kind: 'action', title: '无场景' });

    const a = groupByContext([phone, computer, custom, none]).map((group) => group.context);
    const b = groupByContext([none, custom, computer, phone]).map((group) => group.context);
    expect(a).toEqual(['电脑', '电话', '通勤', NO_CONTEXT]);
    expect(b).toEqual(a);
  });
});

describe('sortNextActions', () => {
  it('截止日期优先（早→晚），无日期排后；同日期按能量高→低；再按创建时间', () => {
    const later = makeItem({
      id: 'later',
      kind: 'action',
      title: '两天后',
      createdAt: atDay(-5),
      gantt: { start: null, end: dayOffset(2), progress: 0 },
      gtd: { capturedAt: atDay(-5), clarified: true, energy: 'low' },
    });
    const overdue = makeItem({
      id: 'overdue',
      kind: 'action',
      title: '昨天到期',
      createdAt: atDay(-4),
      gantt: { start: null, end: dayOffset(-1), progress: 0 },
      gtd: { capturedAt: atDay(-4), clarified: true, energy: 'low' },
    });
    const undatedHigh = makeItem({
      id: 'undated-high',
      kind: 'action',
      title: '无日期高能量',
      createdAt: atDay(-3),
      gtd: { capturedAt: atDay(-3), clarified: true, energy: 'high' },
    });
    const undatedLowOld = makeItem({
      id: 'undated-low-old',
      kind: 'action',
      title: '无日期低能量',
      createdAt: atDay(-6),
      gtd: { capturedAt: atDay(-6), clarified: true, energy: 'low' },
    });
    const undatedLowNew = makeItem({
      id: 'undated-low-new',
      kind: 'action',
      title: '无日期低能量新',
      createdAt: atDay(-2),
      gtd: { capturedAt: atDay(-2), clarified: true, energy: 'low' },
    });

    const result = sortNextActions([
      undatedLowNew,
      undatedHigh,
      later,
      undatedLowOld,
      overdue,
    ]);
    expect(result.map((item) => item.id)).toEqual([
      'overdue',
      'later',
      'undated-high',
      'undated-low-old',
      'undated-low-new',
    ]);
  });
});

describe('isStuckProject', () => {
  const project = makeItem({
    id: 'p1',
    kind: 'project',
    title: '官网改版',
    status: 'active',
    gantt: { start: null, end: dayOffset(10), progress: 20 },
  });

  it('有 next 子动作 → 不 stalled', () => {
    const child = makeItem({ id: 'c1', kind: 'action', title: '写文案', parentId: 'p1', status: 'next' });
    expect(isStuckProject(makeWorkspace([project, child]), 'p1')).toBe(false);
  });

  it('全部子动作完成 → 不算停滞', () => {
    const child = makeItem({ id: 'c1', kind: 'action', title: '写文案', parentId: 'p1', status: 'done' });
    const child2 = makeItem({ id: 'c2', kind: 'action', title: '上线', parentId: 'p1', status: 'done' });
    expect(isStuckProject(makeWorkspace([project, child, child2]), 'p1')).toBe(false);
  });

  it('无子动作 → 停滞', () => {
    expect(isStuckProject(makeWorkspace([project]), 'p1')).toBe(true);
  });

  it('有未完成但没有 next → 停滞', () => {
    const child = makeItem({ id: 'c1', kind: 'action', title: '写文案', parentId: 'p1', status: 'active' });
    expect(isStuckProject(makeWorkspace([project, child]), 'p1')).toBe(true);
  });

  it('已完成的项目 / 不存在的 id → false', () => {
    const doneProject = makeItem({ id: 'p2', kind: 'project', title: '完成的项目', status: 'done' });
    expect(isStuckProject(makeWorkspace([doneProject]), 'p2')).toBe(false);
    expect(isStuckProject(makeWorkspace([project]), 'missing')).toBe(false);
  });
});

describe('waitingDays / 超 7 天', () => {
  const today = currentDateKey();

  it('从 gtd.capturedAt 起算', () => {
    const item = makeItem({
      id: 'w1',
      kind: 'action',
      title: '等回复',
      status: 'waiting',
      gtd: { capturedAt: atDay(-3), clarified: true, waitingFor: '张律师' },
    });
    expect(waitingDays(item, today)).toBe(3);
    expect(isWaitingOverdue(item, today)).toBe(false);
  });

  it('严格超过 7 天才提醒', () => {
    const item = makeItem({
      id: 'w2',
      kind: 'action',
      title: '等回复',
      status: 'waiting',
      gtd: { capturedAt: atDay(-8), clarified: true, waitingFor: '张律师' },
    });
    expect(waitingDays(item, today)).toBe(8);
    expect(isWaitingOverdue(item, today)).toBe(true);
  });

  it('没有 capturedAt 时退回 updatedAt，未来时间归零', () => {
    const fallback = makeItem({
      id: 'w3',
      kind: 'action',
      title: '等回复',
      status: 'waiting',
      updatedAt: atDay(-10),
    });
    expect(waitingDays(fallback, today)).toBe(10);
    const future = makeItem({
      id: 'w4',
      kind: 'action',
      title: '未来',
      status: 'waiting',
      updatedAt: atDay(2),
    });
    expect(waitingDays(future, today)).toBe(0);
  });
});

describe('本地日历日 / 7 天窗口', () => {
  /**
   * 在 Asia/Shanghai 下，本地 2026-10-15 01:01 正好序列化为报告中的
   * 2026-10-14T17:01:00.000Z；在其他时区它仍是本地 10-15 凌晨。
   * 用本地时间构造可保证任一 TZ 下断言稳定。
   */
  const completedLocal = new Date(2026, 9, 15, 1, 1, 0);
  const completedIso = completedLocal.toISOString();
  const now = new Date(2026, 9, 21, 9, 0, 0);
  const today = currentDateKey(now);

  it('localDayKey 按本地日历日归档，而不是截取 UTC 字符串', () => {
    expect(localDayKey(completedIso)).toBe('2026-10-15');
    expect(localDayKey('2026-10-14T17:01:00Z')).toBe(
      expectedLocalKey(new Date('2026-10-14T17:01:00Z')),
    );
    expect(localDayKey('2026-10-15')).toBe('2026-10-15');
    expect(localDayKey(null)).toBeNull();
    expect(localDayKey('not-a-date')).toBeNull();
  });

  it('waitingDays 不再因 UTC 日期截断少算一天', () => {
    const item = makeItem({
      id: 'w-local',
      kind: 'action',
      title: '等回复',
      status: 'waiting',
      gtd: { capturedAt: completedIso, clarified: true, waitingFor: '张律师' },
    });
    expect(waitingDays(item, today)).toBe(6);
  });

  it('relativeTimeLabel 在本地凌晨不会漂移成「昨天」', () => {
    const sameDayEarly = new Date(2026, 9, 21, 1, 0, 0).toISOString();
    expect(relativeTimeLabel(sameDayEarly, now)).toBe('今天');
    expect(relativeTimeLabel(completedIso, now)).toBe('6 天前');
    const yesterdayLate = new Date(2026, 9, 20, 23, 30, 0).toISOString();
    expect(relativeTimeLabel(yesterdayLate, now)).toBe('昨天');
  });

  it('本周完成窗口（今天−6 至今天，含边界）与今日页逐日对齐', () => {
    const items: Item[] = [
      makeItem({
        id: 'boundary-in',
        kind: 'action',
        title: '窗口第一天凌晨',
        status: 'done',
        completedAt: completedIso,
      }),
      makeItem({
        id: 'boundary-out',
        kind: 'action',
        title: '窗口前一天深夜',
        status: 'done',
        completedAt: new Date(2026, 9, 14, 23, 59, 0).toISOString(),
      }),
      makeItem({
        id: 'today-done',
        kind: 'action',
        title: '今天完成',
        status: 'done',
        completedAt: new Date(2026, 9, 21, 0, 30, 0).toISOString(),
      }),
    ];
    const ws = makeWorkspace(items);
    const stats = weeklyReview(ws, today);
    const gtdIds = stats.completedThisWeek.map((item) => item.id);
    const dashboardIds = completedThisWeek(ws, now).map((item) => item.id);

    expect(stats.windowStart).toBe('2026-10-15');
    expect(stats.today).toBe('2026-10-21');
    expect(gtdIds).toEqual(['today-done', 'boundary-in']);
    expect(dashboardIds).toEqual(gtdIds);
  });

  it('演示数据 act_research 场景：GTD 与今日页都算作最近 7 天完成', () => {
    const item = makeItem({
      id: 'act_research',
      kind: 'action',
      title: '需求梳理与竞品盘点',
      status: 'done',
      completedAt: completedIso,
    });
    const ws = makeWorkspace([item]);
    const stats = weeklyReview(ws, today);
    const dashboard = completedThisWeek(ws, now);

    expect(stats.completedCount).toBe(1);
    expect(dashboard.map((entry) => entry.id)).toEqual(['act_research']);
    expect(stats.completedThisWeek.map((entry) => entry.id)).toEqual(
      dashboard.map((entry) => entry.id),
    );
  });
});

describe('weeklyReview', () => {
  it('统计本周完成、超期、无日期、等待超 7 天、停滞项目与收件箱进度', () => {
    const project = makeItem({
      id: 'p1',
      kind: 'project',
      title: '官网改版',
      status: 'active',
      gantt: { start: dayOffset(-5), end: dayOffset(8), progress: 20 },
    });
    const items: Item[] = [
      makeItem({
        id: 'inbox1',
        kind: 'action',
        title: '待澄清',
        status: 'inbox',
        gtd: { capturedAt: atDay(-1), clarified: false },
      }),
      makeItem({
        id: 'done-this-week',
        kind: 'action',
        title: '本周完成',
        status: 'done',
        completedAt: atDay(-2),
        gtd: { capturedAt: atDay(-5), clarified: true },
      }),
      makeItem({
        id: 'done-old',
        kind: 'action',
        title: '很久以前完成',
        status: 'done',
        completedAt: atDay(-10),
      }),
      makeItem({
        id: 'overdue',
        kind: 'action',
        title: '超期',
        status: 'next',
        gantt: { start: null, end: dayOffset(-2), progress: 0 },
      }),
      makeItem({
        id: 'due-today',
        kind: 'action',
        title: '今天到期',
        status: 'next',
        gantt: { start: null, end: dayOffset(0), progress: 0 },
      }),
      makeItem({ id: 'undated', kind: 'action', title: '无日期', status: 'next' }),
      makeItem({
        id: 'waiting-old',
        kind: 'action',
        title: '等待很久',
        status: 'waiting',
        gtd: { capturedAt: atDay(-9), clarified: true, waitingFor: '法务' },
      }),
      makeItem({
        id: 'cleared',
        kind: 'action',
        title: '本周已澄清',
        status: 'next',
        gantt: { start: null, end: dayOffset(3), progress: 0 },
        gtd: { capturedAt: atDay(-2), clarified: true },
      }),
      project,
    ];
    const stats = weeklyReview(makeWorkspace(items), currentDateKey());

    expect(stats.inboxCount).toBe(1);
    expect(stats.inboxClearedCount).toBe(2);
    expect(stats.inboxProgress).toBe(67);
    expect(stats.completedCount).toBe(1);
    expect(stats.completedThisWeek.map((item) => item.id)).toEqual(['done-this-week']);
    expect(stats.overdueCount).toBe(1);
    expect(stats.overdue.map((item) => item.id)).toEqual(['overdue']);
    expect(stats.undatedCount).toBe(1);
    expect(stats.undatedTasks.map((item) => item.id)).toEqual(['undated']);
    expect(stats.waitingOverdueCount).toBe(1);
    expect(stats.stuckProjectCount).toBe(1);
    expect(stats.staleAreas).toHaveLength(0);
  });

  it('空工作区收件箱进度为 100', () => {
    const stats = weeklyReview(makeWorkspace([]), currentDateKey());
    expect(stats.inboxProgress).toBe(100);
    expect(stats.inboxCount).toBe(0);
    expect(stats.completedCount).toBe(0);
  });
});

describe('filterNextActions', () => {
  const items = [
    makeItem({
      id: 'a',
      kind: 'action',
      title: '写官网文案',
      tags: ['官网'],
      gantt: { start: null, end: dayOffset(-1), progress: 0 },
      gtd: { capturedAt: atDay(-2), clarified: true, context: '电脑' },
    }),
    makeItem({
      id: 'b',
      kind: 'action',
      title: '打电话',
      gantt: { start: null, end: dayOffset(3), progress: 0 },
      gtd: { capturedAt: atDay(-1), clarified: true, context: '电话' },
    }),
    makeItem({ id: 'c', kind: 'action', title: '无场景任务' }),
  ];

  it('按场景、无场景哨兵、今天/超期、搜索过滤', () => {
    const today = currentDateKey();
    expect(
      filterNextActions(items, {
        context: '电脑',
        dueSoonOnly: false,
        areaId: null,
        search: '',
        today,
      }).map((item) => item.id),
    ).toEqual(['a']);
    expect(
      filterNextActions(items, {
        context: NO_CONTEXT_FILTER,
        dueSoonOnly: false,
        areaId: null,
        search: '',
        today,
      }).map((item) => item.id),
    ).toEqual(['c']);
    expect(
      filterNextActions(items, {
        context: null,
        dueSoonOnly: true,
        areaId: null,
        search: '',
        today,
      }).map((item) => item.id),
    ).toEqual(['a']);
    expect(
      filterNextActions(items, {
        context: null,
        dueSoonOnly: false,
        areaId: null,
        search: '文案',
        today,
      }).map((item) => item.id),
    ).toEqual(['a']);
  });
});

describe('澄清表单 → patch', () => {
  const baseForm: ClarifyFormState = {
    type: 'next',
    title: '  给财务回电  ',
    notes: '确认发票抬头',
    tags: '#杂事, 财务，杂事',
    areaId: 'area_product',
    context: '__custom__',
    customContext: '飞机上',
    energy: 'high',
    estimateMin: 2,
    dueDate: '2026-01-02',
    delegated: false,
    waitingFor: '',
    someday: false,
    twoMinuteCandidate: false,
  };

  it('映射标题、标签、领域、日期与 gtd 字段', () => {
    const patch = buildClarifyPatch(baseForm);
    expect(patch.title).toBe('给财务回电');
    expect(patch.tags).toEqual(['杂事', '财务']);
    expect(patch.areaId).toBe('area_product');
    expect(patch.gantt).toEqual({ end: '2026-01-02' });
    expect(patch.gtd).toEqual({
      clarified: true,
      context: '飞机上',
      energy: 'high',
      waitingFor: '',
      twoMinuteCandidate: true,
    });
    expect(clarifyTargetStatus(baseForm)).toBe('next');
  });

  it('委派 → waiting；someday → someday；归档 → done', () => {
    expect(clarifyTargetStatus({ ...baseForm, delegated: true, waitingFor: '张律师' })).toBe('waiting');
    expect(clarifyTargetStatus({ ...baseForm, someday: true })).toBe('someday');
    expect(clarifyTargetStatus({ ...baseForm, type: 'reference' })).toBe('done');
    expect(clarifyTargetStatus({ ...baseForm, type: 'note' })).toBe('done');
  });

  it('标题必填、委派必须填等待对象、委派与 someday 互斥', () => {
    expect(validateClarifyForm({ ...baseForm, title: '   ' }).title).toBeTruthy();
    expect(validateClarifyForm({ ...baseForm, delegated: true, waitingFor: '  ' }).waitingFor).toBeTruthy();
    expect(
      validateClarifyForm({ ...baseForm, delegated: true, waitingFor: '张律师', someday: true }).status,
    ).toBeTruthy();
    expect(validateClarifyForm(baseForm)).toEqual({});
  });

  it('创建 action / project 时带上目标状态与来源 capturedAt', () => {
    const source = makeItem({
      id: 'inbox1',
      kind: 'action',
      title: '旧标题',
      gtd: { capturedAt: atDay(-4), clarified: false, context: '电话' },
    });
    const action = buildClarifyNewItem(baseForm, source, 'next');
    expect(action.kind).toBe('action');
    expect(action.status).toBe('next');
    expect(action.gtd?.capturedAt).toBe(source.gtd?.capturedAt);

    const project = buildClarifyNewItem({ ...baseForm, type: 'project' }, source, 'next');
    expect(project.kind).toBe('project');
  });

  it('从现有条目初始化表单：自定义场景进入 custom 输入', () => {
    const item = makeItem({
      id: 'x',
      kind: 'reference',
      title: '竞品截图',
      tags: ['竞品', '定价'],
      areaId: 'area_product',
      status: 'inbox',
      gtd: {
        capturedAt: atDay(-1),
        clarified: false,
        context: '通勤',
        energy: 'medium',
        twoMinuteCandidate: true,
      },
      gantt: { start: null, end: dayOffset(4), progress: 0 },
    });
    const form = createClarifyForm(item);
    expect(form.type).toBe('reference');
    expect(form.context).toBe('__custom__');
    expect(form.customContext).toBe('通勤');
    expect(form.estimateMin).toBe(2);
    expect(form.dueDate).toBe(dayOffset(4));
  });
});
