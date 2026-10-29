import { useEffect, useRef, useState } from 'react';
import type { Item, Workspace } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { areaById, childrenOf, rollupProgress } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { currentQuarter } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/icons';
import { IconButton } from '../../ui/IconButton';
import { Progress } from '../../ui/Progress';
import { ConfidenceScale } from './ConfidenceScale';
import { ConfirmDialog } from './ConfirmDialog';
import { KrRow } from './KrRow';
import { QuarterDialog } from './QuarterDialog';
import { nextQuarter, quarterLabel } from './okrMath';
import type { OkrDensity } from './okrMath';
import { progressTone, statusTone } from './okrDisplay';

interface ObjectiveCardProps {
  workspace: Workspace;
  objective: Item;
  /** 经过搜索过滤的 KR 列表。 */
  keyResults: Item[];
  elapsedPercent: number;
  density: OkrDensity;
  /** 打开独立页面式的目标编辑视图。 */
  onEdit: (id: string) => void;
}

/**
 * 列表卡片：纯展示，不渲染任何输入控件。
 *
 * 标题、信心、KR 全部只读；新增 / 调整 KR、改标题等编辑能力只在
 * `ObjectiveEditor` 独立编辑视图里提供，避免列表态挂载成百上千个输入控件。
 */
export function ObjectiveCard({
  workspace,
  objective,
  keyResults,
  elapsedPercent,
  density,
  onEdit,
}: ObjectiveCardProps) {
  const updateItems = useWorkspace((state) => state.updateItems);
  const createItem = useWorkspace((state) => state.createItem);
  const deleteItems = useWorkspace((state) => state.deleteItems);
  const setUi = useWorkspace((state) => state.setUi);
  const select = useWorkspace((state) => state.select);
  const notify = useWorkspace((state) => state.notify);

  const [menuOpen, setMenuOpen] = useState(false);
  const [quarterMode, setQuarterMode] = useState<'move' | 'copy' | null>(null);
  const [deleteObjectiveOpen, setDeleteObjectiveOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!menuOpen) return;
    const handlePointer = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) setMenuOpen(false);
    };
    const handleKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setMenuOpen(false);
    };
    document.addEventListener('mousedown', handlePointer);
    document.addEventListener('keydown', handleKey);
    return () => {
      document.removeEventListener('mousedown', handlePointer);
      document.removeEventListener('keydown', handleKey);
    };
  }, [menuOpen]);

  const allKeyResults = childrenOf(workspace, objective.id).filter(
    (item) => item.kind === 'keyresult',
  );
  const progress = rollupProgress(workspace, objective.id);
  const area = objective.areaId ? areaById(workspace, objective.areaId) : undefined;
  const confidence = objective.okr?.confidence ?? 5;
  const period = objective.okr?.period ?? currentQuarter();
  const hiddenKrs = allKeyResults.length - keyResults.length;

  const moveObjective = (target: string) => {
    // 目标 + 全部 KR 一次提交：只产生一条历史，一次撤销即可整体回退。
    updateItems([
      { id: objective.id, patch: { okr: { period: target } } },
      ...allKeyResults.map((kr) => ({ id: kr.id, patch: { okr: { period: target } } })),
    ]);
    setQuarterMode(null);
    setUi({ okrPeriod: target });
    notify(`目标已移动到 ${quarterLabel(target)}`, 'success');
  };

  const copyObjective = (target: string) => {
    const copy = createItem({
      kind: 'objective',
      title: objective.title,
      notes: objective.notes,
      status: 'active',
      tags: [...objective.tags],
      areaId: objective.areaId,
      okr: { period: target, confidence },
    });
    for (const kr of allKeyResults) {
      createItem({
        kind: 'keyresult',
        title: kr.title,
        notes: kr.notes,
        parentId: copy.id,
        status: kr.status === 'done' ? 'active' : kr.status,
        tags: [...kr.tags],
        areaId: kr.areaId,
        okr: {
          period: target,
          confidence: kr.okr?.confidence ?? 5,
          krOwner: kr.okr?.krOwner,
          metric: kr.okr?.metric ? { ...kr.okr.metric, current: kr.okr.metric.start } : undefined,
        },
      });
    }
    setQuarterMode(null);
    setUi({ okrPeriod: target });
    select(copy.id);
    notify(`已复制为新季度目标：${quarterLabel(target)}`, 'success');
  };

  return (
    <article className="okr-objective" aria-label={`目标：${objective.title}`}>
      <header className="okr-objective-head">
        <div className="okr-objective-main">
          <div className="okr-objective-meta">
            {area ? (
              <span className="okr-area">
                <span
                  className="okr-area-dot"
                  style={{ backgroundColor: area.color }}
                  aria-hidden="true"
                />
                {area.name}
              </span>
            ) : (
              <span className="okr-area okr-area--none">未归属 Area</span>
            )}
            <Badge tone={statusTone(objective.status)}>{STATUS_LABELS[objective.status]}</Badge>
            <span className="okr-objective-count">{allKeyResults.length} 个关键结果</span>
            {allKeyResults.length === 0 ? (
              <Badge tone="warn" dot>
                缺少关键结果
              </Badge>
            ) : null}
          </div>

          <h2 className="okr-objective-title okr-objective-title--readonly">{objective.title}</h2>

          {density === 'detailed' && objective.notes ? (
            <p className="okr-objective-notes">{objective.notes}</p>
          ) : null}

          <div className="okr-objective-progress">
            <span className="okr-objective-progress-label">整体进度</span>
            <Progress
              value={progress}
              tone={progressTone(progress, false)}
              ariaLabel={`${objective.title} 整体进度`}
            />
            <span className="okr-objective-pct mono">{progress}%</span>
            <span className="okr-objective-spacer" />
            <span className="okr-confidence-prefix">信心</span>
            <ConfidenceScale value={confidence} readOnly ariaLabel={`${objective.title} 信心指数`} />
          </div>
        </div>

        <div className="okr-objective-tools" ref={menuRef}>
          <Button
            variant="ghost"
            size="sm"
            aria-label={`编辑目标：${objective.title}`}
            data-edit-objective={objective.id}
            iconLeft={<Icon name="edit" size={14} />}
            onClick={() => onEdit(objective.id)}
          >
            编辑
          </Button>
          <IconButton
            label={`「${objective.title}」更多操作`}
            size="sm"
            aria-haspopup="menu"
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen((open) => !open)}
          >
            <Icon name="more" size={16} />
          </IconButton>
          {menuOpen ? (
            <div className="okr-menu" role="menu" aria-label="目标操作">
              <button
                type="button"
                role="menuitem"
                className="okr-menu-item"
                onClick={() => {
                  setMenuOpen(false);
                  setQuarterMode('move');
                }}
              >
                <Icon name="calendar" size={14} />
                移动到其他季度
              </button>
              <button
                type="button"
                role="menuitem"
                className="okr-menu-item"
                onClick={() => {
                  setMenuOpen(false);
                  setQuarterMode('copy');
                }}
              >
                <Icon name="plus" size={14} />
                复制为新季度目标
              </button>
              <div className="okr-menu-sep" role="separator" />
              <button
                type="button"
                role="menuitem"
                className="okr-menu-item is-danger"
                onClick={() => {
                  setMenuOpen(false);
                  setDeleteObjectiveOpen(true);
                }}
              >
                <Icon name="trash" size={14} />
                删除目标
              </button>
            </div>
          ) : null}
        </div>
      </header>

      <div className="okr-kr-section">
        {allKeyResults.length === 0 ? (
          <p className="okr-kr-empty">
            还没有关键结果。用一个可量化的结果来支撑这个目标，例如「NPS 从 42 提升到 60」。
          </p>
        ) : (
          <ol className="okr-kr-list" aria-label={`${objective.title} 的关键结果`}>
            {keyResults.map((kr) => {
              const index = allKeyResults.findIndex((item) => item.id === kr.id);
              return (
                <KrRow
                  key={kr.id}
                  objective={objective}
                  kr={kr}
                  index={index}
                  count={allKeyResults.length}
                  elapsedPercent={elapsedPercent}
                  density={density}
                  readOnly
                />
              );
            })}
          </ol>
        )}

        {hiddenKrs > 0 ? (
          <p className="okr-kr-filtered">搜索隐藏了 {hiddenKrs} 条关键结果。</p>
        ) : null}

        <p className="okr-kr-add-hint">在编辑视图新增或调整关键结果</p>
      </div>

      <QuarterDialog
        open={quarterMode !== null}
        title={quarterMode === 'copy' ? '复制为新季度目标' : '移动目标到其他季度'}
        description={
          quarterMode === 'copy'
            ? '复制目标与全部 KR；KR 的当前值会重置为起点，执行项关联不会复制。'
            : '目标与它的 KR 会一起移动到新季度。'
        }
        confirmLabel={quarterMode === 'copy' ? '复制' : '移动'}
        initialPeriod={nextQuarter(period)}
        onConfirm={quarterMode === 'copy' ? copyObjective : moveObjective}
        onClose={() => setQuarterMode(null)}
      />

      <ConfirmDialog
        open={deleteObjectiveOpen}
        title="删除目标？"
        description={`「${objective.title}」及其 ${allKeyResults.length} 个关键结果、子孙执行项都会被删除。此操作可以用撤销恢复。`}
        confirmLabel="删除目标"
        onConfirm={() => {
          setDeleteObjectiveOpen(false);
          deleteItems([objective.id]);
          notify('目标已删除', 'info');
        }}
        onClose={() => setDeleteObjectiveOpen(false)}
      />
    </article>
  );
}
