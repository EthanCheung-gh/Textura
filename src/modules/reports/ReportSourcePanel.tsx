/**
 * 右栏：本期的数据源。
 *
 * 顶部是 `collectFactsDetailed` 的统计口径，下面按 `fact.kind` 分组列出可直接插入的素材行。
 * 面板本身不写 store：点「插入」只回调 `onInsert(fact)`，
 * 由页面层决定插到哪一节（completed→进 展、risk→风险 …）并落盘。
 */
import { useMemo } from 'react';
import type { ReportPeriodKind } from '../../core/model';
import type { FactKind, ReportFact, ReportFactsDetailed } from './facts';
import { Progress } from '../../ui/Progress';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { formatDateKey } from '../../core/utils';

const PERIOD_WORD: Record<ReportPeriodKind, string> = {
  week: '本周',
  month: '本月',
  quarter: '本季',
};

interface FactGroup {
  kind: FactKind;
  label: string;
  facts: ReportFact[];
}

export interface ReportSourcePanelProps {
  /** 期次非法或尚未就绪时为 null。 */
  facts: ReportFactsDetailed | null;
  /** 定稿后禁止插入（内容已冻结）。 */
  disabled: boolean;
  onInsert: (fact: ReportFact) => void;
}

export function ReportSourcePanel({ facts, disabled, onInsert }: ReportSourcePanelProps) {
  const groups = useMemo<FactGroup[]>(() => {
    if (!facts) return [];
    const word = PERIOD_WORD[facts.period.kind];
    const buckets: { kind: FactKind; label: string }[] = [
      { kind: 'completed', label: `${word}完成` },
      { kind: 'risk', label: '风险与阻塞' },
      { kind: 'kr', label: '关键结果' },
      { kind: 'run', label: `${word}运行` },
      { kind: 'nextUp', label: '下期计划' },
    ];
    return buckets.map((bucket) => ({
      ...bucket,
      facts: facts.facts.filter((fact) => fact.kind === bucket.kind),
    }));
  }, [facts]);

  if (!facts) {
    return (
      <aside className="reports-source" aria-label="数据源">
        <EmptyState compact title="本期数据不可用" description="换一个合法期次再看。" />
      </aside>
    );
  }

  const { stats, period } = facts;

  return (
    <aside className="reports-source" aria-label="数据源">
      <div className="reports-source-head">
        <h2 className="reports-source-title">数据源</h2>
        <span className="reports-source-range">
          {formatDateKey(period.start, 'MM/dd')} – {formatDateKey(period.end, 'MM/dd')}
        </span>
      </div>

      <dl className="reports-stats">
        <div className="reports-stat">
          <dt>完成</dt>
          <dd>{stats.completed}</dd>
        </div>
        <div className="reports-stat">
          <dt>进行中</dt>
          <dd>{stats.openInWindow}</dd>
        </div>
        <div className="reports-stat">
          <dt>风险</dt>
          <dd>{stats.risks}</dd>
        </div>
        <div className="reports-stat">
          <dt>运行</dt>
          <dd>{stats.runs}</dd>
        </div>
      </dl>

      <div className="reports-inbox">
        <div className="reports-inbox-row">
          <span>收件箱清理</span>
          <span className="reports-inbox-value">
            剩余 {stats.inboxRemaining} 项 · {stats.inboxProgress}%
          </span>
        </div>
        <Progress value={stats.inboxProgress} size="sm" ariaLabel="收件箱清理进度" />
      </div>

      <div className="reports-facts">
        {groups.map((group) => (
          <section className="reports-fact-group" key={group.kind}>
            <h3 className="reports-fact-head">
              {group.label}
              <span className="reports-fact-count">{group.facts.length}</span>
            </h3>
            {group.facts.length === 0 ? (
              <p className="reports-fact-empty">无</p>
            ) : (
              <ul className="reports-fact-list">
                {group.facts.map((fact) => (
                  <li className="reports-fact" key={`${fact.kind}-${fact.id}`}>
                    <div className="reports-fact-text">
                      <span className="reports-fact-title" title={fact.title}>
                        {fact.title}
                      </span>
                      <span className="reports-fact-meta">{fact.meta}</span>
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled={disabled}
                      onClick={() => onInsert(fact)}
                      title={`插入到报告：${fact.line}`}
                      aria-label={`插入「${fact.title}」到报告`}
                    >
                      插入
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </section>
        ))}
      </div>
    </aside>
  );
}
