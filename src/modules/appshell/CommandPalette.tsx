import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import type { ItemKind, Workspace } from '../../core/model';
import { KIND_LABELS, WORKSPACE_VERSION } from '../../core/model';
import { itemPathTitles, objectivesOfPeriod } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { ROUTES } from '../../app/routes';
import { Icon } from '../../ui/icons';
import type { IconName } from '../../ui/icons';
import { Modal } from '../../ui/Modal';
import {
  buildPaletteResults,
  highlightSegments,
  pushRecentRef,
  readRecentRefs,
  writeRecentRefs,
} from './fuzzy';
import type {
  PaletteAreaCandidate,
  PaletteItemCandidate,
  PaletteResults,
  RecentRef,
} from './fuzzy';
import { routeForItemKind } from './navigation';
import { useGlobalHotkeys } from './useGlobalHotkeys';
import { exportWorkspaceToFile } from './workspaceIO';
import './appshell.css';

/** 面板关闭时不订阅真实工作区，避免其他模块每次编辑都触发重算。 */
const EMPTY_WORKSPACE: Workspace = {
  version: WORKSPACE_VERSION,
  items: [],
  edges: [],
  areas: [],
  runs: [],
  updatedAt: '',
};

const EMPTY_RESULTS: PaletteResults = { recent: [], commands: [], items: [], areas: [] };

const KIND_ICONS: Record<ItemKind, IconName> = {
  objective: 'target',
  keyresult: 'flag',
  project: 'folder',
  action: 'check',
  sop: 'workflow',
  step: 'workflow',
  milestone: 'flag',
  note: 'edit',
  reference: 'link',
};

interface PaletteAction {
  id: string;
  label: string;
  hint?: string;
  icon: IconName;
  keywords?: string[];
  disabled?: boolean;
  run: () => void;
}

interface PaletteRow {
  key: string;
  group: string;
  label: string;
  hint?: string;
  icon: IconName;
  disabled?: boolean;
  ref: RecentRef;
  run: () => void;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function rowDomId(key: string): string {
  return `palette-row-${key.replace(/[^a-zA-Z0-9_-]/g, '-')}`;
}

function Highlighted({ text, query }: { text: string; query: string }) {
  const segments = highlightSegments(text, query);
  return (
    <>
      {segments.map((segment, index) =>
        segment.match ? (
          <mark className="palette-mark" key={index}>
            {segment.text}
          </mark>
        ) : (
          <span key={index}>{segment.text}</span>
        ),
      )}
    </>
  );
}

export function CommandPalette() {
  const open = useWorkspace((state) => state.ui.paletteOpen);
  // 关闭时返回同一个常量引用，工作面编辑不会引起本组件重渲染。
  const workspace = useWorkspace((state) =>
    state.ui.paletteOpen ? state.workspace : EMPTY_WORKSPACE,
  );
  const okrPeriod = useWorkspace((state) => state.ui.okrPeriod);
  const theme = useWorkspace((state) => state.ui.theme);

  const [query, setQuery] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);
  const [recent, setRecent] = useState<RecentRef[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);

  const togglePalette = useCallback(() => {
    const state = useWorkspace.getState();
    const next = !state.ui.paletteOpen;
    state.setUi({
      paletteOpen: next,
      ...(next ? { quickCaptureOpen: false, shortcutsOpen: false } : {}),
    });
  }, []);

  const handleUndo = useCallback(() => {
    const state = useWorkspace.getState();
    // GTD / SOP 视图各自注册了 Cmd/Ctrl+Z，避免同一次按键撤销两步。
    if (state.ui.route === 'gtd' || state.ui.route === 'sop') return;
    if (!state.canUndo()) {
      state.notify('没有可撤销的操作', 'info');
      return;
    }
    state.undo();
    state.notify('已撤销上一步', 'success');
  }, []);

  const handleRedo = useCallback(() => {
    const state = useWorkspace.getState();
    if (state.ui.route === 'gtd' || state.ui.route === 'sop') return;
    if (!state.canRedo()) {
      state.notify('没有可重做的操作', 'info');
      return;
    }
    state.redo();
    state.notify('已重做一步', 'success');
  }, []);

  useGlobalHotkeys({
    onTogglePalette: togglePalette,
    onUndo: handleUndo,
    onRedo: handleRedo,
    onEscape: () => {
      const state = useWorkspace.getState();
      if (state.ui.paletteOpen) state.setUi({ paletteOpen: false });
    },
  });

  useEffect(() => {
    if (!open) return;
    setQuery('');
    setActiveIndex(0);
    setRecent(readRecentRefs());
  }, [open]);

  const hasQuery = query.trim().length > 0;

  const actions = useMemo<PaletteAction[]>(() => {
    if (!open) return [];
    const state = useWorkspace.getState();
    const firstObjective = objectivesOfPeriod(workspace, okrPeriod)[0];
    const close = () => state.setUi({ paletteOpen: false });

    const runExport = () => {
      void (async () => {
        try {
          const target = await exportWorkspaceToFile(useWorkspace.getState().workspace);
          if (target) state.notify(`已导出到 ${target}`, 'success');
        } catch (error) {
          state.notify(`导出失败：${errorMessage(error)}`, 'error');
        } finally {
          close();
        }
      })();
    };

    const list: PaletteAction[] = [
      {
        id: 'new-sop',
        label: '新建 SOP',
        hint: '创建流程并打开画布',
        icon: 'workflow',
        keywords: ['流程', '新建'],
        run: () => {
          const item = state.createItem({ kind: 'sop', title: '未命名 SOP', status: 'active' });
          state.select(item.id);
          state.setUi({ route: 'sop', paletteOpen: false });
          state.notify('SOP 已创建，去画布添加步骤吧', 'success');
        },
      },
      {
        id: 'new-objective',
        label: '新建目标',
        hint: `周期 ${okrPeriod}`,
        icon: 'target',
        keywords: ['okr', '目标', '新建'],
        run: () => {
          const item = state.createItem({
            kind: 'objective',
            title: '新的目标',
            status: 'active',
            okr: { period: okrPeriod },
          });
          state.select(item.id);
          state.setUi({ route: 'okr', okrPeriod, paletteOpen: false });
          state.notify('目标已创建，接着添加关键结果吧', 'success');
        },
      },
      {
        id: 'new-keyresult',
        label: '新建 KR',
        hint: firstObjective ? `归属「${firstObjective.title}」` : '需要先创建目标',
        icon: 'flag',
        keywords: ['关键结果', 'okr', '新建'],
        disabled: !firstObjective,
        run: () => {
          if (!firstObjective) {
            state.notify('先创建一个目标，再添加关键结果', 'error');
            return;
          }
          const period = firstObjective.okr?.period ?? okrPeriod;
          const item = state.createItem({
            kind: 'keyresult',
            title: '新的关键结果',
            parentId: firstObjective.id,
            status: 'active',
            okr: { period },
          });
          state.select(item.id);
          state.setUi({ route: 'okr', okrPeriod: period, paletteOpen: false });
          state.notify('关键结果已创建', 'success');
        },
      },
      {
        id: 'quick-capture',
        label: '快速收集',
        hint: '收集到 GTD 收件箱',
        icon: 'plus',
        keywords: ['收集', 'inbox'],
        run: () => state.setUi({ quickCaptureOpen: true, paletteOpen: false }),
      },
      {
        id: 'toggle-theme',
        label: theme === 'dark' ? '切换到浅色主题' : '切换到深色主题',
        hint: '外观',
        icon: theme === 'dark' ? 'sun' : 'moon',
        keywords: ['深色', '浅色', 'dark', 'light'],
        run: () => {
          state.setUi({ theme: theme === 'dark' ? 'light' : 'dark', paletteOpen: false });
          state.notify(theme === 'dark' ? '已切换到浅色主题' : '已切换到深色主题', 'info');
        },
      },
      {
        id: 'undo',
        label: '撤销',
        hint: '⌘/Ctrl + Z',
        icon: 'chevron-left',
        keywords: ['undo', '回退'],
        disabled: !state.canUndo(),
        run: () => {
          state.undo();
          state.setUi({ paletteOpen: false });
          state.notify('已撤销上一步', 'success');
        },
      },
      {
        id: 'redo',
        label: '重做',
        hint: '⌘/Ctrl + ⇧ + Z',
        icon: 'chevron-right',
        keywords: ['redo'],
        disabled: !state.canRedo(),
        run: () => {
          state.redo();
          state.setUi({ paletteOpen: false });
          state.notify('已重做一步', 'success');
        },
      },
      {
        id: 'export',
        label: '导出工作区',
        hint: 'JSON 备份文件',
        icon: 'folder',
        keywords: ['备份', 'json', 'export'],
        run: runExport,
      },
      {
        id: 'open-settings',
        label: '打开设置',
        hint: '存储、备份与关于',
        icon: 'settings',
        keywords: ['偏好', 'settings'],
        run: () => state.setUi({ route: 'settings', paletteOpen: false }),
      },
      ...ROUTES.map<PaletteAction>((route) => ({
        id: `route:${route.id}`,
        label: `前往${route.label}`,
        hint: route.subtitle,
        icon: route.icon,
        keywords: [route.label, route.id],
        run: () => state.setUi({ route: route.id, paletteOpen: false }),
      })),
    ];
    return list;
  }, [open, workspace, okrPeriod, theme]);

  const commandCandidates = useMemo(
    () =>
      actions.map((action) => ({
        id: action.id,
        label: action.label,
        hint: action.hint,
        keywords: action.keywords,
      })),
    [actions],
  );

  const actionById = useMemo(
    () => new Map(actions.map((action) => [action.id, action])),
    [actions],
  );

  const itemCandidates = useMemo<PaletteItemCandidate[]>(() => {
    if (!open) return [];
    if (!hasQuery) {
      // 空查询只需要解析「最近使用」中的条目；不为整棵 workspace 拼路径。
      const recentIds = new Set(
        recent.filter((ref) => ref.type === 'item').map((ref) => ref.id),
      );
      if (recentIds.size === 0) return [];
      const candidates: PaletteItemCandidate[] = [];
      for (const item of workspace.items) {
        if (!recentIds.has(item.id)) continue;
        candidates.push({
          id: item.id,
          title: item.title,
          kind: item.kind,
          tags: [],
          pathTitles: [],
        });
      }
      return candidates;
    }
    // 有查询词时才计算祖先路径（每条一次 ancestorsOf）。
    return workspace.items.map((item) => ({
      id: item.id,
      title: item.title,
      kind: item.kind,
      tags: item.tags,
      pathTitles: itemPathTitles(workspace, item.id),
    }));
  }, [open, hasQuery, workspace, recent]);

  const areaCandidates = useMemo<PaletteAreaCandidate[]>(
    () => (open ? workspace.areas.map((area) => ({ id: area.id, name: area.name })) : []),
    [open, workspace.areas],
  );

  const runItem = useCallback((id: string) => {
    const state = useWorkspace.getState();
    const item = state.workspace.items.find((entry) => entry.id === id);
    if (!item) return;
    const period = item.okr?.period;
    state.select(item.id);
    state.setUi({
      route: routeForItemKind(item.kind),
      paletteOpen: false,
      ...(period ? { okrPeriod: period } : {}),
    });
  }, []);

  const runArea = useCallback((id: string) => {
    const state = useWorkspace.getState();
    const area = state.workspace.areas.find((entry) => entry.id === id);
    if (!area) return;
    state.setUi({ route: 'gtd', search: area.name, paletteOpen: false });
    state.notify(`已在搜索框填入领域「${area.name}」，可在 GTD 视图继续用领域筛选收窄`, 'info');
  }, []);

  const results = useMemo(() => {
    if (!open) return EMPTY_RESULTS;
    return buildPaletteResults(query, {
      commands: commandCandidates,
      items: itemCandidates,
      areas: areaCandidates,
      recent,
    });
  }, [open, query, commandCandidates, itemCandidates, areaCandidates, recent]);

  const runForRef = (ref: RecentRef): (() => void) | null => {
    if (ref.type === 'command') return actionById.get(ref.id)?.run ?? null;
    if (ref.type === 'item') {
      return workspace.items.some((item) => item.id === ref.id) ? () => runItem(ref.id) : null;
    }
    return workspace.areas.some((area) => area.id === ref.id) ? () => runArea(ref.id) : null;
  };

  const iconForRef = (ref: RecentRef): IconName => {
    if (ref.type === 'command') return actionById.get(ref.id)?.icon ?? 'play';
    if (ref.type === 'item') {
      const item = workspace.items.find((entry) => entry.id === ref.id);
      return item ? KIND_ICONS[item.kind] : 'flag';
    }
    return 'folder';
  };

  const rows: PaletteRow[] = [];
  for (const recentRow of results.recent) {
    const run = runForRef(recentRow.ref);
    if (!run) continue;
    rows.push({
      key: `recent:${recentRow.ref.type}:${recentRow.ref.id}`,
      group: '最近使用',
      label: recentRow.label,
      hint: recentRow.hint,
      icon: iconForRef(recentRow.ref),
      ref: recentRow.ref,
      run,
    });
  }
  for (const command of results.commands) {
    const action = actionById.get(command.id);
    if (!action) continue;
    rows.push({
      key: `command:${action.id}`,
      group: '命令',
      label: action.label,
      hint: action.hint,
      icon: action.icon,
      disabled: action.disabled,
      ref: { type: 'command', id: action.id },
      run: action.run,
    });
  }
  for (const { candidate } of results.items) {
    rows.push({
      key: `item:${candidate.id}`,
      group: '条目',
      label: candidate.title,
      hint:
        candidate.pathTitles.length > 1
          ? candidate.pathTitles.slice(0, -1).join(' / ')
          : KIND_LABELS[candidate.kind],
      icon: KIND_ICONS[candidate.kind],
      ref: { type: 'item', id: candidate.id },
      run: () => runItem(candidate.id),
    });
  }
  for (const area of results.areas) {
    rows.push({
      key: `area:${area.id}`,
      group: '领域',
      label: area.name,
      hint: '在 GTD 中筛选',
      icon: 'folder',
      ref: { type: 'area', id: area.id },
      run: () => runArea(area.id),
    });
  }

  const activeRow = rows[activeIndex] ?? null;

  useEffect(() => {
    if (!open) return;
    setActiveIndex((index) => (index >= rows.length ? 0 : index));
  }, [open, rows.length]);

  useEffect(() => {
    if (!open || !activeRow) return;
    document.getElementById(rowDomId(activeRow.key))?.scrollIntoView({ block: 'nearest' });
  }, [open, activeIndex, activeRow?.key]);

  const executeRow = (row: PaletteRow) => {
    if (row.disabled) return;
    const nextRecent = pushRecentRef(row.ref, recent);
    setRecent(nextRecent);
    writeRecentRefs(nextRecent);
    row.run();
  };

  const move = (direction: 1 | -1) => {
    if (rows.length === 0) return;
    let index = activeIndex;
    for (let step = 0; step < rows.length; step += 1) {
      index = (index + direction + rows.length) % rows.length;
      if (!rows[index].disabled) {
        setActiveIndex(index);
        return;
      }
    }
  };

  const jumpGroup = (direction: 1 | -1) => {
    const groups = [...new Set(rows.map((row) => row.group))];
    if (groups.length < 2) return;
    const currentGroup = activeRow?.group ?? groups[0];
    const start = groups.indexOf(currentGroup);
    for (let step = 1; step <= groups.length; step += 1) {
      const position = ((start + direction * step) % groups.length + groups.length) % groups.length;
      const group = groups[position];
      const index = rows.findIndex((row) => row.group === group && !row.disabled);
      if (index >= 0) {
        setActiveIndex(index);
        return;
      }
    }
  };

  const handleInputKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.nativeEvent.isComposing) return;
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        move(1);
        break;
      case 'ArrowUp':
        event.preventDefault();
        move(-1);
        break;
      case 'Enter':
        event.preventDefault();
        if (activeRow) executeRow(activeRow);
        break;
      case 'Tab':
        event.preventDefault();
        jumpGroup(event.shiftKey ? -1 : 1);
        break;
      default:
        break;
    }
  };

  return (
    <Modal
      open={open}
      onClose={() => useWorkspace.getState().setUi({ paletteOpen: false })}
      title="命令面板"
      description="搜索命令、条目与领域"
      width={640}
      initialFocusRef={inputRef}
    >
      <div className="palette">
        <div className="palette-search">
          <Icon name="search" size={16} />
          <input
            ref={inputRef}
            className="palette-input"
            type="text"
            value={query}
            role="combobox"
            aria-label="搜索命令、条目或领域"
            aria-expanded
            aria-controls="palette-results"
            aria-autocomplete="list"
            aria-activedescendant={activeRow ? rowDomId(activeRow.key) : undefined}
            placeholder="输入命令、条目标题、标签或领域…"
            autoComplete="off"
            spellCheck={false}
            onChange={(event) => {
              setQuery(event.target.value);
              setActiveIndex(0);
            }}
            onKeyDown={handleInputKeyDown}
          />
          <kbd className="palette-kbd">Esc</kbd>
        </div>

        <div
          className="palette-results"
          id="palette-results"
          role="listbox"
          aria-label="命令面板结果"
        >
          {rows.length === 0 ? <p className="palette-empty">没有匹配的结果</p> : null}
          {rows.map((row, index) => {
            const showGroup = index === 0 || rows[index - 1].group !== row.group;
            return (
              <Fragment key={row.key}>
                {showGroup ? (
                  <div className="palette-group" role="presentation">
                    {row.group}
                  </div>
                ) : null}
                <button
                  type="button"
                  id={rowDomId(row.key)}
                  role="option"
                  aria-selected={index === activeIndex}
                  className="palette-row"
                  data-active={index === activeIndex}
                  disabled={row.disabled}
                  onMouseEnter={() => setActiveIndex(index)}
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => executeRow(row)}
                >
                  <Icon name={row.icon} size={15} />
                  <span className="palette-label">
                    <Highlighted text={row.label} query={query} />
                  </span>
                  {row.hint ? <span className="palette-hint">{row.hint}</span> : null}
                </button>
              </Fragment>
            );
          })}
        </div>

        <div className="palette-footer">
          <span>
            <kbd className="palette-kbd">↑</kbd>
            <kbd className="palette-kbd">↓</kbd> 选择
          </span>
          <span>
            <kbd className="palette-kbd">Enter</kbd> 执行
          </span>
          <span>
            <kbd className="palette-kbd">Tab</kbd> 切换分组
          </span>
          <span>
            <kbd className="palette-kbd">Esc</kbd> 关闭
          </span>
          <span className="palette-footer-hint">⌘/Ctrl + K 开关面板</span>
        </div>
      </div>
    </Modal>
  );
}
