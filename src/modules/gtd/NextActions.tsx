import { memo, useCallback, useMemo, useState } from 'react';
import type { Area, Item, ItemPatch } from '../../core/model';
import { getWorkspaceIndex, itemById } from '../../core/selectors';
import { getWorkspace, useWorkspace } from '../../core/store';
import { dateKey } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Select, TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { IconButton } from '../../ui/IconButton';
import {
  LIST_PAGE_SIZE,
  NO_CONTEXT,
  NO_CONTEXT_FILTER,
  PRESET_CONTEXTS,
  buildPathTitleIndex,
  contextOf,
  deadlineInfo,
  ENERGY_LABELS,
  filterNextActions,
  groupByContext,
  nextPage,
  paginateItems,
  resolvePageLimit,
  sortNextActions,
} from './gtdLogic';
import type { ContextGroup, PaginationState } from './gtdLogic';
import { useRowKeyboard } from './useRowKeyboard';

export interface NextActionsProps {
  items: Item[];
  today: string;
  onClarify: (item: Item) => void;
}

/** 组织 + 执行：按场景分组、可折叠的下一步列表。 */
export function NextActions({ items, today, onClarify }: NextActionsProps) {
  const workspace = useWorkspace((state) => state.workspace);
  const gtdContext = useWorkspace((state) => state.ui.gtdContext);
  const search = useWorkspace((state) => state.ui.search);
  const setUi = useWorkspace((state) => state.setUi);
  const updateItem = useWorkspace((state) => state.updateItem);

  const [dueSoonOnly, setDueSoonOnly] = useState(false);
  const [areaFilter, setAreaFilter] = useState('');
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draft, setDraft] = useState('');

  const contextOptions = useMemo(() => {
    const present = [
      ...new Set(
        items.map((item) => contextOf(item)).filter((value): value is string => Boolean(value)),
      ),
    ];
    const custom = present
      .filter((context) => !(PRESET_CONTEXTS as readonly string[]).includes(context))
      .sort();
    const hasNone = items.some((item) => !contextOf(item));
    const current = gtdContext;
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
  }, [items, gtdContext]);

  const filtered = useMemo(() => {
    const result = filterNextActions(items, {
      context: gtdContext,
      dueSoonOnly,
      areaId: areaFilter || null,
      search,
      today,
    });
    return sortNextActions(result);
  }, [items, gtdContext, search, dueSoonOnly, areaFilter, today]);

  const groups = useMemo(() => groupByContext(filtered), [filtered]);
  const groupTotals = useMemo(
    () => new Map(groups.map((group) => [group.context, group.items.length])),
    [groups],
  );

  // 分页 key：筛选 / 搜索 / 分组折叠任一变化都回到第一页。
  const collapsedKey = useMemo(() => [...collapsed].sort().join('\u0000'), [collapsed]);
  const pageKey = `${gtdContext ?? ''}|${search}|${dueSoonOnly ? '1' : '0'}|${areaFilter}|${today}|${collapsedKey}`;
  const [page, setPage] = useState<PaginationState>({ key: pageKey, limit: LIST_PAGE_SIZE });
  // key 变化时同步重置（派生 state，避免切回旧筛选时复用旧页数）。
  if (page.key !== pageKey) setPage({ key: pageKey, limit: LIST_PAGE_SIZE });
  const limit = resolvePageLimit(page, pageKey);

  const flatVisible = useMemo(
    () => filtered.filter((item) => !collapsed.has(contextOf(item) ?? NO_CONTEXT)),
    [filtered, collapsed],
  );
  const slice = useMemo(() => paginateItems(flatVisible, limit), [flatVisible, limit]);
  const pageGroups = useMemo(() => groupByContext(slice.items), [slice.items]);
  const visibleItems = useMemo(
    () => pageGroups.flatMap((group) => group.items),
    [pageGroups],
  );
  const visibleIds = useMemo(() => visibleItems.map((item) => item.id), [visibleItems]);

  const pathIndex = useMemo(
    () => buildPathTitleIndex(workspace, slice.items),
    [workspace, slice.items],
  );
  const areas = useMemo(() => getWorkspaceIndex(workspace).areas, [workspace]);

  const { activeId, setActiveId, onKeyDown } = useRowKeyboard({
    ids: visibleIds,
    onDone: (id) => {
      const item = visibleItems.find((entry) => entry.id === id);
      if (!item) return;
      const store = getWorkspace();
      store.toggleDone(item.id);
      store.notify(`已完成「${item.title}」`, 'success');
    },
    onEnter: (id) => {
      const item = visibleItems.find((entry) => entry.id === id);
      if (item) onClarify(item);
    },
  });

  const toggleGroup = useCallback((context: string) => {
    setCollapsed((current) => {
      const next = new Set(current);
      if (next.has(context)) next.delete(context);
      else next.add(context);
      return next;
    });
  }, []);

  const startEdit = useCallback((item: Item) => {
    setEditingId(item.id);
    setDraft(item.title);
  }, []);

  const cancelEdit = useCallback(() => {
    setEditingId(null);
    setDraft('');
  }, []);

  const commitTitle = useCallback((item: Item, value: string) => {
    const title = value.trim();
    // Enter 与 blur 可能连续触发：以 store 里的最新标题判重，避免重复写入。
    const current = itemById(getWorkspace().workspace, item.id) ?? item;
    if (title && title !== current.title) {
      const store = getWorkspace();
      store.updateItem(item.id, { title });
      store.notify('标题已更新', 'success');
    }
    setEditingId(null);
    setDraft('');
  }, []);

  const toggleDone = useCallback((item: Item) => {
    const store = getWorkspace();
    store.toggleDone(item.id);
    store.notify(`已完成「${item.title}」`, 'success');
  }, []);

  const showMore = useCallback(() => {
    setPage((current) => nextPage(current, pageKey));
  }, [pageKey]);

  const resetFilters = useCallback(() => {
    setDueSoonOnly(false);
    setAreaFilter('');
    setUi({ gtdContext: null, search: '' });
  }, [setUi]);

  const areaOptions = useMemo(
    () => [
      { value: '', label: '全部领域' },
      ...workspace.areas.map((area) => ({ value: area.id, label: area.name })),
    ],
    [workspace.areas],
  );

  return (
    <>
      <div className="gtd-filterbar">
        <Select
          aria-label="按场景筛选"
          value={gtdContext ?? ''}
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
            description={search ? `当前搜索「${search}」没有命中。` : '调整筛选，或去收件箱澄清新事项。'}
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
          {pageGroups.map((group) => (
            <ContextSection
              key={group.context}
              group={group}
              total={groupTotals.get(group.context) ?? group.items.length}
              collapsed={collapsed.has(group.context)}
              onToggle={toggleGroup}
              activeId={activeId}
              onActivate={setActiveId}
              today={today}
              editingId={editingId}
              draft={draft}
              onStartEdit={startEdit}
              onDraftChange={setDraft}
              onCommitTitle={commitTitle}
              onCancelEdit={cancelEdit}
              onToggleDone={toggleDone}
              onClarify={onClarify}
              areas={areas}
              parentText={pathIndex.parentText}
              updateItem={updateItem}
            />
          ))}
          {slice.remaining > 0 ? (
            <div className="gtd-show-more">
              <button type="button" className="gtd-linkbtn" onClick={showMore}>
                显示更多（剩余 {slice.remaining} 条）
              </button>
              <span className="gtd-show-more-note">
                已显示 {slice.shown} / {slice.total} 条
              </span>
            </div>
          ) : null}
        </div>
      )}
    </>
  );
}

interface ContextSectionProps {
  group: ContextGroup;
  /** 该场景在筛选结果里的总条数（可能大于本页渲染条数）。 */
  total: number;
  collapsed: boolean;
  onToggle: (context: string) => void;
  activeId: string | null;
  onActivate: (id: string) => void;
  today: string;
  editingId: string | null;
  draft: string;
  onStartEdit: (item: Item) => void;
  onDraftChange: (value: string) => void;
  onCommitTitle: (item: Item, value: string) => void;
  onCancelEdit: () => void;
  onToggleDone: (item: Item) => void;
  onClarify: (item: Item) => void;
  areas: Map<string, Area>;
  parentText: Map<string, string>;
  updateItem: (id: string, patch: ItemPatch) => void;
}

function ContextSection({
  group,
  total,
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
  areas,
  parentText,
  updateItem,
}: ContextSectionProps) {
  return (
    <div className="gtd-group">
      <button
        type="button"
        className="gtd-group-header"
        aria-expanded={!collapsed}
        onClick={() => onToggle(group.context)}
      >
        <span className={`gtd-chevron${collapsed ? '' : ' gtd-chevron--open'}`} aria-hidden="true">
          <Icon name="chevron-right" size={13} />
        </span>
        <span className="gtd-group-title">@{group.context}</span>
        <span
          className="gtd-group-count"
          title={`本页显示 ${group.items.length} 条 · 共 ${total} 条`}
        >
          {total}
        </span>
      </button>

      {collapsed ? null : (
        <div className="gtd-group-items" role="list">
          {group.items.map((item) => (
            <NextActionRow
              key={item.id}
              item={item}
              active={activeId === item.id}
              editing={editingId === item.id}
              draft={editingId === item.id ? draft : ''}
              breadcrumb={parentText.get(item.id) ?? ''}
              area={item.areaId ? areas.get(item.areaId) : undefined}
              today={today}
              onActivate={onActivate}
              onStartEdit={onStartEdit}
              onDraftChange={onDraftChange}
              onCommitTitle={onCommitTitle}
              onCancelEdit={onCancelEdit}
              onToggleDone={onToggleDone}
              onClarify={onClarify}
              updateItem={updateItem}
            />
          ))}
        </div>
      )}
    </div>
  );
}

interface NextActionRowProps {
  item: Item;
  active: boolean;
  editing: boolean;
  draft: string;
  /** 列表级预先构建好的面包屑文本（根 → 父级）。 */
  breadcrumb: string;
  area: Area | undefined;
  today: string;
  onActivate: (id: string) => void;
  onStartEdit: (item: Item) => void;
  onDraftChange: (value: string) => void;
  onCommitTitle: (item: Item, value: string) => void;
  onCancelEdit: () => void;
  onToggleDone: (item: Item) => void;
  onClarify: (item: Item) => void;
  updateItem: (id: string, patch: ItemPatch) => void;
}

/**
 * 下一步的单行。props 只包含 item（引用稳定）与原始值 / 稳定回调，
 * 因此编辑或高亮某一行时，其余行会被 React.memo 直接跳过。
 */
const NextActionRow = memo(function NextActionRow({
  item,
  active,
  editing,
  draft,
  breadcrumb,
  area,
  today,
  onActivate,
  onStartEdit,
  onDraftChange,
  onCommitTitle,
  onCancelEdit,
  onToggleDone,
  onClarify,
  updateItem,
}: NextActionRowProps) {
  const context = contextOf(item);
  const due = deadlineInfo(item, today);
  const contextOptions = [
    { value: '', label: `@${NO_CONTEXT}` },
    ...PRESET_CONTEXTS.map((entry) => ({ value: entry, label: `@${entry}` })),
    ...(context && !(PRESET_CONTEXTS as readonly string[]).includes(context)
      ? [{ value: context, label: `@${context}` }]
      : []),
  ];

  return (
    <div
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
              onBlur={() => onCommitTitle(item, draft)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') {
                  event.preventDefault();
                  onCommitTitle(item, draft);
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
          {breadcrumb ? (
            <span className="gtd-breadcrumb" title={breadcrumb}>
              <Icon name="folder" size={12} />
              {breadcrumb}
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
          options={contextOptions}
          onChange={(event) => updateItem(item.id, { gtd: { context: event.target.value } })}
        />
        <TextInput
          type="date"
          aria-label={`修改「${item.title}」的截止日期`}
          className="gtd-inline-date"
          value={dateKey(item.gantt?.end) ?? ''}
          onChange={(event) => updateItem(item.id, { gantt: { end: event.target.value || null } })}
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
});
