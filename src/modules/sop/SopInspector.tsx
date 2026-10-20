/** 右栏检查器：节点 / 连线 / SOP 级设置。 */
import { useEffect, useRef, useState } from 'react';
import type { InputHTMLAttributes, TextareaHTMLAttributes } from 'react';
import type { ChecklistEntry, Edge, Item, SopNodeType } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { areaById, rollupProgress } from '../../core/selectors';
import { formatDateTime, uid } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { Field, Select, TextArea, TextInput } from '../../ui/Field';
import { IconButton } from '../../ui/IconButton';
import { Icon } from '../../ui/icons';
import { Progress } from '../../ui/Progress';
import { NODE_TYPE_LABELS } from './SopNode';
import type { SopSelection } from './types';

const NODE_TYPE_OPTIONS = (Object.keys(NODE_TYPE_LABELS) as SopNodeType[]).map((value) => ({
  value,
  label: `${NODE_TYPE_LABELS[value]}（${value}）`,
}));

const EDGE_LABEL_PRESETS = ['是', '否', '通过', '补充', '继续'];

interface DraftInputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'> {
  value: string;
  onCommit: (value: string) => void;
}

/** 失焦 / 回车才写回 store，避免每次按键都产生一次 history 与自动保存。 */
function DraftInput({ value, onCommit, onKeyDown, ...rest }: DraftInputProps) {
  const [draft, setDraft] = useState(value);
  const cancelled = useRef(false);

  useEffect(() => {
    setDraft(value);
  }, [value]);

  return (
    <TextInput
      {...rest}
      value={draft}
      onChange={(event) => setDraft(event.target.value)}
      onBlur={() => {
        if (cancelled.current) {
          cancelled.current = false;
          setDraft(value);
          return;
        }
        const next = draft.trim();
        if (next !== value) onCommit(next);
      }}
      onKeyDown={(event) => {
        if (event.key === 'Enter') {
          event.preventDefault();
          event.currentTarget.blur();
        } else if (event.key === 'Escape') {
          event.preventDefault();
          cancelled.current = true;
          event.currentTarget.blur();
        }
        onKeyDown?.(event);
      }}
    />
  );
}

interface DraftTextAreaProps
  extends Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, 'value' | 'onChange'> {
  value: string;
  onCommit: (value: string) => void;
}

function DraftTextArea({ value, onCommit, rows = 3, ...rest }: DraftTextAreaProps) {
  const [draft, setDraft] = useState(value);
  const cancelled = useRef(false);

  useEffect(() => {
    setDraft(value);
  }, [value]);

  return (
    <TextArea
      {...rest}
      rows={rows}
      value={draft}
      onChange={(event) => setDraft(event.target.value)}
      onBlur={() => {
        if (cancelled.current) {
          cancelled.current = false;
          setDraft(value);
          return;
        }
        if (draft !== value) onCommit(draft);
      }}
      onKeyDown={(event) => {
        if (event.key === 'Escape') {
          event.preventDefault();
          cancelled.current = true;
          event.currentTarget.blur();
        }
      }}
    />
  );
}

export interface SopInspectorProps {
  sop: Item;
  nodes: Item[];
  edges: Edge[];
  selection: SopSelection;
  onSelect: (selection: SopSelection) => void;
  onDeleteSelection: () => void;
}

export function SopInspector({
  sop,
  nodes,
  edges,
  selection,
  onSelect,
  onDeleteSelection,
}: SopInspectorProps) {
  const workspace = useWorkspace((state) => state.workspace);
  const updateItem = useWorkspace((state) => state.updateItem);
  const updateEdge = useWorkspace((state) => state.updateEdge);
  const deleteEdge = useWorkspace((state) => state.deleteEdge);

  const selectedNode = selection?.kind === 'node' ? nodes.find((item) => item.id === selection.id) : null;
  const selectedEdge = selection?.kind === 'edge' ? edges.find((edge) => edge.id === selection.id) : null;

  const areaOptions = [
    { value: '', label: '无归属 Area' },
    ...workspace.areas.map((area) => ({ value: area.id, label: area.name })),
  ];

  if (selectedNode) {
    const checklist = selectedNode.sop?.checklist ?? [];
    const area = selectedNode.areaId ? areaById(workspace, selectedNode.areaId) : undefined;
    const commitChecklist = (next: ChecklistEntry[]) =>
      updateItem(selectedNode.id, { sop: { checklist: next } });

    return (
      <div className="sop-inspector">
        <div className="sop-inspector-head">
          <div>
            <span className="sop-inspector-eyebrow">节点</span>
            <h2 className="sop-inspector-title">{selectedNode.title}</h2>
          </div>
          <Badge tone="accent">
            {NODE_TYPE_LABELS[selectedNode.sop?.nodeType ?? 'action']}
          </Badge>
        </div>

        <div className="sop-inspector-body">
          <Field label="标题" htmlFor="sop-node-title">
            <DraftInput
              id="sop-node-title"
              value={selectedNode.title}
              onCommit={(value) => {
                if (value) updateItem(selectedNode.id, { title: value });
              }}
            />
          </Field>

          <Field label="说明" htmlFor="sop-node-notes">
            <DraftTextArea
              id="sop-node-notes"
              rows={3}
              value={selectedNode.notes}
              placeholder="这一步要做什么、注意什么…"
              onCommit={(value) => updateItem(selectedNode.id, { notes: value })}
            />
          </Field>

          <div className="sop-field-grid">
            <Field label="类型" htmlFor="sop-node-type">
              <Select
                id="sop-node-type"
                options={NODE_TYPE_OPTIONS}
                value={selectedNode.sop?.nodeType ?? 'action'}
                onChange={(event) =>
                  updateItem(selectedNode.id, {
                    sop: { nodeType: event.target.value as SopNodeType },
                  })
                }
              />
            </Field>
            <Field label="负责人" htmlFor="sop-node-owner">
              <DraftInput
                id="sop-node-owner"
                placeholder="谁来做"
                value={selectedNode.sop?.owner ?? ''}
                onCommit={(value) => updateItem(selectedNode.id, { sop: { owner: value } })}
              />
            </Field>
          </div>

          <div className="sop-field-grid">
            <Field label="预计耗时（分钟）" htmlFor="sop-node-duration">
              <DraftInput
                id="sop-node-duration"
                inputMode="numeric"
                placeholder="5"
                value={
                  selectedNode.sop?.durationMin === undefined
                    ? ''
                    : String(selectedNode.sop.durationMin)
                }
                onCommit={(value) => {
                  const parsed = Number.parseInt(value, 10);
                  updateItem(selectedNode.id, {
                    sop: { durationMin: Number.isFinite(parsed) && parsed > 0 ? parsed : 0 },
                  });
                }}
              />
            </Field>
            <Field label="Area" htmlFor="sop-node-area">
              <Select
                id="sop-node-area"
                options={areaOptions}
                value={area?.id ?? ''}
                onChange={(event) =>
                  updateItem(selectedNode.id, { areaId: event.target.value || null })
                }
              />
            </Field>
          </div>

          <Field label="标签" htmlFor="sop-node-tags" hint="用逗号分隔">
            <DraftInput
              id="sop-node-tags"
              value={selectedNode.tags.join(', ')}
              placeholder="onboarding, 邮件"
              onCommit={(value) =>
                updateItem(selectedNode.id, {
                  tags: value
                    .split(/[,，\s]+/)
                    .map((tag) => tag.trim())
                    .filter(Boolean),
                })
              }
            />
          </Field>

          <div className="sop-checklists">
            <div className="sop-checklists-head">
              <span className="sop-section-label">检查项</span>
              <span className="sop-checklists-count">
                {checklist.filter((entry) => entry.done).length}/{checklist.length}
              </span>
              <IconButton
                label="添加检查项"
                size="sm"
                onClick={() =>
                  commitChecklist([
                    ...checklist,
                    { id: uid('chk'), text: '新检查项', done: false },
                  ])
                }
              >
                <Icon name="plus" size={14} />
              </IconButton>
            </div>
            {checklist.length === 0 ? (
              <p className="sop-hint">还没有检查项。检查项会显示在节点进度条与运行条里。</p>
            ) : (
              <ul className="sop-checklist">
                {checklist.map((entry) => (
                  <li key={entry.id} className="sop-checklist-item" data-done={entry.done ? 'true' : 'false'}>
                    <input
                      type="checkbox"
                      className="sop-checkbox"
                      checked={entry.done}
                      aria-label={`标记「${entry.text}」`}
                      onChange={(event) =>
                        commitChecklist(
                          checklist.map((item) =>
                            item.id === entry.id ? { ...item, done: event.target.checked } : item,
                          ),
                        )
                      }
                    />
                    <DraftInput
                      aria-label="检查项内容"
                      value={entry.text}
                      onCommit={(value) =>
                        commitChecklist(
                          checklist.map((item) =>
                            item.id === entry.id
                              ? { ...item, text: value || item.text }
                              : item,
                          ),
                        )
                      }
                    />
                    <IconButton
                      label={`删除检查项 ${entry.text}`}
                      size="sm"
                      variant="danger"
                      onClick={() =>
                        commitChecklist(checklist.filter((item) => item.id !== entry.id))
                      }
                    >
                      <Icon name="close" size={13} />
                    </IconButton>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="sop-inspector-danger">
            <Button
              variant="danger"
              size="sm"
              iconLeft={<Icon name="trash" size={14} />}
              onClick={onDeleteSelection}
            >
              删除节点
            </Button>
          </div>
        </div>
      </div>
    );
  }

  if (selectedEdge) {
    const from = nodes.find((item) => item.id === selectedEdge.from);
    const to = nodes.find((item) => item.id === selectedEdge.to);

    return (
      <div className="sop-inspector">
        <div className="sop-inspector-head">
          <div>
            <span className="sop-inspector-eyebrow">连线</span>
            <h2 className="sop-inspector-title">分支文案</h2>
          </div>
          <Badge tone="info">flow</Badge>
        </div>

        <div className="sop-inspector-body">
          <p className="sop-hint">
            {from?.title ?? '未知'} → {to?.title ?? '未知'}
          </p>

          <Field label="标签" htmlFor="sop-edge-label" hint="判断节点的出边靠标签区分分支">
            <DraftInput
              id="sop-edge-label"
              value={selectedEdge.label}
              placeholder="例如：是 / 否 / 补充"
              onCommit={(value) => updateEdge(selectedEdge.id, { label: value })}
            />
          </Field>

          <div className="sop-preset-row">
            {EDGE_LABEL_PRESETS.map((label) => (
              <Button
                key={label}
                size="sm"
                variant={selectedEdge.label === label ? 'primary' : 'secondary'}
                onClick={() => updateEdge(selectedEdge.id, { label })}
              >
                {label}
              </Button>
            ))}
          </div>

          <div className="sop-inspector-danger">
            <Button
              variant="danger"
              size="sm"
              iconLeft={<Icon name="trash" size={14} />}
              onClick={() => {
                deleteEdge(selectedEdge.id);
                onSelect(null);
              }}
            >
              删除连线
            </Button>
          </div>
        </div>
      </div>
    );
  }

  const stepCounts = new Map<SopNodeType, number>();
  for (const node of nodes) {
    const type = node.sop?.nodeType ?? 'action';
    stepCounts.set(type, (stepCounts.get(type) ?? 0) + 1);
  }
  const latestRun = workspace.runs
    .filter((run) => run.sopId === sop.id)
    .sort((a, b) => b.at.localeCompare(a.at))[0];
  const latestStep = latestRun ? nodes.find((node) => node.id === latestRun.stepId) : undefined;

  return (
    <div className="sop-inspector">
      <div className="sop-inspector-head">
        <div>
          <span className="sop-inspector-eyebrow">SOP 设置</span>
          <h2 className="sop-inspector-title">{sop.title}</h2>
        </div>
        <Badge tone="neutral">{nodes.length} 步</Badge>
      </div>

      <div className="sop-inspector-body">
        <Field label="名称" htmlFor="sop-title">
          <DraftInput
            id="sop-title"
            value={sop.title}
            onCommit={(value) => {
              if (value) updateItem(sop.id, { title: value });
            }}
          />
        </Field>

        <Field label="描述" htmlFor="sop-notes">
          <DraftTextArea
            id="sop-notes"
            rows={3}
            value={sop.notes}
            placeholder="这个流程解决什么问题、适用范围…"
            onCommit={(value) => updateItem(sop.id, { notes: value })}
          />
        </Field>

        <div className="sop-field-grid">
          <Field label="默认负责人" htmlFor="sop-owner">
            <DraftInput
              id="sop-owner"
              placeholder="未指定"
              value={sop.sop?.owner ?? ''}
              onCommit={(value) => updateItem(sop.id, { sop: { owner: value } })}
            />
          </Field>
          <Field label="Area" htmlFor="sop-area">
            <Select
              id="sop-area"
              options={areaOptions}
              value={sop.areaId ?? ''}
              onChange={(event) => updateItem(sop.id, { areaId: event.target.value || null })}
            />
          </Field>
        </div>

        <div className="sop-stats">
          <div className="sop-stats-head">
            <span className="sop-section-label">步骤统计</span>
            <span className="sop-stats-value">{nodes.length} 个节点 · {edges.length} 条连线</span>
          </div>
          <Progress value={rollupProgress(workspace, sop.id)} tone="accent" size="sm" showLabel />
          <div className="sop-stats-types">
            {(Object.keys(NODE_TYPE_LABELS) as SopNodeType[])
              .filter((type) => stepCounts.has(type))
              .map((type) => (
                <Badge key={type} tone="neutral">
                  {NODE_TYPE_LABELS[type]} {stepCounts.get(type)}
                </Badge>
              ))}
            {nodes.length === 0 ? <span className="sop-hint">画布还是空的。</span> : null}
          </div>
          <p className="sop-hint">拖动节点移动 · 拖动圆点连线 · Delete 删除选中</p>
        </div>

        <div className="sop-recent">
          <div className="sop-stats-head">
            <span className="sop-section-label">最近运行</span>
            {latestRun ? (
              <span className="sop-stats-value">{formatDateTime(latestRun.at)}</span>
            ) : null}
          </div>
          {latestRun ? (
            <div className="sop-recent-summary">
              <span className="sop-recent-step">{latestStep?.title ?? '已删除步骤'}</span>
              <Badge
                tone={
                  latestRun.result === 'pass'
                    ? 'ok'
                    : latestRun.result === 'fail'
                      ? 'danger'
                      : 'warn'
                }
              >
                {latestRun.result === 'pass'
                  ? '通过'
                  : latestRun.result === 'fail'
                    ? '未通过'
                    : '跳过'}
              </Badge>
            </div>
          ) : (
            <p className="sop-hint">还没有运行记录。点画布工具栏的「运行」开始逐步执行。</p>
          )}
        </div>
      </div>
    </div>
  );
}
