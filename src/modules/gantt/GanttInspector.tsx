import { useEffect, useState } from 'react';
import type { Workspace } from '../../core/model';
import { ITEM_STATUSES, KIND_LABELS, STATUS_LABELS } from '../../core/model';
import { childrenOf, itemById } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { dateKey, formatDateKey } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Field, Select, TextArea, TextInput } from '../../ui/Field';
import { IconButton } from '../../ui/IconButton';
import { Modal } from '../../ui/Modal';
import { Icon } from '../../ui/icons';
import { isGanttableItem, displayProgress, itemRange } from './scale';

export interface GanttInspectorProps {
  workspace: Workspace;
  selectedId: string | null;
  onSelect: (id: string | null) => void;
  onClose: () => void;
}

const STATUS_OPTIONS = ITEM_STATUSES.map((status) => ({ value: status, label: STATUS_LABELS[status] }));

export function GanttInspector({ workspace, selectedId, onSelect, onClose }: GanttInspectorProps) {
  const updateItem = useWorkspace((state) => state.updateItem);
  const deleteItems = useWorkspace((state) => state.deleteItems);
  const setStatus = useWorkspace((state) => state.setStatus);
  const toggleDone = useWorkspace((state) => state.toggleDone);
  const createEdge = useWorkspace((state) => state.createEdge);
  const deleteEdge = useWorkspace((state) => state.deleteEdge);
  const notify = useWorkspace((state) => state.notify);

  const item = selectedId ? itemById(workspace, selectedId) : undefined;

  const [title, setTitle] = useState(item?.title ?? '');
  const [notes, setNotes] = useState(item?.notes ?? '');
  const [progressDraft, setProgressDraft] = useState(item?.gantt?.progress ?? 0);
  const [direction, setDirection] = useState<'pre' | 'post'>('pre');
  const [addTarget, setAddTarget] = useState('');
  const [confirming, setConfirming] = useState(false);

  useEffect(() => {
    setDirection('pre');
    setAddTarget('');
    setConfirming(false);
    // 仅在切换条目时重置表单控件状态。
  }, [item?.id]);

  // 标题 / 备注 / 进度跟随 store（例如在左侧树中就地编辑后保持同步）。
  useEffect(() => {
    setTitle(item?.title ?? '');
  }, [item?.id, item?.title]);

  useEffect(() => {
    setNotes(item?.notes ?? '');
  }, [item?.id, item?.notes]);

  useEffect(() => {
    setProgressDraft(item?.gantt?.progress ?? 0);
  }, [item?.id, item?.gantt?.progress]);

  if (!item) {
    return (
      <aside className="gantt-inspector" aria-label="条目详情">
        <div className="gantt-inspector-head">
          <div className="gantt-inspector-title">
            <h2>详情</h2>
          </div>
          <IconButton label="收起详情" size="sm" onClick={onClose}>
            <Icon name="close" size={15} />
          </IconButton>
        </div>
        <EmptyState
          compact
          icon={<Icon name="timeline" size={18} />}
          title="未选中条目"
          description="点击左侧任务或时间轴上的任务条，查看并编辑细节。"
        />
      </aside>
    );
  }

  const start = dateKey(item.gantt?.start) ?? '';
  const end = dateKey(item.gantt?.end) ?? '';
  const range = itemRange(item);
  const progress = displayProgress(item);
  const isDone = item.status === 'done';
  const draftProgress = Math.min(100, Math.max(0, Math.round(progressDraft)));
  const shownProgress = isDone ? progress : draftProgress;
  const areaOptions = [
    { value: '', label: '未归属' },
    ...workspace.areas.map((area) => ({ value: area.id, label: area.name })),
  ];

  const dependsEdges = workspace.edges.filter(
    (edge) => edge.type === 'depends' && (edge.from === item.id || edge.to === item.id),
  );
  const blocked = new Set(
    workspace.edges.filter((edge) => edge.type === 'depends').map((edge) => `${edge.from}>${edge.to}`),
  );
  const candidateItems = workspace.items
    .filter((candidate) => isGanttableItem(candidate) && candidate.id !== item.id)
    .filter((candidate) =>
      direction === 'pre'
        ? !blocked.has(`${item.id}>${candidate.id}`)
        : !blocked.has(`${candidate.id}>${item.id}`),
    )
    .sort((a, b) => a.title.localeCompare(b.title, 'zh-Hans-CN'));
  const candidateOptions = [
    { value: '', label: candidateItems.length === 0 ? '没有可选的条目' : '选择条目…' },
    ...candidateItems.map((candidate) => {
      const candidateRange = itemRange(candidate);
      const suffix = candidateRange
        ? `（${formatDateKey(candidateRange.start, 'M/d')}–${formatDateKey(candidateRange.end, 'M/d')}）`
        : '（未排期）';
      return { value: candidate.id, label: `${candidate.title}${suffix}` };
    }),
  ];
  const children = childrenOf(workspace, item.id);

  const commitTitle = () => {
    const next = title.trim();
    if (next && next !== item.title) updateItem(item.id, { title: next });
    else setTitle(item.title);
  };

  const commitNotes = () => {
    if (notes !== item.notes) updateItem(item.id, { notes });
  };

  const commitProgress = () => {
    // 已完成条目的 100% 是展示口径，不写回 gantt.progress。
    if (isDone) return;
    const current = Math.round(item.gantt?.progress ?? 0);
    if (progressDraft !== current) updateItem(item.id, { gantt: { progress: progressDraft } });
  };

  const applyDate = (edge: 'start' | 'end', value: string) => {
    let nextStart = edge === 'start' ? (value || null) : (dateKey(item.gantt?.start) ?? null);
    let nextEnd = edge === 'end' ? (value || null) : (dateKey(item.gantt?.end) ?? null);
    if (nextStart && nextEnd && nextStart > nextEnd) {
      if (edge === 'start') nextEnd = nextStart;
      else nextStart = nextEnd;
    }
    updateItem(item.id, { gantt: { start: nextStart, end: nextEnd } });
  };

  const addDependency = () => {
    if (!addTarget) return;
    const from = direction === 'pre' ? item.id : addTarget;
    const to = direction === 'pre' ? addTarget : item.id;
    createEdge({ from, to, type: 'depends', label: '' });
    setAddTarget('');
    notify('已添加依赖', 'success');
  };

  const confirmDelete = () => {
    deleteItems([item.id]);
    setConfirming(false);
    onSelect(null);
    onClose();
  };

  return (
    <aside className="gantt-inspector" aria-label="条目详情">
      <div className="gantt-inspector-head">
        <div className="gantt-inspector-title">
          <h2>详情</h2>
          <Badge tone="neutral">{KIND_LABELS[item.kind]}</Badge>
        </div>
        <IconButton label="收起详情" size="sm" onClick={onClose}>
          <Icon name="close" size={15} />
        </IconButton>
      </div>

      <div className="gantt-inspector-body">
        <Field label="标题" htmlFor="gantt-title">
          <TextInput
            id="gantt-title"
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            onBlur={commitTitle}
            onKeyDown={(event) => {
              if (event.key === 'Enter') {
                event.preventDefault();
                commitTitle();
                event.currentTarget.blur();
              }
            }}
          />
        </Field>

        <Field label="备注" htmlFor="gantt-notes">
          <TextArea
            id="gantt-notes"
            rows={3}
            value={notes}
            placeholder="补充上下文、验收标准…"
            onChange={(event) => setNotes(event.target.value)}
            onBlur={commitNotes}
          />
        </Field>

        <div className="gantt-inspector-grid">
          <Field label="状态" htmlFor="gantt-status">
            <Select
              id="gantt-status"
              options={STATUS_OPTIONS}
              value={item.status}
              onChange={(event) => setStatus(item.id, event.target.value as (typeof ITEM_STATUSES)[number])}
            />
          </Field>
          <Field label="Area" htmlFor="gantt-area">
            <Select
              id="gantt-area"
              options={areaOptions}
              value={item.areaId ?? ''}
              onChange={(event) => updateItem(item.id, { areaId: event.target.value || null })}
            />
          </Field>
        </div>

        <div className="gantt-section">
          <div className="gantt-section-head">
            <span>日期</span>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => updateItem(item.id, { gantt: { start: null, end: null } })}
              disabled={!start && !end}
            >
              清除日期
            </Button>
          </div>

          <div className="gantt-date-row">
            <label className="gantt-date-label" htmlFor="gantt-start">
              开始
            </label>
            <input
              id="gantt-start"
              type="date"
              className="input gantt-date-input"
              value={start}
              onChange={(event) => applyDate('start', event.target.value)}
            />
            <IconButton
              label="清除开始日期"
              size="sm"
              disabled={!start}
              onClick={() => applyDate('start', '')}
            >
              <Icon name="x" size={13} />
            </IconButton>
          </div>

          <div className="gantt-date-row">
            <label className="gantt-date-label" htmlFor="gantt-end">
              结束
            </label>
            <input
              id="gantt-end"
              type="date"
              className="input gantt-date-input"
              value={end}
              onChange={(event) => applyDate('end', event.target.value)}
            />
            <IconButton label="清除结束日期" size="sm" disabled={!end} onClick={() => applyDate('end', '')}>
              <Icon name="x" size={13} />
            </IconButton>
          </div>

          <p className={`gantt-date-hint${range ? '' : ' is-empty'}`}>
            {range
              ? `${formatDateKey(range.start, 'yyyy/MM/dd')} → ${formatDateKey(range.end, 'yyyy/MM/dd')} · ${progress}%`
              : '未排期：设置开始日期后即可在时间轴上看到任务条。'}
          </p>
        </div>

        <div className="gantt-section">
          <div className="gantt-section-head">
            <span>进度</span>
            <span className="gantt-progress-value">{shownProgress}%</span>
          </div>
          <input
            type="range"
            className="gantt-progress-range"
            min={0}
            max={100}
            step={5}
            value={isDone ? progress : draftProgress}
            disabled={isDone}
            aria-label={`任务进度，当前 ${shownProgress}%`}
            aria-describedby={isDone ? 'gantt-progress-note' : undefined}
            onChange={(event) => setProgressDraft(Number(event.target.value))}
            onPointerUp={commitProgress}
            onKeyUp={commitProgress}
            onBlur={commitProgress}
          />
          {isDone ? (
            <p className="gantt-progress-note" id="gantt-progress-note">
              已完成条目进度按 100% 展示
            </p>
          ) : null}
        </div>

        <div className="gantt-section">
          <div className="gantt-section-head">
            <span>依赖</span>
            <span className="gantt-section-count">{dependsEdges.length}</span>
          </div>
          {dependsEdges.length === 0 ? <p className="gantt-section-empty">暂无依赖关系。</p> : null}
          <ul className="gantt-dep-list">
            {dependsEdges.map((edge) => {
              const outgoing = edge.from === item.id;
              const other = itemById(workspace, outgoing ? edge.to : edge.from);
              return (
                <li key={edge.id} className="gantt-dep-row">
                  <Icon name="link" size={13} />
                  <span className="gantt-dep-text">
                    {outgoing ? `依赖「${other?.title ?? '已删除'}」` : `「${other?.title ?? '已删除'}」依赖此任务`}
                  </span>
                  <IconButton
                    label="删除依赖"
                    size="sm"
                    variant="danger"
                    onClick={() => deleteEdge(edge.id)}
                  >
                    <Icon name="trash" size={13} />
                  </IconButton>
                </li>
              );
            })}
          </ul>

          <div className="gantt-dep-form">
            <Select
              aria-label="依赖方向"
              options={[
                { value: 'pre', label: '当前任务依赖…' },
                { value: 'post', label: '…依赖当前任务' },
              ]}
              value={direction}
              onChange={(event) => {
                setDirection(event.target.value === 'post' ? 'post' : 'pre');
                setAddTarget('');
              }}
            />
            <Select
              aria-label="选择依赖条目"
              options={candidateOptions}
              value={addTarget}
              onChange={(event) => setAddTarget(event.target.value)}
              disabled={candidateItems.length === 0}
            />
            <Button size="sm" onClick={addDependency} disabled={!addTarget}>
              添加依赖
            </Button>
          </div>
        </div>

        <div className="gantt-section">
          <div className="gantt-section-head">
            <span>子任务</span>
            <span className="gantt-section-count">{children.length}</span>
          </div>
          {children.length === 0 ? <p className="gantt-section-empty">暂无子任务。</p> : null}
          <ul className="gantt-child-list">
            {children.map((child) => (
              <li key={child.id} className="gantt-child-row">
                <input
                  type="checkbox"
                  className="gantt-check"
                  checked={child.status === 'done'}
                  aria-label={`完成 ${child.title}`}
                  onChange={() => toggleDone(child.id)}
                />
                <button type="button" className="gantt-child-title" onClick={() => onSelect(child.id)}>
                  {child.title}
                </button>
                {child.gantt?.end ? (
                  <span className="gantt-child-date">{formatDateKey(child.gantt.end, 'M/d')}</span>
                ) : null}
              </li>
            ))}
          </ul>
        </div>

        <div className="gantt-inspector-footer">
          <Button
            size="sm"
            variant="danger"
            iconLeft={<Icon name="trash" size={14} />}
            onClick={() => setConfirming(true)}
          >
            删除条目
          </Button>
        </div>
      </div>

      <Modal
        open={confirming}
        onClose={() => setConfirming(false)}
        title="删除条目"
        description={`「${item.title}」及其子任务会被删除，可用撤销恢复。`}
        footer={
          <>
            <Button size="sm" variant="secondary" onClick={() => setConfirming(false)}>
              取消
            </Button>
            <Button size="sm" variant="danger" onClick={confirmDelete}>
              确认删除
            </Button>
          </>
        }
      >
        <p>删除后依赖该条目的连线也会一并移除。确定继续吗？</p>
      </Modal>
    </aside>
  );
}
