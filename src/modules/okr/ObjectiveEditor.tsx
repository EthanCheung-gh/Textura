import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Item, ItemStatus } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { childrenOf, itemById, rollupProgress } from '../../core/selectors';
import { getWorkspace, useWorkspace } from '../../core/store';
import { currentQuarter, formatDateTime } from '../../core/utils';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Field, Select, TextArea } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { Progress } from '../../ui/Progress';
import type { SaveState } from '../../core/store';
import { ConfidenceScale } from './ConfidenceScale';
import { ConfirmDialog } from './ConfirmDialog';
import { EditableTitle } from './EditableTitle';
import { KrRow } from './KrRow';
import { QuarterDialog } from './QuarterDialog';
import { nextQuarter, quarterElapsedPercent, quarterLabel } from './okrMath';
import { progressTone } from './okrDisplay';
import { resolveEditorObjective, summarizeEditor } from './okrEditor';

/** notes 停止输入后多久写入 store（失焦 / 卸载会提前 flush）。 */
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
 * 目标不存在（已删除 / 非 objective）时渲染空态，不白屏。
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

  // Esc 返回：输入控件内（编辑器自己的 Esc 语义）与弹窗内不触发。
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || event.defaultPrevented) return;
      const target = event.target instanceof HTMLElement ? event.target : null;
      if (target) {
        if (target.isContentEditable) return;
        const tag = target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
        if (target.closest('[role="dialog"]')) return;
      }
      onBack();
    };
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [onBack]);

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
  const krInputRef = useRef<HTMLInputElement>(null);

  const keyResults = useMemo(
    () => childrenOf(workspace, objective.id).filter((item) => item.kind === 'keyresult'),
    [workspace, objective.id],
  );
  const summary = useMemo(() => summarizeEditor(workspace, objective.id), [workspace, objective.id]);
  const progress = rollupProgress(workspace, objective.id);
  const period = objective.okr?.period ?? currentQuarter();
  const confidence = objective.okr?.confidence ?? 5;
  const elapsedPercent = quarterElapsedPercent(period);

  const areaOptions = [
    { value: '', label: '未归属 Area' },
    ...workspace.areas.map((area) => ({ value: area.id, label: area.name })),
  ];

  /* ---------- notes：本地草稿 + 600ms 防抖 + 失焦/卸载 flush ---------- */
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
    krInputRef.current?.focus();
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
        <h2 id={titleId} className="okr-editor-heading">
          <span className="okr-editor-sr">目标编辑：</span>
          <EditableTitle
            value={objective.title}
            ariaLabel={`编辑目标标题：${objective.title}`}
            className="okr-editor-title"
            onCommit={(next) => updateItem(objective.id, { title: next })}
          />
        </h2>

        <div className="okr-editor-fields">
          <label className="okr-editor-field">
            <span className="okr-editor-field-label">领域</span>
            <Select
              options={areaOptions}
              value={objective.areaId ?? ''}
              aria-label="目标归属 Area"
              onChange={(event) => updateItem(objective.id, { areaId: event.target.value || null })}
            />
          </label>
          <label className="okr-editor-field">
            <span className="okr-editor-field-label">状态</span>
            <Select
              options={OBJECTIVE_STATUS_OPTIONS}
              value={objective.status}
              aria-label="目标状态"
              onChange={(event) => setStatus(objective.id, event.target.value as ItemStatus)}
            />
          </label>
          <div className="okr-editor-field okr-editor-field--confidence">
            <span className="okr-editor-field-label">信心</span>
            <ConfidenceScale
              value={confidence}
              size="md"
              ariaLabel={`${objective.title} 信心指数`}
              onChange={(next) => updateItem(objective.id, { okr: { confidence: next } })}
            />
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

        <Field label="备注" hint="停止输入 600ms 后保存；失焦立即提交。">
          <TextArea
            className="okr-editor-notes"
            rows={3}
            value={notesDraft}
            placeholder="为什么这是本季度最重要的事？"
            aria-label={`${objective.title} 备注`}
            onChange={(event) => handleNotesChange(event.target.value)}
            onBlur={flushNotes}
          />
        </Field>
      </div>

      <section className="okr-editor-section" aria-labelledby={`${titleId}-kr`}>
        <div className="okr-editor-section-head">
          <h3 id={`${titleId}-kr`} className="okr-editor-section-title">
            关键结果 · {keyResults.length}
          </h3>
          <span className="okr-editor-section-note">上下移调整顺序；指标、负责人与执行项在行内编辑</span>
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
                onDelete={setPendingDeleteKr}
              />
            ))}
          </ol>
        )}

        <div className="okr-add-kr">
          <Icon name="plus" size={14} />
          <input
            ref={krInputRef}
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
              }
            }}
          />
          <Button size="sm" variant="ghost" disabled={!newKr.trim()} onClick={addKeyResult}>
            添加
          </Button>
        </div>
      </section>

      <section className="okr-editor-exec-summary" aria-label="执行项概览">
        <span className="okr-editor-exec-line">
          <Icon name="link" size={14} />
          关联执行项 {summary.executionItems} · 已完成 {summary.doneExecutionItems}
        </span>
        {summary.executionItems === 0 ? (
          <p className="okr-editor-hint">
            还没有关联执行项。在上方关键结果点击「关联执行项」，把甘特 / GTD 里的项目与行动挂上来。
          </p>
        ) : (
          <p className="okr-editor-hint">明细在每条关键结果下；勾选可直接标记完成。</p>
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
