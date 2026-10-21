import { useWorkspace } from '../core/store';
import { Icon } from '../ui/icons';
import { IconButton } from '../ui/IconButton';
import { TextInput } from '../ui/Field';
import { routeMeta } from './routes';

export function TopBar() {
  const ui = useWorkspace((state) => state.ui);
  const setUi = useWorkspace((state) => state.setUi);
  const meta = routeMeta(ui.route);

  return (
    <header className="topbar">
      <div className="topbar-titles">
        <span className="topbar-title">{meta.title}</span>
        <span className="topbar-subtitle">{meta.subtitle}</span>
      </div>
      <div className="topbar-spacer" />
      <div className="topbar-search" style={{ flex: '0 1 320px', width: 'auto', minWidth: 180 }}>
        <TextInput
          type="search"
          aria-label="搜索工作区"
          placeholder="搜索…"
          value={ui.search}
          onChange={(event) => setUi({ search: event.target.value })}
        />
      </div>
      <div className="topbar-actions">
        <IconButton
          label={ui.theme === 'dark' ? '切换到浅色主题' : '切换到深色主题'}
          variant="ghost"
          onClick={() => setUi({ theme: ui.theme === 'dark' ? 'light' : 'dark' })}
        >
          <Icon name={ui.theme === 'dark' ? 'sun' : 'moon'} size={17} />
        </IconButton>
      </div>
    </header>
  );
}
