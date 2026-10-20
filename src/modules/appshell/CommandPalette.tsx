// TODO(module): 由 appshell Worker 重写为真正的命令面板（Ctrl/⌘+K）。
import { useMemo, useState } from 'react';
import { useWorkspace } from '../../core/store';
import { ROUTES } from '../../app/routes';
import { Modal } from '../../ui/Modal';
import { TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';

export function CommandPalette() {
  const open = useWorkspace((state) => state.ui.paletteOpen);
  const setUi = useWorkspace((state) => state.setUi);
  const workspace = useWorkspace((state) => state.workspace);
  const select = useWorkspace((state) => state.select);
  const [query, setQuery] = useState('');

  const items = useMemo(() => {
    const keyword = query.trim().toLowerCase();
    const routes = ROUTES.filter((route) => !keyword || route.label.toLowerCase().includes(keyword));
    const records = workspace.items
      .filter((item) => keyword && item.title.toLowerCase().includes(keyword))
      .slice(0, 8);
    return { routes, records };
  }, [query, workspace.items]);

  const close = () => setUi({ paletteOpen: false });

  return (
    <Modal open={open} onClose={close} title="命令面板" description="跳转视图或定位条目">
      <TextInput
        autoFocus
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder="输入视图名或条目…"
        aria-label="搜索命令"
      />
      <div style={{ marginTop: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 2 }}>
        {items.routes.map((route) => (
          <button
            key={route.id}
            type="button"
            className="sidebar-link"
            onClick={() => {
              setUi({ route: route.id });
              close();
            }}
          >
            <span className="sidebar-link-icon">
              <Icon name={route.icon} size={16} />
            </span>
            <span className="sidebar-link-label">前往 {route.label}</span>
          </button>
        ))}
        {items.records.map((item) => (
          <button
            key={item.id}
            type="button"
            className="sidebar-link"
            onClick={() => {
              select(item.id);
              close();
            }}
          >
            <span className="sidebar-link-icon">
              <Icon name="flag" size={16} />
            </span>
            <span className="sidebar-link-label">{item.title}</span>
          </button>
        ))}
        {items.routes.length === 0 && items.records.length === 0 ? (
          <p className="faint" style={{ padding: 'var(--space-3)' }}>
            没有匹配结果
          </p>
        ) : null}
      </div>
    </Modal>
  );
}
