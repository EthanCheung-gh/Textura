import { Fragment, memo, useCallback, useMemo, useState } from 'react';
import clsx from 'clsx';
import type { Item, Workspace } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { areaById, rollupProgress } from '../../core/selectors';
import { Badge } from '../../ui/Badge';
import { Icon } from '../../ui/icons';
import { Progress } from '../../ui/Progress';
import { ExecutionItemList } from './ExecutionItemList';
import { MetricEditor } from './MetricEditor';
import {
  OKR_KR_PAGE_SIZE,
  confidenceBucket,
  executionItemsOf,
  isKrBehind,
  nextOkrPage,
  paginateObjectiveKrs,
  resolveOkrPageLimit,
} from './okrMath';
import type { ExecutionItemRef, ObjectiveView, OkrPaginationState } from './okrMath';
import { formatMetric, progressTone, statusTone } from './okrDisplay';

interface OkrTableProps {
  workspace: Workspace;
  entries: ObjectiveView[];
  elapsedPercent: number;
  /** 季度 + 搜索词；变化时表格回到第一页。 */
  resetKey: string;
}

const BUCKET_TONE = { low: 'danger', mid: 'warn', high: 'ok' } as const;
const BUCKET_LABEL = { low: '低', mid: '中', high: '高' } as const;

/** 季度复盘表格：目标 / KR / 指标 / 当前进度 / 信心 / 执行项数，KR 行可展开。 */
export function OkrTable({ workspace, entries, elapsedPercent, resetKey }: OkrTableProps) {
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set());
  const [expandedKrs, setExpandedKrs] = useState<Set<string>>(() => new Set());
  const [page, setPage] = useState<OkrPaginationState>({
    key: resetKey,
    limit: OKR_KR_PAGE_SIZE,
  });
  // 季度 / 搜索变化时同步重置分页（派生 state）。
  if (page.key !== resetKey) setPage({ key: resetKey, limit: OKR_KR_PAGE_SIZE });

  const limit = resolveOkrPageLimit(page, resetKey);
  const pageData = useMemo(() => paginateObjectiveKrs(entries, limit), [entries, limit]);
  // 分页后仍用完整 KR 数展示目标标题（本页只渲染其中一部分）。
  const fullKrCounts = useMemo(
    () => new Map(entries.map((entry) => [entry.objective.id, entry.keyResults.length])),
    [entries],
  );

  const toggleObjective = useCallback((id: string) => {
    setCollapsed((previous) => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const toggleKr = useCallback((id: string) => {
    setExpandedKrs((previous) => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const showMore = useCallback(() => {
    setPage((current) => nextOkrPage(current, resetKey));
  }, [resetKey]);

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
          {pageData.entries.map(({ objective, keyResults }) => {
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
                        {fullKrCounts.get(objective.id) ?? keyResults.length} KR · 信心 {confidence}
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
                      const progress = rollupProgress(workspace, kr.id);
                      return (
                        <KrTableRow
                          key={kr.id}
                          kr={kr}
                          objectiveTitle={objective.title}
                          progress={progress}
                          behind={isKrBehind(progress, elapsedPercent)}
                          executionItems={executionItemsOf(workspace, kr.id)}
                          expanded={expandedKrs.has(kr.id)}
                          elapsedPercent={elapsedPercent}
                          onToggle={toggleKr}
                        />
                      );
                    })}
              </Fragment>
            );
          })}
          {pageData.hasMore ? (
            <tr className="okr-table-show-more">
              <td colSpan={6}>
                <button type="button" className="okr-show-more-btn" onClick={showMore}>
                  显示更多（剩余 {pageData.remaining} 条 KR）
                </button>
                <span className="okr-table-show-more-note">
                  已显示 {pageData.shownKeyResults} / {pageData.totalKeyResults} 条 KR
                </span>
              </td>
            </tr>
          ) : null}
        </tbody>
      </table>
    </div>
  );
}

interface KrTableRowProps {
  kr: Item;
  objectiveTitle: string;
  progress: number;
  behind: boolean;
  executionItems: ExecutionItemRef[];
  expanded: boolean;
  elapsedPercent: number;
  onToggle: (id: string) => void;
}

/**
 * 表格里的单条 KR。props 都是原始值或内容稳定的数组，
 * 展开 / 编辑其他行时其余 KR 行不会重渲染。
 */
const KrTableRow = memo(function KrTableRow({
  kr,
  objectiveTitle,
  progress,
  behind,
  executionItems,
  expanded,
  elapsedPercent,
  onToggle,
}: KrTableRowProps) {
  const noGrip = !kr.okr?.metric && executionItems.length === 0;
  const bucket = confidenceBucket(kr.okr?.confidence ?? 5);
  return (
    <Fragment>
      <tr className={clsx('okr-table-kr', expanded && 'is-expanded')}>
        <td className="okr-table-objname">{objectiveTitle}</td>
        <td>
          <div className="okr-table-kr-cell">
            <button
              type="button"
              className="okr-table-kr-btn"
              aria-expanded={expanded}
              aria-label={`${expanded ? '收起' : '展开'}「${kr.title}」详情`}
              onClick={() => onToggle(kr.id)}
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
              value={progress}
              tone={progressTone(progress, behind)}
              size="sm"
              ariaLabel={`${kr.title} 进度`}
            />
            <span className="mono">{progress}%</span>
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
                <Badge tone={statusTone(kr.status)}>{STATUS_LABELS[kr.status]}</Badge>
                <span>负责人：{kr.okr?.krOwner || '未指派'}</span>
                <span>信心：{kr.okr?.confidence ?? 5}/10</span>
                <span className={clsx('okr-kr-pace', behind && 'is-behind')}>
                  {behind
                    ? `落后时间进度 ${Math.round(elapsedPercent - progress)} 个点`
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
});
