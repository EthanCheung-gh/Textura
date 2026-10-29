import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import clsx from 'clsx';
import type { Item, ItemStatus } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { areaById, childrenOf, itemById, rollupProgress } from '../../core/selectors';
import { getWorkspace, useWorkspace } from '../../core/store';
import { currentQuarter, formatDateTime } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Select, TextArea, TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { Progress } from '../../ui/Progress';
import type { SaveState } from '../../core/store';
import { ConfidenceScale } from './ConfidenceScale';
import { ConfirmDialog } from './ConfirmDialog';
import { EditPencil } from './EditPencil';
import { KrRow } from './KrRow';
import { QuarterDialog } from './QuarterDialog';
import { nextQuarter, quarterElapsedPercent, quarterLabel } from './okrMath';
import { progressTone, statusTone } from './okrDisplay';
import { resolveEditorObjective, summarizeEditor } from './okrEditor';
import { editTargetKey, isEditingKr, nextEditTarget } from './editTarget';
import type { EditTarget } from './editTarget';

/** notes 停止输入后多久写入 store（失焦 / 结束编辑 / 卸载会提前 flush）。 */
const NOTES_COMMIT_DELAY_MS = 600;

const OBJECTIVE_STATUS_OPTIONS = (
  ['next', 'active', 'waiting', 'scheduled', 'done', 'dropped'] as ItemStatus[]
).map((status) => ({ value: status, label: STATUS_LABELS[status] }));

const SAVE_LABELS: Record<SaveState, string> = {
  idle: '已保存',
  saving: '保存中…',
  saved: '已保存',
  error: '保存失败',
};

const SAVE_ICONS: Record<SaveState, 'check' | 'clock' | 'flag'> = {
  idle: 'check',
  saving: 'clock',
  saved: 'check',
  error: 'flag',
};

interface ObjectiveEditorProps {
  objectiveId: string;
  onBack: () => void;
}

/**
 * 独立页面式的目标编辑视图：顶部返回 / 面包屑 / 保存状态，
 * 下方 Hero（标题 + 元信息 + notes）、KR 明细、执行项概览与目标操作。
 *
 * 视图默认只读（只渲染文本），点铅笔才挂载输入控件；Esc 先收起编辑目标，
 * 再按一次才返回列表。目标不存在（已删除 / 非 objective）时渲染空态，不白屏。
 */
export function ObjectiveEditor({ objectiveId, onBack }: ObjectiveEditorProps) {
  const workspace = useWorkspace((state) => state.workspace);
  const saveState = useWorkspace((state) => state.saveState);
  const objective = useMemo(
    () => resolveEditorObjective(workspace, objectiveId),
    [workspace, objectiveId],
  );

  const backRef = useRef<HTMLButtonElement>(null);
  const titleId = `okr-editor-heading-${objectiveId}`;
  const period = objective?.okr?.period ?? currentQuarter();

  // 进入编辑视图后焦点落到「返回目标列表」。
  useEffect(() => {
    backRef.current?.focus();
  }, [objectiveId]);

  // 空态没有编辑主体，Esc 直接返回列表；有目标时由 ObjectiveEditorBody 处理
  //（它知道当前编辑目标，先收起编辑态再退出）。
  useEffect(() => {
    if (objective) return;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || event.defaultPrevented) return;
      const target = event.target instanceof HTMLElement ? event.target : null;
      if (target?.closest('[role="dialog"]')) return;
      onBack();
    };
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [objective, onBack]);

  return (
    <section
      className="okr-editor"
      role="region"
      aria-label="目标编辑"
      aria-labelledby={objective ? titleId : undefined}
    >
      <div className="okr-editor-bar">
        <Button
          ref={backRef}
          variant="ghost"
          size="sm"
          iconLeft={<Icon name="chevron-left" size={14} />}
          onClick={onBack}
        >
          返回目标列表
        </Button>
        <span className="okr-editor-crumb">{quarterLabel(period)} · 目标编辑</span>
        <span className="okr-editor-save" data-state={saveState} role="status">
          <Icon name={SAVE_ICONS[saveState]} size={13} />
          {SAVE_LABELS[saveState]}
        </span>
      </div>

      {objective ? (
        <ObjectiveEditorBody key={objective.id} objective={objective} titleId={titleId} onBack={onBack} />
      ) : (
        <div className="okr-editor-empty">
          <EmptyState
            icon={<Icon name="target" size={20} />}
            title="目标不存在或已被删除"
            description="这个目标可能已经被删除，或链接里的 id 并不是一个目标。"
            action={
              <Button variant="secondary" onClick={onBack}>
                返回目标列表
              </Button>
            }
          />
        </div>
      )}
    </section>
  );
}

interface ObjectiveEditorBodyProps {
  objective: Item;
  titleId: string;
  onBack: () => void;
}

/**
 * 编辑主体：持有唯一的 `editTarget`。
 *
 * 任何时刻最多一个编辑目标；`startEdit` 切换目标、`endEdit` 收起，
 * 收起后焦点回到该字段的铅笔（`data-edit-target`）。
 */
function ObjectiveEditorBody({ objective, titleId, onBack }: ObjectiveEditorBodyProps) {
  const workspace = useWorkspace((state) => state.workspace);
  const updateItem = useWorkspace((state) => state.updateItem);
  const updateItems = useWorkspace((state) => state.updateItems);
  const createItem = useWorkspace((state) => state.createItem);
  const deleteItems = useWorkspace((state) => state.deleteItems);
  const setStatus = useWorkspace((state) => state.setStatus);
  const setUi = useWorkspace((state) => state.setUi);
  const notify = useWorkspace((state) => state.notify);

  const [quarterMode, setQuarterMode] = useState<'move' | 'copy' | null>(null);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [pendingDeleteKr, setPendingDeleteKr] = useState<Item | null>(null);
  const [newKr, setNewKr] = useState('');
  /** 唯一编辑目标：null = 全部只读。 */
  const [editTarget, setEditTarget] = useState<EditTarget>(null);
  const previousTargetRef = useRef<EditTarget>(null);
  const confidenceRef = useRef<HTMLSpanElement>(null);

  const keyResults = useMemo(
    () => childrenOf(workspace, objective.id).filter((item) => item.kind === 'keyresult'),
    [workspace, objective.id],
  );
  const summary = useMemo(() => summarizeEditor(workspace, objective.id), [workspace, objective.id]);
  const progress = rollupProgress(workspace, objective.id);
  const period = objective.okr?.period ?? currentQuarter();
  const confidence = objective.okr?.confidence ?? 5;
  const area = objective.areaId ? areaById(workspace, objective.areaId) : undefined;
  const elapsedPercent = quarterElapsedPercent(period);

  const editingTitle = editTarget?.kind === 'title';
  const editingArea = editTarget?.kind === 'area';
  const editingStatus = editTarget?.kind === 'status';
  const editingConfidence = editTarget?.kind === 'confidence';
  const editingNotes = editTarget?.kind === 'notes';
  const addingKr = editTarget?.kind === 'add-kr';

  const areaOptions = [
    { value: '', label: '未归属 Area' },
    ...workspace.areas.map((entry) => ({ value: entry.id, label: entry.name })),
  ];

  /** 开始 / 切换 / 收起编辑目标（点同一支铅笔相当于收起）。 */
  const startEdit = useCallback((next: EditTarget) => {
    setEditTarget((current) => nextEditTarget(current, next));
  }, []);
  const endEdit = useCallback(() => setEditTarget(null), []);

  // 结束编辑后把焦点还给刚才那支铅笔：键盘用户不会掉到 body 上。
  useEffect(() => {
    const previous = previousTargetRef.current;
    previousTargetRef.current = editTarget;
    if (editTarget !== null || previous === null) return;
    const key = editTargetKey(previous);
    const frame = requestAnimationFrame(() => {
      const node = document.querySelector<HTMLElement>(`[data-edit-target="${key}"]`);
      node?.focus();
    });
    return () => cancelAnimationFrame(frame);
  }, [editTarget]);

  // 信心刻度是按钮组，没有 autoFocus：进入编辑态后聚焦当前分值的 radio。
  useEffect(() => {
    if (!editingConfidence) return;
    confidenceRef.current
      ?.querySelector<HTMLButtonElement>('[role="radio"][aria-checked="true"]')
      ?.focus();
  }, [editingConfidence]);

  // 有编辑目标时 Esc 只收起它；没有时才返回列表。字段自身的 Esc 会 stopPropagation。
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || event.defaultPrevented) return;
      const target = event.target instanceof HTMLElement ? event.target : null;
      if (target?.closest('[role="dialog"]')) return;
      if (editTarget !== null) {
        setEditTarget(null);
        return;
      }
      onBack();
    };
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [editTarget, onBack]);

  // 新增 KR 输入框只在 `add-kr` 目标下存在；切走时丢掉未提交草稿，不留孤儿输入。
  useEffect(() => {
    if (editTarget?.kind === 'add-kr') return;
    setNewKr((current) => (current ? '' : current));
  }, [editTarget]);

  /* ---------- 标题 ---------- */
  const [titleDraft, setTitleDraft] = useState(objective.title);

  const startTitleEdit = () => {
    setTitleDraft(objective.title);
    startEdit({ kind: 'title' });
  };

  const commitTitle = () => {
    const next = titleDraft.trim();
    if (next && next !== objective.title) updateItem(objective.id, { title: next });
    else setTitleDraft(objective.title);
    endEdit();
  };

  /* ---------- notes：本地草稿 + 600ms 防抖 + 失焦/结束/卸载 flush ---------- */
  const [notesDraft, setNotesDraft] = useState(objective.notes);
  const notesDraftRef = useRef(objective.notes);
  const notesCommittedRef = useRef(objective.notes);
  const notesTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const objectiveIdRef = useRef(objective.id);
  objectiveIdRef.current = objective.id;

  /** 把本地草稿提交到 store（无变化 / 目标已删除时不写）。 */
  const flushNotes = useCallback(() => {
    if (notesTimer.current !== null) {
      clearTimeout(notesTimer.current);
      notesTimer.current = null;
    }
    const next = notesDraftRef.current;
    if (next === notesCommittedRef.current) return;
    notesCommittedRef.current = next;
    const store = getWorkspace();
    if (itemById(store.workspace, objectiveIdRef.current)) {
      store.updateItem(objectiveIdRef.current, { notes: next });
    }
  }, []);

  // 外部改动（撤销 / 导入）才覆盖草稿；自己提交后值相等，不会打断输入。
  useEffect(() => {
    if (objective.notes === notesCommittedRef.current) return;
    notesCommittedRef.current = objective.notes;
    notesDraftRef.current = objective.notes;
    setNotesDraft(objective.notes);
  }, [objective.notes]);

  // 卸载（返回列表 / 切换目标）时 flush 草稿。
  useEffect(() => () => flushNotes(), [flushNotes]);

  const handleNotesChange = (value: string) => {
    notesDraftRef.current = value;
    setNotesDraft(value);
    if (notesTimer.current !== null) clearTimeout(notesTimer.current);
    notesTimer.current = setTimeout(() => {
      notesTimer.current = null;
      flushNotes();
    }, NOTES_COMMIT_DELAY_MS);
  };

  const startNotesEdit = () => {
    notesDraftRef.current = notesCommittedRef.current;
    setNotesDraft(notesCommittedRef.current);
    startEdit({ kind: 'notes' });
  };

  const commitNotes = () => {
    flushNotes();
    endEdit();
  };

  /** Esc：回退到上次提交值再结束编辑，不写 store。 */
  const cancelNotes = () => {
    if (notesTimer.current !== null) {
      clearTimeout(notesTimer.current);
      notesTimer.current = null;
    }
    notesDraftRef.current = notesCommittedRef.current;
    setNotesDraft(notesCommittedRef.current);
    endEdit();
  };

  /* ---------- 新增 KR ---------- */
  const addKeyResult = () => {
    const title = newKr.trim();
    if (!title) return;
    createItem({
      kind: 'keyresult',
      title,
      parentId: objective.id,
      status: 'active',
      areaId: objective.areaId,
      okr: { period, confidence: 5 },
    });
    setNewKr('');
    endEdit();
  };

  const moveObjective = (target: string) => {
    // 目标 + 全部 KR 一次提交：一条历史，一次撤销整体回退。
    updateItems([
      { id: objective.id, patch: { okr: { period: target } } },
      ...keyResults.map((kr) => ({ id: kr.id, patch: { okr: { period: target } } })),
    ]);
    setQuarterMode(null);
    // 留在编辑视图；列表的季度同步到目标新周期，返回后仍能看到它。
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
    for (const kr of keyResults) {
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
    notify(`已复制为新季度目标：${quarterLabel(target)}`, 'success');
  };

  const deleteObjective = () => {
    setDeleteOpen(false);
    deleteItems([objective.id]);
    notify('目标已删除', 'info');
    onBack();
  };

  return (
    <>
      <div className="okr-editor-hero">
        <div className="okr-editor-title-row">
          <h2 id={titleId} className="okr-editor-heading">
            <span className="okr-editor-sr">目标编辑：</span>
            {editingTitle ? (
              <TextInput
                autoFocus
                className="okr-editor-title"
                value={titleDraft}
                aria-label="目标标题"
                onChange={(event) => setTitleDraft(event.target.value)}
                onBlur={commitTitle}
                onKeyDown={(event) => {
                  if (event.nativeEvent.isComposing) return;
                  if (event.key === 'Enter') {
                    event.preventDefault();
                    event.currentTarget.blur();
                  } else if (event.key === 'Escape') {
                    event.preventDefault();
                    event.stopPropagation();
                    setTitleDraft(objective.title);
                    endEdit();
                  }
                }}
              />
            ) : (
              <span className="okr-editor-title">{objective.title}</span>
            )}
          </h2>
          {editingTitle ? null : (
            <EditPencil target="title" label="编辑目标标题" onClick={startTitleEdit} />
          )}
        </div>

        <div className="okr-editor-fields">
          <div className="okr-editor-field">
            <span className="okr-editor-field-label">领域</span>
            {editingArea ? (
              <Select
                autoFocus
                options={areaOptions}
                value={objective.areaId ?? ''}
                aria-label="目标归属 Area"
                onChange={(event) => {
                  updateItem(objective.id, { areaId: event.target.value || null });
                  endEdit();
                }}
                onBlur={endEdit}
              />
            ) : (
              <span className="okr-editor-field-value">
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
                <EditPencil
                  target="area"
                  label="编辑目标领域"
                  onClick={() => startEdit({ kind: 'area' })}
                />
              </span>
            )}
          </div>

          <div className="okr-editor-field">
            <span className="okr-editor-field-label">状态</span>
            {editingStatus ? (
              <Select
                autoFocus
                options={OBJECTIVE_STATUS_OPTIONS}
                value={objective.status}
                aria-label="目标状态"
                onChange={(event) => {
                  setStatus(objective.id, event.target.value as ItemStatus);
                  endEdit();
                }}
                onBlur={endEdit}
              />
            ) : (
              <span className="okr-editor-field-value">
                <Badge tone={statusTone(objective.status)}>{STATUS_LABELS[objective.status]}</Badge>
                <EditPencil
                  target="status"
                  label="编辑目标状态"
                  onClick={() => startEdit({ kind: 'status' })}
                />
              </span>
            )}
          </div>

          <div className="okr-editor-field okr-editor-field--confidence">
            <span className="okr-editor-field-label">信心</span>
            <span className="okr-editor-field-value" ref={confidenceRef}>
              {editingConfidence ? (
                <ConfidenceScale
                  value={confidence}
                  size="md"
                  ariaLabel={`${objective.title} 信心指数`}
                  onChange={(next) => {
                    updateItem(objective.id, { okr: { confidence: next } });
                    endEdit();
                  }}
                />
              ) : (
                <>
                  <ConfidenceScale
                    value={confidence}
                    size="md"
                    readOnly
                    ariaLabel={`${objective.title} 信心指数`}
                  />
                  <EditPencil
                    target="confidence"
                    label="编辑目标信心"
                    onClick={() => startEdit({ kind: 'confidence' })}
                  />
                </>
              )}
            </span>
          </div>
        </div>

        <div className="okr-editor-progress">
          <span className="okr-editor-field-label">整体进度</span>
          <Progress
            value={progress}
            tone={progressTone(progress, false)}
            ariaLabel={`${objective.title} 整体进度`}
          />
          <span className="okr-editor-pct mono">{progress}%</span>
        </div>

        <div className="okr-editor-dates">
          <span>创建 {formatDateTime(objective.createdAt)}</span>
          <span>更新 {formatDateTime(objective.updatedAt)}</span>
        </div>

        <div className="okr-editor-notes-field">
          <div className="okr-editor-notes-head">
            <span className="okr-editor-field-label">备注</span>
            {editingNotes ? null : (
              <EditPencil target="notes" label="编辑目标备注" onClick={startNotesEdit} />
            )}
          </div>
          {editingNotes ? (
            <>
              <TextArea
                autoFocus
                className="okr-editor-notes"
                rows={3}
                value={notesDraft}
                placeholder="为什么这是本季度最重要的事？"
                aria-label={`${objective.title} 备注`}
                onChange={(event) => handleNotesChange(event.target.value)}
                onBlur={commitNotes}
                onKeyDown={(event) => {
                  if (event.nativeEvent.isComposing) return;
                  if (event.key === 'Escape') {
                    event.preventDefault();
                    event.stopPropagation();
                    cancelNotes();
                  }
                }}
              />
              <p className="field-hint">停止输入 600ms 后保存；失焦立即提交，Esc 取消。</p>
            </>
          ) : (
            <p
              className={clsx('okr-editor-notes-text', !objective.notes && 'is-empty')}
            >
              {objective.notes || '添加备注'}
            </p>
          )}
        </div>
      </div>

      <section className="okr-editor-section" aria-labelledby={`${titleId}-kr`}>
        <div className="okr-editor-section-head">
          <h3 id={`${titleId}-kr`} className="okr-editor-section-title">
            关键结果 · {keyResults.length}
          </h3>
          <span className="okr-editor-section-note">
            点铅笔编辑某一条；同一时刻只展开一条 KR
          </span>
        </div>

        {keyResults.length === 0 ? (
          <p className="okr-editor-kr-empty">
            还没有关键结果。用一个可量化的结果来支撑这个目标，例如「NPS 从 42 提升到 60」。
          </p>
        ) : (
          <ol className="okr-kr-list" aria-label={`${objective.title} 的关键结果`}>
            {keyResults.map((kr, index) => (
              <KrRow
                key={kr.id}
                objective={objective}
                kr={kr}
                index={index}
                count={keyResults.length}
                elapsedPercent={elapsedPercent}
                density="detailed"
                readOnly={false}
                editing={isEditingKr(editTarget, kr.id)}
                onStartEdit={() => startEdit({ kind: 'kr', id: kr.id })}
                onDone={endEdit}
                onDelete={setPendingDeleteKr}
              />
            ))}
          </ol>
        )}

        <div className={clsx('okr-add-kr', !addingKr && 'okr-add-kr--idle')}>
          {addingKr ? (
            <>
              <Icon name="plus" size={14} />
              <input
                autoFocus
                className="okr-add-kr-input"
                value={newKr}
                placeholder="新增关键结果，回车创建（默认信心 5）…"
                aria-label={`为「${objective.title}」新增关键结果`}
                onChange={(event) => setNewKr(event.target.value)}
                onKeyDown={(event) => {
                  if (event.nativeEvent.isComposing) return;
                  if (event.key === 'Enter') {
                    event.preventDefault();
                    addKeyResult();
                  } else if (event.key === 'Escape') {
                    event.preventDefault();
                    event.stopPropagation();
                    setNewKr('');
                    endEdit();
                  }
                }}
              />
              <Button size="sm" variant="ghost" disabled={!newKr.trim()} onClick={addKeyResult}>
                添加
              </Button>
            </>
          ) : (
            <Button
              size="sm"
              variant="ghost"
              className="okr-add-kr-trigger"
              data-edit-target="add-kr"
              iconLeft={<Icon name="plus" size={14} />}
              onClick={() => startEdit({ kind: 'add-kr' })}
            >
              新增关键结果
            </Button>
          )}
        </div>
      </section>

      <section className="okr-editor-exec-summary" aria-label="执行项概览">
        <span className="okr-editor-exec-line">
          <Icon name="link" size={14} />
          关联执行项 {summary.executionItems} · 已完成 {summary.doneExecutionItems}
        </span>
        {summary.executionItems === 0 ? (
          <p className="okr-editor-hint">
            还没有关联执行项。展开某条关键结果后点「关联执行项」，把甘特 / GTD 里的项目与行动挂上来。
          </p>
        ) : (
          <p className="okr-editor-hint">明细在每条关键结果下；展开后可勾选完成。</p>
        )}
      </section>

      <div className="okr-editor-actions">
        <Button
          size="sm"
          variant="secondary"
          iconLeft={<Icon name="calendar" size={14} />}
          onClick={() => setQuarterMode('move')}
        >
          移动到其他季度
        </Button>
        <Button
          size="sm"
          variant="secondary"
          iconLeft={<Icon name="plus" size={14} />}
          onClick={() => setQuarterMode('copy')}
        >
          复制为新季度目标
        </Button>
        <Button
          size="sm"
          variant="danger"
          iconLeft={<Icon name="trash" size={14} />}
          onClick={() => setDeleteOpen(true)}
        >
          删除目标
        </Button>
      </div>

      <QuarterDialog
        open={quarterMode !== null}
        title={quarterMode === 'copy' ? '复制为新季度目标' : '移动目标到其他季度'}
        description={
          quarterMode === 'copy'
            ? '复制目标与全部 KR；KR 的当前值会重置为起点，执行项关联不会复制。'
            : '目标与它的 KR 会一起移动到新季度。你仍会留在当前编辑视图。'
        }
        confirmLabel={quarterMode === 'copy' ? '复制' : '移动'}
        initialPeriod={nextQuarter(period)}
        onConfirm={quarterMode === 'copy' ? copyObjective : moveObjective}
        onClose={() => setQuarterMode(null)}
      />

      <ConfirmDialog
        open={deleteOpen}
        title="删除目标？"
        description={`「${objective.title}」及其 ${keyResults.length} 个关键结果、子孙执行项都会被删除。此操作可以用撤销恢复。`}
        confirmLabel="删除目标"
        onConfirm={deleteObjective}
        onClose={() => setDeleteOpen(false)}
      />

      <ConfirmDialog
        open={pendingDeleteKr !== null}
        title="删除关键结果？"
        description={
          pendingDeleteKr
            ? `「${pendingDeleteKr.title}」及其下挂的子项会被删除；通过边关联的执行项只会解除关联。`
            : ''
        }
        confirmLabel="删除 KR"
        onConfirm={() => {
          const target = pendingDeleteKr;
          setPendingDeleteKr(null);
          if (target) deleteItems([target.id]);
          notify('关键结果已删除', 'info');
        }}
        onClose={() => setPendingDeleteKr(null)}
      />
    </>
  );
}
