/**
 * 左栏：期次列表 + 搜索。
 *
 * 只做展示与回调：排序 / 过滤在页面层用 useMemo 一次算好，
 * 这里仅把每行需要的派生文案（期次标题、字数、是否显示自定义标题）预先摊平成 view model。
 */
import { useMemo } from 'react';
import clsx from 'clsx';
import type { Report, ReportPeriodKind } from '../../core/model';
import { REPORT_STATUS_LABELS } from '../../core/model';
import { Badge } from '../../ui/Badge';
import { EmptyState } from '../../ui/EmptyState';
import { TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { periodLabel } from './period';
import { REPORT_KIND_LABELS, wordCount } from './reportView';

export interface ReportIndexProps {
  /** 已按「期次倒序 + 搜索过滤」排好的列表。 */
  reports: Report[];
  kind: ReportPeriodKind;
  selectedId: string | null;
  query: string;
  /** 该粒度下的报告总数（区分「本粒度还没有报告」与「搜索没命中」）。 */
  totalCount: number;
  onQueryChange: (value: string) => void;
  onSelect: (report: Report) => void;
}

interface IndexRow {
  report: Report;
  periodText: string;
  /** 自定义标题（与默认「2026 年第 44 周报」相同则不重复展示）。 */
  customTitle: string | null;
  words: number;
}

export function ReportIndex({
  reports,
  kind,
  selectedId,
  query,
  totalCount,
  onQueryChange,
  onSelect,
}: ReportIndexProps) {
  const rows = useMemo<IndexRow[]>(
    () =>
      reports.map((report) => {
        const periodText = periodLabel(report.kind, report.period) || report.period;
        const fallback = `${periodText}报`;
        return {
          report,
          periodText,
          customTitle:
            report.title.trim() && report.title.trim() !== fallback ? report.title.trim() : null,
          words: wordCount(report),
        };
      }),
    [reports],
  );

  const searching = query.trim().length > 0;

  return (
    <section className="reports-index" aria-label="报告期次列表">
      <div className="reports-index-head">
        <span>{REPORT_KIND_LABELS[kind]}期次</span>
        <span className="reports-index-count">{totalCount} 份</span>
      </div>

      <div className="reports-index-search">
        <Icon name="search" size={14} />
        <TextInput
          value={query}
          onChange={(event) => onQueryChange(event.target.value)}
          placeholder="搜索期次 / 标题 / 正文"
          aria-label="搜索报告"
          spellCheck={false}
        />
      </div>

      {rows.length === 0 ? (
        <EmptyState
          compact
          title={totalCount === 0 ? '还没有报告' : '没有匹配的报告'}
          description={
            totalCount === 0
              ? '选好期次后点「生成本期草稿」。'
              : '换个关键词，或清空搜索框。'
          }
        />
      ) : (
        <ul className="reports-index-list">
          {rows.map((row) => {
            const active = row.report.id === selectedId;
            return (
              <li key={row.report.id}>
                <button
                  type="button"
                  className={clsx('reports-index-item', active && 'is-active')}
                  aria-current={active ? 'true' : undefined}
                  onClick={() => onSelect(row.report)}
                >
                  <span className="reports-index-row">
                    <span className="reports-index-period">{row.periodText}</span>
                    <Badge tone={row.report.status === 'final' ? 'ok' : 'warn'}>
                      {REPORT_STATUS_LABELS[row.report.status]}
                    </Badge>
                  </span>
                  {row.customTitle ? (
                    <span className="reports-index-title">{row.customTitle}</span>
                  ) : null}
                  <span className="reports-index-words">{row.words} 字</span>
                </button>
              </li>
            );
          })}
        </ul>
      )}

      {searching && rows.length > 0 ? (
        <p className="reports-index-hint">命中 {rows.length} 份</p>
      ) : null}
    </section>
  );
}
