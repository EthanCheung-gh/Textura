/** 右栏底部：该 SOP 最近 20 条运行记录（只读；契约没有清空历史的动作）。 */
import { useMemo } from 'react';
import { useWorkspace } from '../../core/store';
import { formatDateTime } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import type { BadgeTone } from '../../ui/Badge';

const RESULT_META: Record<string, { tone: BadgeTone; label: string }> = {
  pass: { tone: 'ok', label: '通过' },
  fail: { tone: 'danger', label: '未通过' },
  skip: { tone: 'warn', label: '跳过' },
};

export interface RunHistoryProps {
  sopId: string;
}

export function RunHistory({ sopId }: RunHistoryProps) {
  const workspace = useWorkspace((state) => state.workspace);

  const runs = useMemo(
    () =>
      workspace.runs
        .filter((run) => run.sopId === sopId)
        .sort((a, b) => b.at.localeCompare(a.at))
        .slice(0, 20),
    [sopId, workspace.runs],
  );

  const titles = useMemo(() => {
    const map = new Map<string, string>();
    for (const item of workspace.items) map.set(item.id, item.title);
    return map;
  }, [workspace.items]);

  return (
    <section className="sop-history" aria-label="运行历史">
      <div className="sop-history-head">
        <span className="sop-section-label">运行历史</span>
        <span className="sop-history-count">最近 {runs.length} / 20</span>
      </div>
      {runs.length === 0 ? (
        <p className="sop-hint">还没有运行记录。</p>
      ) : (
        <ul className="sop-history-list">
          {runs.map((run) => {
            const meta = RESULT_META[run.result] ?? RESULT_META.skip;
            return (
              <li key={run.id} className="sop-history-item">
                <span className="sop-history-time">{formatDateTime(run.at)}</span>
                <span className="sop-history-step">{titles.get(run.stepId) ?? '已删除步骤'}</span>
                <Badge tone={meta.tone}>{meta.label}</Badge>
                {run.note ? <span className="sop-history-note">{run.note}</span> : null}
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
