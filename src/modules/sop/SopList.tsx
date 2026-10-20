/** 左栏：SOP 列表（选择 / 新建 / 重命名 / 删除 / 搜索联动）。 */
import { useMemo, useState } from 'react';
import type { Item, SopRunEntry } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { areaById, childrenOf } from '../../core/selectors';
import { Badge } from '../../ui/Badge';
import type { BadgeTone } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Select, TextInput } from '../../ui/Field';
import { IconButton } from '../../ui/IconButton';
import { Icon } from '../../ui/icons';
import { Modal } from '../../ui/Modal';

export interface SopListProps {
  sops: Item[];
  selectedId: string | null;
  onSelect: (id: string) => void;
}

const RUN_BADGE: Record<SopRunEntry['result'], { tone: BadgeTone; label: string }> = {
  pass: { tone: 'ok', label: '通过' },
  fail: { tone: 'danger', label: '未通过' },
  skip: { tone: 'warn', label: '跳过' },
};

function latestRun(runs: SopRunEntry[], sopId: string): SopRunEntry | null {
  let latest: SopRunEntry | null = null;
  for (const run of runs) {
    if (run.sopId !== sopId) continue;
    if (!latest || run.at > latest.at) latest = run;
  }
  return latest;
}

export function SopList({ sops, selectedId, onSelect }: SopListProps) {
  const workspace = useWorkspace((state) => state.workspace);
  const search = useWorkspace((state) => state.ui.search);
  const createItem = useWorkspace((state) => state.createItem);
  const updateItem = useWorkspace((state) => state.updateItem);
  const deleteItems = useWorkspace((state) => state.deleteItems);
  const notify = useWorkspace((state) => state.notify);

  const [creating, setCreating] = useState(false);
  const [draftTitle, setDraftTitle] = useState('');
  const [draftAreaId, setDraftAreaId] = useState('');
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState('');
  const [pendingDelete, setPendingDelete] = useState<Item | null>(null);

  const areaOptions = useMemo(
    () => [
      { value: '', label: '无归属 Area' },
      ...workspace.areas.map((area) => ({ value: area.id, label: area.name })),
    ],
    [workspace.areas],
  );

  const query = search.trim().toLowerCase();
  const visible = useMemo(
    () => (query ? sops.filter((sop) => sop.title.toLowerCase().includes(query)) : sops),
    [query, sops],
  );

  const stepCount = (sopId: string): number =>
    childrenOf(workspace, sopId).filter((child) => child.kind === 'step').length;

  const startCreate = () => {
    setCreating(true);
    setDraftTitle('');
    setDraftAreaId('');
  };

  const cancelCreate = () => {
    setCreating(false);
    setDraftTitle('');
  };

  const commitCreate = () => {
    const title = draftTitle.trim();
    if (!title) {
      cancelCreate();
      return;
    }
    const item = createItem({ kind: 'sop', title, areaId: draftAreaId || null });
    setCreating(false);
    setDraftTitle('');
    setDraftAreaId('');
    onSelect(item.id);
    notify(`已创建 SOP「${title}」`, 'success');
  };

  const startRename = (sop: Item) => {
    setRenamingId(sop.id);
    setRenameValue(sop.title);
  };

  const commitRename = () => {
    if (!renamingId) return;
    const title = renameValue.trim();
    if (title) updateItem(renamingId, { title });
    setRenamingId(null);
    setRenameValue('');
  };

  const confirmDelete = () => {
    if (!pendingDelete) return;
    const title = pendingDelete.title;
    deleteItems([pendingDelete.id]);
    setPendingDelete(null);
    notify(`已删除 SOP「${title}」及其步骤`, 'info');
  };

  return (
    <aside className="sop-list" aria-label="SOP 列表">
      <div className="sop-list-head">
        <span className="sop-list-heading">流程</span>
        <span className="sop-list-count">{sops.length}</span>
        <IconButton label="新建 SOP" size="sm" onClick={startCreate}>
          <Icon name="plus" size={15} />
        </IconButton>
      </div>

      {creating ? (
        <div className="sop-create">
          <TextInput
            autoFocus
            aria-label="新 SOP 名称"
            placeholder="SOP 名称，回车创建"
            value={draftTitle}
            onChange={(event) => setDraftTitle(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter') {
                event.preventDefault();
                commitCreate();
              } else if (event.key === 'Escape') {
                event.preventDefault();
                cancelCreate();
              }
            }}
          />
          <div className="sop-create-row">
            <Select
              aria-label="归属 Area"
              options={areaOptions}
              value={draftAreaId}
              onChange={(event) => setDraftAreaId(event.target.value)}
            />
            <Button size="sm" variant="primary" onClick={commitCreate}>
              创建
            </Button>
            <Button size="sm" variant="ghost" onClick={cancelCreate}>
              取消
            </Button>
          </div>
        </div>
      ) : null}

      <div className="sop-list-scroll">
        {sops.length === 0 ? (
          <EmptyState
            compact
            icon={<Icon name="workflow" size={18} />}
            title="没有 SOP"
            description="SOP = 可执行的流程图：把步骤画成节点，用连线决定下一步。"
            action={
              <Button variant="primary" size="sm" onClick={startCreate}>
                创建第一个 SOP
              </Button>
            }
          />
        ) : visible.length === 0 ? (
          <EmptyState compact title="没有匹配的 SOP" description={`搜索「${search}」无结果。`} />
        ) : (
          <ul className="sop-list-items">
            {visible.map((sop) => {
              const area = sop.areaId ? areaById(workspace, sop.areaId) : undefined;
              const run = latestRun(workspace.runs, sop.id);
              const badge = run ? RUN_BADGE[run.result] : null;
              const active = sop.id === selectedId;

              if (renamingId === sop.id) {
                return (
                  <li key={sop.id} className="sop-list-row sop-list-row--editing">
                    <TextInput
                      autoFocus
                      aria-label="重命名 SOP"
                      value={renameValue}
                      onChange={(event) => setRenameValue(event.target.value)}
                      onBlur={commitRename}
                      onKeyDown={(event) => {
                        if (event.key === 'Enter') {
                          event.preventDefault();
                          commitRename();
                        } else if (event.key === 'Escape') {
                          event.preventDefault();
                          setRenamingId(null);
                          setRenameValue('');
                        }
                      }}
                    />
                  </li>
                );
              }

              return (
                <li key={sop.id} className="sop-list-row" data-active={active ? 'true' : 'false'}>
                  <button
                    type="button"
                    className="sop-list-main"
                    onClick={() => onSelect(sop.id)}
                    onDoubleClick={() => startRename(sop)}
                    aria-current={active ? 'true' : undefined}
                  >
                    <span
                      className="sop-list-area"
                      style={{ background: area?.color ?? 'transparent' }}
                      data-empty={area ? 'false' : 'true'}
                      aria-hidden="true"
                    />
                    <span className="sop-list-text">
                      <span className="sop-list-title">{sop.title}</span>
                      <span className="sop-list-meta">
                        <span className="sop-list-meta-text">
                          {stepCount(sop.id)} 步{area ? ` · ${area.name}` : ''}
                        </span>
                        {badge ? (
                          <Badge tone={badge.tone}>{badge.label}</Badge>
                        ) : (
                          <Badge tone="neutral">未运行</Badge>
                        )}
                      </span>
                    </span>
                  </button>
                  <div className="sop-list-actions">
                    <IconButton
                      label={`重命名 ${sop.title}`}
                      size="sm"
                      onClick={() => startRename(sop)}
                    >
                      <Icon name="edit" size={14} />
                    </IconButton>
                    <IconButton
                      label={`删除 ${sop.title}`}
                      size="sm"
                      variant="danger"
                      onClick={() => setPendingDelete(sop)}
                    >
                      <Icon name="trash" size={14} />
                    </IconButton>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <div className="sop-list-foot">
        <Icon name="edit" size={13} className="sop-list-foot-icon" />
        <span>双击重命名 · 删除会级联清除步骤与连线</span>
      </div>

      <Modal
        open={pendingDelete !== null}
        onClose={() => setPendingDelete(null)}
        title="删除 SOP"
        description="会同时删除其全部步骤、流程连线与运行记录，删除后可用 Ctrl/Cmd+Z 撤销。"
        footer={
          <>
            <Button variant="ghost" onClick={() => setPendingDelete(null)}>
              取消
            </Button>
            <Button variant="danger" onClick={confirmDelete}>
              删除
            </Button>
          </>
        }
      >
        <p className="sop-modal-text">
          确认删除「{pendingDelete?.title ?? ''}」？共 {pendingDelete ? stepCount(pendingDelete.id) : 0}{' '}
          个步骤。
        </p>
      </Modal>
    </aside>
  );
}
