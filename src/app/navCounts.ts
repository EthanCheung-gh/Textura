/**
 * 侧栏导航徽标：把「每个视图关心多少东西」压成一个数字。
 *
 * 口径（刻意固定，改动前请先对齐产品语义，而不是就着 UI 改）。
 *
 * 核心原则：徽标是「点进去会看到多少条」的预告。预测值必须与目标视图首屏列表等长，
 * 否则不如不显示。每个数字的对照基准写在对应条目里。
 * - dashboard「今日焦点」= 与 DashboardPage「今日聚焦」列表等长，即
 *   overdue ∪ dueToday ∪ (nextActions 中无 gantt.end 的)，按 id 去重；三者都要求
 *   未完成/未放弃（selector 内的 isOpen / status='next' 保证）。注意它**包含**无日期的
 *   下一步 action/project——这点与页面一致，也与「只算超期+今天」的直觉不同。
 * - calendar「未来 7 天排程」= 与日历默认渲染的集合一致：
 *   `visibleItems(scheduledItemsInRange(ws, today, today+6))`，即 [今天, 今天+6] 与 gantt
 *   起止区间有交集的条目，**含已完成（done）、不含已放弃（dropped）**（共 7 个自然日）。
 * - okr「当前周期目标」= 当前 ui.okrPeriod 下的 objective 数。切季度时徽标跟着变，避免
 *   「有数但点进去是空的」。
 * - gtd「收件箱待澄清」= status === 'inbox' 的条目数，即还没过澄清这一步的量。
 * - gantt「时间轴未完成」= 在时间轴上有区间（itemRange 非 null）、可出现在甘特视图
 *   （isGanttableItem）、且未完成/未放弃的条目。这是「甘特上还有多少条活要排」。
 * - sop「SOP 数量」= kind === 'sop' 的条目数（SOP 本身就是流程定义，不按状态过滤）。
 * - reports「草稿」= status === 'draft' 的报告数，即还没定稿的周报/月报/季报。
 * - settings 没有徽标（见 NavRouteId）。
 *
 * 纯函数、无 React 依赖，便于单测直接喂内存 workspace。
 */
import { addDays, format } from 'date-fns';
import type { Workspace } from '../core/model';
import type { Route } from '../core/store';
import {
  countByStatus,
  dueTodayItems,
  itemsOfKind,
  nextActions,
  objectivesOfPeriod,
  overdueItems,
  scheduledItemsInRange,
} from '../core/selectors';
import { dateKey, parseDateKey } from '../core/utils';
import { isGanttableItem, itemRange } from '../modules/gantt/scale';

/** 有徽标的路由（'settings' 没有）。 */
export type NavRouteId = Exclude<Route, 'settings'>;

export interface NavCountOptions {
  /** 'YYYY-MM-DD'，与 DashboardPage 的 today 同源。 */
  today: string;
  /** 当前 OKR 周期，例如 '2026-Q1'（来自 ui.okrPeriod）。 */
  okrPeriod: string;
}

/**
 * 今日焦点：与 `modules/dashboard/today.ts` 的 `buildTodayFocus` 等长
 * （overdue ∪ dueToday ∪ 无 end 的 nextActions，按 id 去重）。
 *
 * 为什么不直接调 `buildTodayFocus(...).length`：它要为每条算 `ancestorsOf` 并做一次
 * 分组排序，而 Sidebar 常驻、每次 workspace 变化都会重算，徽标只需要长度。这里复用三个
 * 已按 workspace 记忆化的 selector，等价性论证：
 * - push 顺序与去重键（item.id）一致，所以集合相同；
 * - overdue 取 `end < today`、dueToday 取 `end === today`，二者按日期互斥；
 * - 无日期的 nextActions 因 `end` 为空，与上面两组必然不相交。
 * 因此并集大小 = 三条来源之和；仍用 Set 去重，防止将来口径放宽（如「超期含今天」）时重复计数。
 * 等价性由 `navCounts.test.ts` 里「与 buildTodayFocus 等长」的用例守住（含种子数据）。
 */
function todayFocusCount(ws: Workspace, today: string): number {
  const ids = new Set<string>();
  for (const item of overdueItems(ws, today)) ids.add(item.id);
  for (const item of dueTodayItems(ws, today)) ids.add(item.id);
  for (const item of nextActions(ws)) {
    // 有截止日期的下一步已归入超期/今天，或属于未来排期，不进入「无日期」桶。
    if (dateKey(item.gantt?.end)) continue;
    ids.add(item.id);
  }
  return ids.size;
}

/**
 * 未来 7 天（含今天）的排程条目数，与日历默认渲染集合同源。
 *
 * 日历页渲染的是 `visibleItems(scheduledItemsInRange(ws, from, to))`（见 CalendarPage.tsx），
 * 即**含 done、不含 dropped**。
 *
 * 这里没有直接 import `modules/calendar/calendarLogic` 的 `visibleItems`——那个模块会连带把
 * 农历/节气引擎拉进首屏入口 chunk（实测 entry 106.31→116.54 kB / gzip 35.99→40.58，
 * CalendarPage chunk 24.04→14.35 kB），与 ARCHITECTURE.md 记录的首屏分包边界冲突。
 * 因此内联同一谓词（只过滤 dropped），并由 navCounts.test.ts 用真实的 `visibleItems(...)`
 * 结果做等长断言——口径一旦漂移会被测试抓到。
 */
function nextWeekScheduleCount(ws: Workspace, today: string): number {
  const start = parseDateKey(today);
  if (!start) return 0;
  const end = format(addDays(start, 6), 'yyyy-MM-dd');
  return scheduledItemsInRange(ws, today, end).filter((item) => item.status !== 'dropped').length;
}

/** 甘特上仍有区间、且未完成/未放弃的条目数。 */
function ganttOpenCount(ws: Workspace): number {
  let count = 0;
  for (const item of ws.items) {
    if (!isGanttableItem(item)) continue;
    if (item.status === 'done' || item.status === 'dropped') continue;
    if (itemRange(item) === null) continue;
    count += 1;
  }
  return count;
}

/** 所有有徽标路由的计数。键齐全，调用方可以直接下标取值。 */
export function routeCounts(ws: Workspace, opts: NavCountOptions): Record<NavRouteId, number> {
  const today = opts.today;
  return {
    dashboard: todayFocusCount(ws, today),
    calendar: nextWeekScheduleCount(ws, today),
    okr: objectivesOfPeriod(ws, opts.okrPeriod).length,
    gtd: countByStatus(ws).inbox,
    gantt: ganttOpenCount(ws),
    sop: itemsOfKind(ws, 'sop').length,
    reports: (ws.reports ?? []).filter((report) => report.status === 'draft').length,
  };
}
