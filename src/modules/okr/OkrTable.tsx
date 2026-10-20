import { Fragment, useState } from 'react';
import clsx from 'clsx';
import type { Workspace } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { areaById, rollupProgress } from '../../core/selectors';
import { Badge } from '../../ui/Badge';
import { Icon } from '../../ui/icons';
import { Progress } from '../../ui/Progress';
import { ExecutionItemList } from './ExecutionItemList';
import { MetricEditor } from './MetricEditor';
import { confidenceBucket, executionItemsOf, isKrBehind } from './okrMath';
import type { ObjectiveView } from './okrMath';
import { formatMetric, progressTone, statusTone } from './okrDisplay';

interface OkrTableProps {
  workspace: Workspace;
  entries: ObjectiveView[];
  elapsedPercent: number;
}

const BUCKET_TONE = { low: 'danger', mid: 'warn', high: 'ok' } as const;
const BUCKET_LABEL = { low: '低', mid: '中', high: '高' } as const;

/** 季度复盘表格：目标 / KR / 指标 / 当前进度 / 信心 / 执行项数，KR 行可展开。 */
export function OkrTable({ workspace, entries, elapsedPercent }: OkrTableProps) {
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set());
  const [expandedKrs, setExpandedKrs] = useState<Set<string>>(() => new Set());

  const toggleObjective = (id: string) => {
    setCollapsed((previous) => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleKr = (id: string) => {
    setExpandedKrs((previous) => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  return (
    <div className="okr-table-wrap">
      <table className="okr-table">
        <caption className="sr-only">季度 OKR 复盘表</caption>
        <thead>
          <tr>
            <th scope="col">目标</th>
            <th scope="col">关键结果</th>
            <th scope="col">指标</th>
            <th scope="col">当前进度</th>
            <th scope="col">信心</th>
            <th scope="col">执行项</th>
          </tr>
        </thead>
        <tbody>
          {entries.map(({ objective, keyResults }) => {
            const progress = rollupProgress(workspace, objective.id);
            const area = objective.areaId ? areaById(workspace, objective.areaId) : undefined;
            const confidence = objective.okr?.confidence ?? 5;
            const isCollapsed = collapsed.has(objective.id);
            return (
              <Fragment key={objective.id}>
                <tr className="okr-table-objective">
                  <td colSpan={6}>
                    <div className="okr-table-obj">
                      <button
                        type="button"
                        className={clsx('okr-table-toggle', isCollapsed && 'is-collapsed')}
                        aria-expanded={!isCollapsed}
                        aria-label={`${isCollapsed ? '展开' : '收起'}「${objective.title}」`}
                        onClick={() => toggleObjective(objective.id)}
                      >
                        <Icon name="chevron-down" size={15} />
                      </button>
                      {area ? (
                        <span
                          className="okr-area-dot"
                          style={{ backgroundColor: area.color }}
                          aria-hidden="true"
                        />
                      ) : null}
                      <span className="okr-table-obj-title">{objective.title}</span>
                      <Badge tone={statusTone(objective.status)}>
                        {STATUS_LABELS[objective.status]}
                      </Badge>
                      <span className="okr-table-obj-meta">
                        {keyResults.length} KR · 信心 {confidence}
                      </span>
                      <span className="okr-table-spacer" />
                      <div className="okr-table-progress">
                        <Progress
                          value={progress}
                          tone={progressTone(progress, false)}
                          size="sm"
                          ariaLabel={`${objective.title} 整体进度`}
                        />
                        <span className="mono">{progress}%</span>
                      </div>
                    </div>
                  </td>
                </tr>
                {isCollapsed
                  ? null
                  : keyResults.map((kr) => {
                      const krProgress = rollupProgress(workspace, kr.id);
                      const behind = isKrBehind(krProgress, elapsedPercent);
                      const executionItems = executionItemsOf(workspace, kr.id);
                      const noGrip = !kr.okr?.metric && executionItems.length === 0;
                      const expanded = expandedKrs.has(kr.id);
                      const bucket = confidenceBucket(kr.okr?.confidence ?? 5);
                      return (
                        <Fragment key={kr.id}>
                          <tr className={clsx('okr-table-kr', expanded && 'is-expanded')}>
                            <td className="okr-table-objname">{objective.title}</td>
                            <td>
                              <div className="okr-table-kr-cell">
                                <button
                                  type="button"
                                  className="okr-table-kr-btn"
                                  aria-expanded={expanded}
                                  aria-label={`${expanded ? '收起' : '展开'}「${kr.title}」详情`}
                                  onClick={() => toggleKr(kr.id)}
                                >
                                  <Icon name={expanded ? 'chevron-down' : 'chevron-right'} size={13} />
                                  <span>{kr.title}</span>
                                </button>
                                {behind ? (
                                  <Badge tone="danger" dot className="okr-behind-badge">
                                    落后
                                  </Badge>
                                ) : null}
                                {noGrip ? (
                                  <Badge tone="warn" dot>
                                    缺少抓手
                                  </Badge>
                                ) : null}
                              </div>
                            </td>
                            <td className="okr-table-metric mono">{formatMetric(kr.okr?.metric)}</td>
                            <td>
                              <div className="okr-table-progress">
                                <Progress
                                  value={krProgress}
                                  tone={progressTone(krProgress, behind)}
                                  size="sm"
                                  ariaLabel={`${kr.title} 进度`}
                                />
                                <span className="mono">{krProgress}%</span>
                              </div>
                            </td>
                            <td>
                              <Badge tone={BUCKET_TONE[bucket]} dot>
                                {kr.okr?.confidence ?? 5} · {BUCKET_LABEL[bucket]}
                              </Badge>
                            </td>
                            <td>
                              <span className="okr-count-pill mono">{executionItems.length}</span>
                            </td>
                          </tr>
                          {expanded ? (
                            <tr className="okr-table-detail">
                              <td colSpan={6}>
                                <div className="okr-table-detail-inner">
                                  <MetricEditor kr={kr} />
                                  <div className="okr-table-detail-meta">
                                    <Badge tone={statusTone(kr.status)}>
                                      {STATUS_LABELS[kr.status]}
                                    </Badge>
                                    <span>负责人：{kr.okr?.krOwner || '未指派'}</span>
                                    <span>信心：{kr.okr?.confidence ?? 5}/10</span>
                                    <span className={clsx('okr-kr-pace', behind && 'is-behind')}>
                                      {behind
                                        ? `落后时间进度 ${Math.round(elapsedPercent - krProgress)} 个点`
                                        : '进度不落后于时间进度'}
                                    </span>
                                  </div>
                                  <ExecutionItemList krTitle={kr.title} items={executionItems} />
                                </div>
                              </td>
                            </tr>
                          ) : null}
                        </Fragment>
                      );
                    })}
              </Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
