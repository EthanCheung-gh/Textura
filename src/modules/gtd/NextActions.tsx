import { useMemo, useState } from 'react';
import type { Item, ItemPatch, Workspace } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { areaById, itemPathTitles } from '../../core/selectors';
import { dateKey } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Select, TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { IconButton } from '../../ui/IconButton';
import {
  NO_CONTEXT,
  NO_CONTEXT_FILTER,
  PRESET_CONTEXTS,
  contextOf,
  deadlineInfo,
  ENERGY_LABELS,
  filterNextActions,
  groupByContext,
  sortNextActions,
} from './gtdLogic';
import type { ContextGroup } from './gtdLogic';
import { useRowKeyboard } from './useRowKeyboard';

export interface NextActionsProps {
  items: Item[];
  today: string;
  onClarify: (item: Item) => void;
}

/** 组织 + 执行：按场景分组、可折叠的下一步列表。 */
export function NextActions({ items, today, onClarify }: NextActionsProps) {
  const workspace = useWorkspace((state) => state.workspace);
  const ui = useWorkspace((state) => state.ui);
  const setUi = useWorkspace((state) => state.setUi);
  const updateItem = useWorkspace((state) => state.updateItem);
  const toggleDone = useWorkspace((state) => state.toggleDone);
  const notify = useWorkspace((state) => state.notify);

  const [dueSoonOnly, setDueSoonOnly] = useState(false);
  const [areaFilter, setAreaFilter] = useState('');
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draft, setDraft] = useState('');

  const contextOptions = useMemo(() => {
    const present = [...new Set(items.map((item) => contextOf(item)).filter((value): value is string => Boolean(value)))];
    const custom = present.filter((context) => !(PRESET_CONTEXTS as readonly string[]).includes(context)).sort();
    const hasNone = items.some((item) => !contextOf(item));
    const current = ui.gtdContext;
    const extra =
      current &&
      current !== NO_CONTEXT_FILTER &&
      !(PRESET_CONTEXTS as readonly string[]).includes(current) &&
      !present.includes(current)
        ? [{ value: current, label: `@${current}` }]
        : [];
    return [
      { value: '', label: '全部场景' },
      ...PRESET_CONTEXTS.map((context) => ({ value: context, label: `@${context}` })),
      ...custom.map((context) => ({ value: context, label: `@${context}` })),
      ...extra,
      ...(hasNone || current === NO_CONTEXT_FILTER
        ? [{ value: NO_CONTEXT_FILTER, label: `@${NO_CONTEXT}` }]
        : []),
    ];
  }, [items, ui.gtdContext]);

  const filtered = useMemo(() => {
    const result = filterNextActions(items, {
      context: ui.gtdContext,
      dueSoonOnly,
      areaId: areaFilter || null,
      search: ui.search,
      today,
    });
    return sortNextActions(result);
  }, [items, ui.gtdContext, ui.search, dueSoonOnly, areaFilter, today]);

  const groups = useMemo(() => groupByContext(filtered), [filtered]);
  const visibleItems = useMemo(
    () => groups.filter((group) => !collapsed.has(group.context)).flatMap((group) => group.items),
    [groups, collapsed],
  );
  const visibleIds = useMemo(() => visibleItems.map((item) => item.id), [visibleItems]);
  const { activeId, setActiveId, onKeyDown } = useRowKeyboard({
    ids: visibleIds,
    onDone: (id) => {
      const item = visibleItems.find((entry) => entry.id === id);
      if (!item) return;
      toggleDone(item.id);
      notify(`已完成「${item.title}」`, 'success');
    },
    onEnter: (id) => {
      const item = visibleItems.find((entry) => entry.id === id);
      if (item) onClarify(item);
    },
  });

  const toggleGroup = (context: string) => {
    setCollapsed((current) => {
      const next = new Set(current);
      if (next.has(context)) next.delete(context);
      else next.add(context);
      return next;
    });
  };

  const commitTitle = (item: Item) => {
    const title = draft.trim();
    if (title && title !== item.title) {
      updateItem(item.id, { title });
      notify('标题已更新', 'success');
    }
    setEditingId(null);
    setDraft('');
  };

  const resetFilters = () => {
    setDueSoonOnly(false);
    setAreaFilter('');
    setUi({ gtdContext: null, search: '' });
  };

  const areaOptions = [
    { value: '', label: '全部领域' },
    ...workspace.areas.map((area) => ({ value: area.id, label: area.name })),
  ];

  return (
    <>
      <div className="gtd-filterbar">
        <Select
          aria-label="按场景筛选"
          value={ui.gtdContext ?? ''}
          options={contextOptions}
          onChange={(event) => setUi({ gtdContext: event.target.value || null })}
          className="gtd-filter-select"
        />
        <label className="gtd-toggle">
          <input
            type="checkbox"
            checked={dueSoonOnly}
            onChange={(event) => setDueSoonOnly(event.target.checked)}
          />
          <span>仅今天/超期</span>
        </label>
        <Select
          aria-label="按领域筛选"
          value={areaFilter}
          options={areaOptions}
          onChange={(event) => setAreaFilter(event.target.value)}
          className="gtd-filter-select"
        />
        <span className="gtd-filter-count">
          {filtered.length} / {items.length}
        </span>
      </div>

      {filtered.length === 0 ? (
        <div className="gtd-section-body gtd-empty-body">
          <EmptyState
            icon={<Icon name="search" size={20} />}
            title="没有符合条件的下一步"
            description={ui.search ? `当前搜索「${ui.search}」没有命中。` : '调整筛选，或去收件箱澄清新事项。'}
            action={
              <Button variant="secondary" size="sm" onClick={resetFilters}>
                清空筛选
              </Button>
            }
            compact
          />
        </div>
      ) : (
        <div
          className="gtd-rows gtd-group-rows"
          role="list"
          aria-label="下一步行动"
          tabIndex={0}
          onKeyDown={onKeyDown}
          onFocus={() => {
            if (!activeId && visibleItems[0]) setActiveId(visibleItems[0].id);
          }}
        >
          {groups.map((group) => (
            <ContextSection
              key={group.context}
              group={group}
              collapsed={collapsed.has(group.context)}
              onToggle={() => toggleGroup(group.context)}
              activeId={activeId}
              onActivate={setActiveId}
              today={today}
              editingId={editingId}
              draft={draft}
              onStartEdit={(item) => {
                setEditingId(item.id);
                setDraft(item.title);
              }}
              onDraftChange={setDraft}
              onCommitTitle={commitTitle}
              onCancelEdit={() => {
                setEditingId(null);
                setDraft('');
              }}
              onToggleDone={(item) => {
                toggleDone(item.id);
                notify(`已完成「${item.title}」`, 'success');
              }}
              onClarify={onClarify}
              workspace={workspace}
              updateItem={updateItem}
            />
          ))}
        </div>
      )}
    </>
  );
}

interface ContextSectionProps {
  group: ContextGroup;
  collapsed: boolean;
  onToggle: () => void;
  activeId: string | null;
  onActivate: (id: string) => void;
  today: string;
  editingId: string | null;
  draft: string;
  onStartEdit: (item: Item) => void;
  onDraftChange: (value: string) => void;
  onCommitTitle: (item: Item) => void;
  onCancelEdit: () => void;
  onToggleDone: (item: Item) => void;
  onClarify: (item: Item) => void;
  workspace: Workspace;
  updateItem: (id: string, patch: ItemPatch) => void;
}

function ContextSection({
  group,
  collapsed,
  onToggle,
  activeId,
  onActivate,
  today,
  editingId,
  draft,
  onStartEdit,
  onDraftChange,
  onCommitTitle,
  onCancelEdit,
  onToggleDone,
  onClarify,
  workspace,
  updateItem,
}: ContextSectionProps) {
  return (
    <div className="gtd-group">
      <button
        type="button"
        className="gtd-group-header"
        aria-expanded={!collapsed}
        onClick={onToggle}
      >
        <span className={`gtd-chevron${collapsed ? '' : ' gtd-chevron--open'}`} aria-hidden="true">
          <Icon name="chevron-right" size={13} />
        </span>
        <span className="gtd-group-title">@{group.context}</span>
        <span className="gtd-group-count">{group.items.length}</span>
      </button>

      {collapsed ? null : (
        <div className="gtd-group-items" role="list">
          {group.items.map((item) => {
            const context = contextOf(item);
            const area = item.areaId ? areaById(workspace, item.areaId) : undefined;
            const path = itemPathTitles(workspace, item.id).slice(0, -1);
            const due = deadlineInfo(item, today);
            const active = activeId === item.id;
            const editing = editingId === item.id;
            return (
              <div
                key={item.id}
                className="gtd-row gtd-next-row"
                data-active={active ? 'true' : 'false'}
                data-row-id={item.id}
                role="listitem"
                onMouseEnter={() => onActivate(item.id)}
              >
                <button
                  type="button"
                  className="gtd-check"
                  aria-label={`完成「${item.title}」`}
                  onClick={() => onToggleDone(item)}
                >
                  <Icon name="check" size={12} />
                </button>

                <div className="gtd-next-body">
                  <div className="gtd-next-titleline">
                    {editing ? (
                      <TextInput
                        autoFocus
                        className="gtd-title-input"
                        value={draft}
                        aria-label="编辑标题"
                        onChange={(event) => onDraftChange(event.target.value)}
                        onBlur={() => onCommitTitle(item)}
                        onKeyDown={(event) => {
                          if (event.key === 'Enter') {
                            event.preventDefault();
                            onCommitTitle(item);
                          } else if (event.key === 'Escape') {
                            event.preventDefault();
                            onCancelEdit();
                          }
                        }}
                      />
                    ) : (
                      <button
                        type="button"
                        className="gtd-row-title"
                        title="点击编辑标题"
                        aria-label={`编辑标题「${item.title}」`}
                        onClick={() => onStartEdit(item)}
                      >
                        {item.title}
                      </button>
                    )}
                    {path.length > 0 ? (
                      <span className="gtd-breadcrumb" title={path.join(' / ')}>
                        <Icon name="folder" size={12} />
                        {path.join(' / ')}
                      </span>
                    ) : null}
                  </div>

                  <div className="gtd-row-meta">
                    <span className={`gtd-deadline gtd-deadline--${due.tone}`}>
                      <Icon name="calendar" size={12} />
                      {due.label}
                    </span>
                    <Badge tone="info">@{context ?? NO_CONTEXT}</Badge>
                    <Badge tone="neutral">能量 {ENERGY_LABELS[item.gtd?.energy ?? 'medium']}</Badge>
                    {area ? (
                      <span className="gtd-area">
                        <span className="gtd-area-dot" style={{ background: area.color }} />
                        {area.name}
                      </span>
                    ) : null}
                  </div>
                </div>

                <div className="gtd-inline-controls">
                  <Select
                    aria-label={`修改「${item.title}」的场景`}
                    className="gtd-inline-select"
                    value={context ?? ''}
                    options={[
                      { value: '', label: `@${NO_CONTEXT}` },
                      ...PRESET_CONTEXTS.map((entry) => ({ value: entry, label: `@${entry}` })),
                      ...(context && !(PRESET_CONTEXTS as readonly string[]).includes(context)
                        ? [{ value: context, label: `@${context}` }]
                        : []),
                    ]}
                    onChange={(event) => updateItem(item.id, { gtd: { context: event.target.value } })}
                  />
                  <TextInput
                    type="date"
                    aria-label={`修改「${item.title}」的截止日期`}
                    className="gtd-inline-date"
                    value={dateKey(item.gantt?.end) ?? ''}
                    onChange={(event) =>
                      updateItem(item.id, { gantt: { end: event.target.value || null } })
                    }
                  />
                  <IconButton
                    label={`打开「${item.title}」的澄清面板`}
                    size="sm"
                    onClick={() => onClarify(item)}
                  >
                    <Icon name="edit" size={13} />
                  </IconButton>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
