import { useEffect } from 'react';
import { useWorkspace } from '../core/store';
import type { Route } from '../core/store';
import { Sidebar } from './Sidebar';
import { TopBar } from './TopBar';
import { Button } from '../ui/Button';
import { DashboardPage } from '../modules/dashboard/DashboardPage';
import { OkrPage } from '../modules/okr/OkrPage';
import { GtdPage } from '../modules/gtd/GtdPage';
import { GanttPage } from '../modules/gantt/GanttPage';
import { SopPage } from '../modules/sop/SopPage';
import { CommandPalette } from '../modules/appshell/CommandPalette';
import { QuickCapture } from '../modules/appshell/QuickCapture';
import { SettingsPage } from '../modules/appshell/SettingsPage';
import { ShortcutsDialog } from '../modules/appshell/ShortcutsDialog';

let bootstrapped = false;

function RouteView({ route }: { route: Route }) {
  switch (route) {
    case 'okr':
      return <OkrPage />;
    case 'gtd':
      return <GtdPage />;
    case 'gantt':
      return <GanttPage />;
    case 'sop':
      return <SopPage />;
    case 'settings':
      return <SettingsPage />;
    case 'dashboard':
    default:
      return <DashboardPage />;
  }
}

export function AppShell() {
  const status = useWorkspace((state) => state.status);
  const error = useWorkspace((state) => state.error);
  const theme = useWorkspace((state) => state.ui.theme);
  const route = useWorkspace((state) => state.ui.route);
  const notices = useWorkspace((state) => state.notices);
  const load = useWorkspace((state) => state.load);

  useEffect(() => {
    if (bootstrapped) return;
    bootstrapped = true;
    void load();
  }, [load]);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  if (status === 'loading') {
    return (
      <div className="loading-screen" role="status">
        <div className="loading-mark" aria-hidden="true" />
        <span>正在织理工作区…</span>
      </div>
    );
  }

  if (status === 'error') {
    return (
      <div className="loading-screen" role="alert">
        <strong>工作区加载失败</strong>
        <span className="muted">{error ?? '未知错误'}</span>
        <Button variant="secondary" onClick={() => void load()}>
          重试
        </Button>
      </div>
    );
  }

  return (
    <div className="shell">
      <Sidebar />
      <div className="shell-main">
        <TopBar />
        <main className="shell-content" id="main-content">
          <RouteView route={route} />
        </main>
      </div>

      <CommandPalette />
      <QuickCapture />
      <ShortcutsDialog />

      <div className="notices" aria-live="polite" aria-atomic="false">
        {notices.map((notice) => (
          <div key={notice.id} className="notice" data-tone={notice.tone}>
            {notice.message}
          </div>
        ))}
      </div>
    </div>
  );
}
