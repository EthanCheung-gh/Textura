import { useEffect, useMemo, useRef, useState } from 'react';
import clsx from 'clsx';
import type { Item, Workspace } from '../../core/model';
import { KIND_LABELS, STATUS_LABELS } from '../../core/model';
import { areaById, itemsOfKind } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { Modal } from '../../ui/Modal';
import { Progress } from '../../ui/Progress';
import { EmptyState } from '../../ui/EmptyState';
import { executionItemsOf, matchesQuery } from './okrMath';
import { formatSchedule, statusTone } from './okrDisplay';

interface LinkItemsDialogProps {
  open: boolean;
  kr: Item;
  workspace: Workspace;
  onClose: () => void;
}

/** 为 KR 关联项目/行动：搜索、多选、写入 `okr` 边（store 负责去重）。 */
export function LinkItemsDialog({ open, kr, workspace, onClose }: LinkItemsDialogProps) {
  const createEdge = useWorkspace((state) => state.createEdge);
  const notify = useWorkspace((state) => state.notify);
  const uiSearch = useWorkspace((state) => state.ui.search);
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState<Set<string>>(() => new Set());
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!open) return;
    setQuery(uiSearch);
    setSelected(new Set());
  }, [open, kr.id, uiSearch]);

  const linkedIds = useMemo(
    () => new Set(executionItemsOf(workspace, kr.id).map((entry) => entry.item.id)),
    [workspace, kr.id],
  );

  const candidates = useMemo(() => {
    const pool = [...itemsOfKind(workspace, 'project'), ...itemsOfKind(workspace, 'action')];
    return pool.filter((item) => matchesQuery(workspace, item, query));
  }, [workspace, query]);

  const toggle = (id: string) => {
    setSelected((previous) => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const confirm = () => {
    if (selected.size === 0) return;
    for (const id of selected) {
      createEdge({ from: kr.id, to: id, type: 'okr' });
    }
    notify(`已关联 ${selected.size} 个执行项`, 'success');
    onClose();
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="关联执行项"
      description={`为「${kr.title}」挑选支撑它的项目或行动。`}
      width={640}
      initialFocusRef={searchRef}
      footer={
        <>
          <span className="okr-link-count">已选 {selected.size}</span>
          <Button variant="ghost" onClick={onClose}>
            取消
          </Button>
          <Button variant="primary" disabled={selected.size === 0} onClick={confirm}>
            关联所选
          </Button>
        </>
      }
    >
      <div className="okr-link-search">
        <Icon name="search" size={15} />
        <TextInput
          ref={searchRef}
          type="search"
          value={query}
          placeholder="搜索项目或行动（标题、标签、负责人）…"
          aria-label="搜索可关联的执行项"
          onChange={(event) => setQuery(event.target.value)}
        />
      </div>
      <p className="okr-dialog-hint">
        来自甘特 / GTD 的项目与行动。已通过层级挂在 KR 下的子项也会显示为「已关联」。
      </p>

      <ul className="okr-link-list">
        {candidates.map((item) => {
          const linked = linkedIds.has(item.id);
          const checked = linked || selected.has(item.id);
          const area = item.areaId ? areaById(workspace, item.areaId) : undefined;
          const progress = item.status === 'done' ? 100 : (item.gantt?.progress ?? 0);
          return (
            <li key={item.id}>
              <label className={clsx('okr-link-item', linked && 'is-linked', checked && 'is-checked')}>
                <input
                  type="checkbox"
                  className="okr-check"
                  checked={checked}
                  disabled={linked}
                  onChange={() => toggle(item.id)}
                  aria-label={`关联「${item.title}」`}
                />
                <span className="okr-link-main">
                  <span className="okr-link-title">{item.title}</span>
                  <span className="okr-link-meta">
                    <Badge tone="neutral">{KIND_LABELS[item.kind]}</Badge>
                    <Badge tone={statusTone(item.status)}>{STATUS_LABELS[item.status]}</Badge>
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
                    <span className="mono">{formatSchedule(item)}</span>
                    {linked ? <Badge tone="ok">已关联</Badge> : null}
                  </span>
                </span>
                <span className="okr-link-progress">
                  <Progress
                    value={progress}
                    size="sm"
                    ariaLabel={`${item.title} 进度`}
                  />
                  <span className="mono">{progress}%</span>
                </span>
              </label>
            </li>
          );
        })}
      </ul>

      {candidates.length === 0 ? (
        <EmptyState
          compact
          icon={<Icon name="search" size={18} />}
          title="没有匹配的执行项"
          description="换个关键词，或先在甘特 / GTD 中创建行动。"
        />
      ) : null}
    </Modal>
  );
}
