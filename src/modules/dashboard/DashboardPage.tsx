import { useMemo } from 'react';
import { format } from 'date-fns';
import { zhCN } from 'date-fns/locale';
import {
  inboxItems,
  itemsOfKind,
  objectivesOfPeriod,
  rollupProgress,
  sopGraph,
} from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { Progress } from '../../ui/Progress';
import { routeForItemKind } from '../appshell/navigation';
import { ActivityFeed } from './ActivityFeed';
import { FocusList } from './FocusList';
import { StatCards } from './StatCards';
import type { StatCard } from './StatCards';
import type { FocusEntry } from './today';
import {
  buildActivity,
  buildTodayFocus,
  completedThisWeek,
  countFocusBuckets,
  latestRun,
  latestRunFor,
  relativeTime,
  RUN_RESULT_LABELS,
  summarizeToday,
} from './today';
import './dashboard.css';

function greetingFor(hour: number): string {
  if (hour < 5) return '夜深了';
  if (hour < 11) return '早上好';
  if (hour < 13) return '中午好';
  if (hour < 18) return '下午好';
  return '晚上好';
}

export function DashboardPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const ui = useWorkspace((state) => state.ui);
  const setUi = useWorkspace((state) => state.setUi);
  const select = useWorkspace((state) => state.select);
  const createItem = useWorkspace((state) => state.createItem);
  const toggleDone = useWorkspace((state) => state.toggleDone);
  const notify = useWorkspace((state) => state.notify);

  const now = new Date();
  const today = format(now, 'yyyy-MM-dd');
  const isEmpty = workspace.items.length === 0 && workspace.runs.length === 0;

  const focus = useMemo(() => buildTodayFocus(workspace, today), [workspace, today]);
  const counts = countFocusBuckets(focus);
  const inbox = useMemo(() => inboxItems(workspace), [workspace]);
  const completed = useMemo(() => completedThisWeek(workspace, now), [workspace, today]);
  const objectives = useMemo(
    () =>
      objectivesOfPeriod(workspace, ui.okrPeriod).map((objective) => ({
        objective,
        progress: rollupProgress(workspace, objective.id),
      })),
    [workspace, ui.okrPeriod],
  );
  const okrAverage =
    objectives.length > 0
      ? Math.round(
          objectives.reduce((sum, entry) => sum + entry.progress, 0) / objectives.length,
        )
      : 0;
  const sops = useMemo(
    () =>
      itemsOfKind(workspace, 'sop')
        .slice(0, 4)
        .map((sop) => ({
          sop,
          steps: sopGraph(workspace, sop.id).nodes.length,
          lastRun: latestRunFor(workspace, sop.id),
        })),
    [workspace],
  );
  const newestRun = latestRun(workspace);
  const newestRunSop = newestRun
    ? (workspace.items.find((item) => item.id === newestRun.sopId) ?? null)
    : null;
  const activity = useMemo(() => buildActivity(workspace, 5), [workspace, today]);

  const summary = summarizeToday({
    overdue: counts.overdue,
    today: counts.today,
    inbox: inbox.length,
    next: counts.undated,
  });

  const openEntry = (entry: FocusEntry) => {
    select(entry.item.id);
    const period = entry.item.okr?.period;
    setUi({
      route: routeForItemKind(entry.item.kind),
      ...(period ? { okrPeriod: period } : {}),
    });
  };

  const createObjective = () => {
    const item = createItem({
      kind: 'objective',
      title: '第一个目标',
      status: 'active',
      okr: { period: ui.okrPeriod },
    });
    select(item.id);
    setUi({ route: 'okr', okrPeriod: ui.okrPeriod });
    notify('目标已创建，接着添加关键结果吧', 'success');
  };

  const createSop = () => {
    const item = createItem({ kind: 'sop', title: '第一个 SOP', status: 'active' });
    select(item.id);
    setUi({ route: 'sop' });
    notify('SOP 已创建，去画布上添加步骤吧', 'success');
  };

  const cards: StatCard[] = [
    {
      id: 'inbox',
      label: '收件箱待澄清',
      value: String(inbox.length),
      unit: '条',
      meta: inbox.length > 0 ? '先澄清，再决定下一步' : '收件箱已清空',
      icon: 'inbox',
      tone: inbox.length > 0 ? 'accent' : 'ok',
      ariaLabel: `收件箱 ${inbox.length} 条待澄清，打开 GTD 视图`,
      onClick: () => setUi({ route: 'gtd' }),
    },
    {
      id: 'completed',
      label: '近 7 天完成',
      value: String(completed.length),
      unit: '项',
      meta: '按 completedAt 的近 7 天滚动窗口',
      icon: 'check',
      tone: 'ok',
      ariaLabel: `近 7 天完成 ${completed.length} 项，打开 GTD 视图`,
      onClick: () => setUi({ route: 'gtd' }),
    },
    {
      id: 'okr',
      label: '活跃 OKR 平均进度',
      value: String(okrAverage),
      unit: '%',
      meta: `${objectives.length} 个目标 · ${ui.okrPeriod}`,
      icon: 'target',
      tone: 'info',
      ariaLabel: `当前季度 OKR 平均进度 ${okrAverage}%，打开 OKR 视图`,
      onClick: () => setUi({ route: 'okr' }),
    },
    {
      id: 'run',
      label: '最近 SOP 运行',
      value: newestRun ? RUN_RESULT_LABELS[newestRun.result] : '—',
      meta: newestRun
        ? `${newestRunSop?.title ?? '未知 SOP'} · ${relativeTime(newestRun.at)}`
        : '还没有运行记录',
      icon: 'play',
      tone: newestRun
        ? newestRun.result === 'fail'
          ? 'danger'
          : newestRun.result === 'skip'
            ? 'warn'
            : 'ok'
        : 'neutral',
      ariaLabel: newestRun
        ? `最近 SOP 运行${RUN_RESULT_LABELS[newestRun.result]}，打开 SOP 视图`
        : '还没有 SOP 运行记录，打开 SOP 视图',
      onClick: () => {
        if (newestRun) select(newestRun.sopId);
        setUi({ route: 'sop' });
      },
    },
  ];

  return (
    <div className="page dash-page">
      <div className="page-header dash-header">
        <div className="page-header-titles">
          <span className="dash-eyebrow">{format(now, 'yyyy年M月d日 EEEE', { locale: zhCN })}</span>
          <h1>{greetingFor(now.getHours())}，今天推进什么？</h1>
          <p className="dash-summary">{summary}</p>
        </div>
        <div className="page-actions">
          <Button
            size="sm"
            variant="secondary"
            iconLeft={<Icon name="search" size={14} />}
            title="⌘/Ctrl + K"
            onClick={() => setUi({ paletteOpen: true })}
          >
            命令面板
            <span className="dash-kbd">⌘K</span>
          </Button>
          <Button
            size="sm"
            variant="secondary"
            iconLeft={<Icon name="plus" size={14} />}
            onClick={() => setUi({ quickCaptureOpen: true })}
          >
            快速收集
          </Button>
        </div>
      </div>

      {isEmpty ? (
        <section className="dash-card dash-onboarding">
          <EmptyState
            icon={<Icon name="workflow" size={22} />}
            title="从第一条记录开始"
            description="工作区还是空的。先收集一条想法，或者建立第一个目标 / 流程，今日视图会自动把它们聚合起来。"
            action={
              <div className="dash-onboarding-actions">
                <Button
                  variant="primary"
                  size="sm"
                  iconLeft={<Icon name="plus" size={14} />}
                  onClick={() => setUi({ quickCaptureOpen: true })}
                >
                  收集第一条
                </Button>
                <Button
                  variant="secondary"
                  size="sm"
                  iconLeft={<Icon name="target" size={14} />}
                  onClick={createObjective}
                >
                  创建第一个目标
                </Button>
                <Button
                  variant="secondary"
                  size="sm"
                  iconLeft={<Icon name="workflow" size={14} />}
                  onClick={createSop}
                >
                  创建第一个 SOP
                </Button>
              </div>
            }
          />
        </section>
      ) : (
        <>
          <StatCards cards={cards} />

          <div className="dash-grid">
            <div className="dash-column">
              <section className="dash-card" aria-label="今日聚焦">
                <header className="dash-card-head">
                  <div>
                    <h2 className="dash-card-title">
                      <Icon name="flag" size={15} />
                      今日聚焦
                    </h2>
                    <p className="dash-card-sub">
                      {counts.overdue} 超期 · {counts.today} 今天 · {counts.undated} 无日期
                    </p>
                  </div>
                  <span className="dash-card-count">{focus.length} 项</span>
                </header>
                <FocusList entries={focus} onToggle={toggleDone} onOpen={openEntry} />
              </section>

              <section className="dash-card" aria-label="最近活动">
                <header className="dash-card-head">
                  <div>
                    <h2 className="dash-card-title">
                      <Icon name="clock" size={15} />
                      最近活动
                    </h2>
                    <p className="dash-card-sub">SOP 运行与完成记录，按时间倒序</p>
                  </div>
                </header>
                <ActivityFeed entries={activity} />
              </section>
            </div>

            <div className="dash-column">
              <section className="dash-card" aria-label="OKR 概览">
                <header className="dash-card-head">
                  <div>
                    <h2 className="dash-card-title">
                      <Icon name="target" size={15} />
                      OKR 概览
                    </h2>
                    <p className="dash-card-sub">{ui.okrPeriod} · 平均 {okrAverage}%</p>
                  </div>
                  <button
                    type="button"
                    className="dash-link"
                    onClick={() => setUi({ route: 'okr' })}
                  >
                    打开 OKR
                  </button>
                </header>
                {objectives.length === 0 ? (
                  <EmptyState
                    compact
                    icon={<Icon name="target" size={18} />}
                    title="本季度还没有目标"
                    description="在 OKR 视图里创建目标与关键结果。"
                    action={
                      <Button size="sm" variant="secondary" onClick={createObjective}>
                        新建目标
                      </Button>
                    }
                  />
                ) : (
                  <div className="dash-okr-list">
                    {objectives.map(({ objective, progress }) => (
                      <button
                        key={objective.id}
                        type="button"
                        className="dash-okr-row"
                        aria-label={`打开目标「${objective.title}」，进度 ${progress}%`}
                        onClick={() => {
                          select(objective.id);
                          setUi({ route: 'okr' });
                        }}
                      >
                        <span className="dash-okr-title">{objective.title}</span>
                        <Progress
                          value={progress}
                          size="sm"
                          tone={progress >= 70 ? 'ok' : progress >= 35 ? 'accent' : 'warn'}
                          ariaLabel={`${objective.title} 进度`}
                        />
                        <span className="dash-okr-value">{progress}%</span>
                      </button>
                    ))}
                  </div>
                )}
              </section>

              <section className="dash-card" aria-label="SOP 快速启动">
                <header className="dash-card-head">
                  <div>
                    <h2 className="dash-card-title">
                      <Icon name="workflow" size={15} />
                      SOP 快速启动
                    </h2>
                    <p className="dash-card-sub">最多显示 4 个流程</p>
                  </div>
                  <button
                    type="button"
                    className="dash-link"
                    onClick={() => setUi({ route: 'sop' })}
                  >
                    打开 SOP
                  </button>
                </header>
                {sops.length === 0 ? (
                  <EmptyState
                    compact
                    icon={<Icon name="workflow" size={18} />}
                    title="还没有 SOP"
                    description="把重复动作画成流程图，之后一键运行。"
                    action={
                      <Button size="sm" variant="secondary" onClick={createSop}>
                        新建 SOP
                      </Button>
                    }
                  />
                ) : (
                  <div className="dash-sop-list">
                    {sops.map(({ sop, steps, lastRun }) => (
                      <button
                        key={sop.id}
                        type="button"
                        className="dash-sop-row"
                        aria-label={`打开 SOP「${sop.title}」`}
                        onClick={() => {
                          select(sop.id);
                          setUi({ route: 'sop' });
                        }}
                      >
                        <span className="dash-sop-icon" aria-hidden="true">
                          <Icon name="workflow" size={15} />
                        </span>
                        <span className="dash-sop-main">
                          <span className="dash-sop-title">{sop.title}</span>
                          <span className="dash-sop-meta">
                            {steps} 个步骤
                            {lastRun
                              ? ` · 最近 ${RUN_RESULT_LABELS[lastRun.result]} ${relativeTime(lastRun.at)}`
                              : ' · 尚未运行'}
                          </span>
                        </span>
                        <Badge
                          tone={
                            lastRun
                              ? lastRun.result === 'fail'
                                ? 'danger'
                                : lastRun.result === 'skip'
                                  ? 'warn'
                                  : 'ok'
                              : 'neutral'
                          }
                        >
                          {lastRun ? RUN_RESULT_LABELS[lastRun.result] : '未运行'}
                        </Badge>
                      </button>
                    ))}
                  </div>
                )}
              </section>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
