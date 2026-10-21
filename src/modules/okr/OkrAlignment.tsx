import { useCallback, useMemo } from 'react';
import type { Item, Workspace } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { areaById, rollupProgress } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { Badge } from '../../ui/Badge';
import { Icon } from '../../ui/icons';
import { Progress } from '../../ui/Progress';
import {
  buildParentPathText,
  confidenceBucket,
  executionItemsOf,
  isKrBehind,
} from './okrMath';
import type { ObjectiveView } from './okrMath';
import { formatMetric, formatSchedule, progressTone, statusTone } from './okrDisplay';

interface OkrAlignmentProps {
  workspace: Workspace;
  entries: ObjectiveView[];
  elapsedPercent: number;
  period: string;
}

const BUCKET_TONE = { low: 'danger', mid: 'warn', high: 'ok' } as const;

/** 目标 → KR → 执行项 的三层只读大纲；点击跳转到对应视图。 */
export function OkrAlignment({ workspace, entries, elapsedPercent, period }: OkrAlignmentProps) {
  const setUi = useWorkspace((state) => state.setUi);
  const select = useWorkspace((state) => state.select);

  const openItem = useCallback(
    (item: Item) => {
      select(item.id);
      if (item.kind === 'objective' || item.kind === 'keyresult') {
        setUi({ route: 'okr', okrPeriod: period });
      } else {
        setUi({ route: item.gantt ? 'gantt' : 'gtd' });
      }
    },
    [period, select, setUi],
  );

  // 列表级一次计算：进度 / 落后判定 / 执行项数组（内容不变时引用稳定）。
  const rows = useMemo(
    () =>
      entries.map(({ objective, keyResults }) => ({
        objective,
        progress: rollupProgress(workspace, objective.id),
        area: objective.areaId ? areaById(workspace, objective.areaId) : undefined,
        keyResults: keyResults.map((kr) => {
          const progress = rollupProgress(workspace, kr.id);
          return {
            kr,
            progress,
            behind: isKrBehind(progress, elapsedPercent),
            executionItems: executionItemsOf(workspace, kr.id),
          };
        }),
      })),
    [workspace, entries, elapsedPercent],
  );

  // 面包屑路径 Map：行内只做 O(1) 查找，不再逐条调用 itemPathTitles。
  const pathText = useMemo(
    () =>
      buildParentPathText(
        workspace,
        rows.flatMap((row) =>
          row.keyResults.flatMap((kr) => kr.executionItems.map((entry) => entry.item)),
        ),
      ),
    [workspace, rows],
  );

  return (
    <div className="okr-align">
      {rows.map(({ objective, progress: objectiveProgress, area, keyResults }) => (
        <section key={objective.id} className="okr-align-objective">
          <div className="okr-align-row okr-align-row--objective">
            <button
              type="button"
              className="okr-align-btn"
              onClick={() => openItem(objective)}
              title="回到卡片视图"
            >
              <Icon name="target" size={15} />
              <span className="okr-align-title">{objective.title}</span>
            </button>
            <span className="okr-align-meta">
              {area ? (
                <span className="okr-area">
                  <span
                    className="okr-area-dot"
                    style={{ backgroundColor: area.color }}
                    aria-hidden="true"
                  />
                  {area.name}
                </span>
              ) : null}
              <Badge tone={statusTone(objective.status)}>{STATUS_LABELS[objective.status]}</Badge>
              <Badge tone="neutral">O · {objectiveProgress}%</Badge>
              <Badge tone={BUCKET_TONE[confidenceBucket(objective.okr?.confidence ?? 5)]}>
                信心 {objective.okr?.confidence ?? 5}
              </Badge>
            </span>
          </div>

          {keyResults.length === 0 ? (
            <p className="okr-align-empty">没有关键结果 · 这个目标缺少可量化的支撑。</p>
          ) : (
            <ul className="okr-align-krs">
              {keyResults.map(({ kr, progress, behind, executionItems }) => (
                <li key={kr.id} className="okr-align-kr">
                  <div className="okr-align-row">
                    <button
                      type="button"
                      className="okr-align-btn"
                      onClick={() => openItem(kr)}
                      title="回到卡片视图"
                    >
                      <Icon name="flag" size={14} />
                      <span className="okr-align-title">{kr.title}</span>
                    </button>
                    <span className="okr-align-meta">
                      <span className="okr-align-metric mono">{formatMetric(kr.okr?.metric)}</span>
                      <span className="okr-align-progress">
                        <Progress
                          value={progress}
                          tone={progressTone(progress, behind)}
                          size="sm"
                          ariaLabel={`${kr.title} 进度`}
                        />
                        <span className="mono">{progress}%</span>
                      </span>
                      <Badge
                        tone={BUCKET_TONE[confidenceBucket(kr.okr?.confidence ?? 5)]}
                        dot
                      >
                        {kr.okr?.confidence ?? 5}
                      </Badge>
                      {behind ? (
                        <Badge tone="danger" dot className="okr-behind-badge">
                          落后
                        </Badge>
                      ) : null}
                      {!kr.okr?.metric && executionItems.length === 0 ? (
                        <Badge tone="warn" dot>
                          缺少抓手
                        </Badge>
                      ) : null}
                    </span>
                  </div>

                  {executionItems.length === 0 ? (
                    <p className="okr-align-empty">没有关联执行项。</p>
                  ) : (
                    <ul className="okr-align-execs">
                      {executionItems.map(({ item, via }) => {
                        const itemProgress =
                          item.status === 'done' ? 100 : (item.gantt?.progress ?? 0);
                        const breadcrumb = pathText.get(item.id) ?? '';
                        return (
                          <li key={item.id}>
                            <button
                              type="button"
                              className="okr-align-exec-btn"
                              onClick={() => openItem(item)}
                              title={item.gantt ? '在甘特中查看' : '在 GTD 中查看'}
                            >
                              <Icon
                                name={item.kind === 'project' ? 'folder' : 'check'}
                                size={13}
                              />
                              <span className="okr-align-exec-title">{item.title}</span>
                              {breadcrumb ? (
                                <span className="okr-align-exec-path" title={breadcrumb}>
                                  {breadcrumb}
                                </span>
                              ) : null}
                              <Badge tone={statusTone(item.status)}>
                                {STATUS_LABELS[item.status]}
                              </Badge>
                              <span className="okr-align-exec-date mono">
                                {formatSchedule(item)}
                              </span>
                              <span className="okr-align-exec-progress mono">{itemProgress}%</span>
                              {via === 'child' ? <Badge tone="neutral">子项</Badge> : null}
                              <Icon name="chevron-right" size={12} />
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      ))}
    </div>
  );
}
