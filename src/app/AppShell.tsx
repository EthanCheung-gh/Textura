import { useEffect, useState } from 'react';
import { useWorkspace } from '../core/store';
import { storageInfo } from '../core/repo';
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
import { RouteErrorBoundary } from './RouteErrorBoundary';

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
  const reload = useWorkspace((state) => state.reload);
  const save = useWorkspace((state) => state.save);
  const setUi = useWorkspace((state) => state.setUi);
  const notify = useWorkspace((state) => state.notify);
  const [reloading, setReloading] = useState(false);

  useEffect(() => {
    if (bootstrapped) return;
    bootstrapped = true;
    void load();
  }, [load]);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  const reloadSafely = async (): Promise<void> => {
    if (reloading) return;
    setReloading(true);
    try {
      // 先落盘，避免错误边界恢复动作丢掉用户刚提交的编辑。
      await save();
      const state = useWorkspace.getState();
      if (state.saveState === 'error') {
        notify(`保存失败，已取消重新加载：${state.error ?? '未知错误'}`, 'error');
        return;
      }
      await reload();
    } finally {
      setReloading(false);
    }
  };

  const showDataDir = async (): Promise<void> => {
    try {
      const info = await storageInfo();
      notify(`数据目录：${info.dataDir}`, 'info');
      try {
        await navigator.clipboard?.writeText(info.dataDir);
      } catch {
        // 剪贴板不可用时只展示路径。
      }
    } catch (showError) {
      notify(
        `无法读取数据目录：${showError instanceof Error ? showError.message : String(showError)}`,
        'error',
      );
    }
  };

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
          <RouteErrorBoundary
            resetKey={route}
            onBackToday={() => setUi({ route: 'dashboard' })}
            onReload={() => void reloadSafely()}
            reloading={reloading}
            onShowDataDir={() => void showDataDir()}
          >
            <RouteView route={route} />
          </RouteErrorBoundary>
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
