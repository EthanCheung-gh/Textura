// TODO(module): 由 appshell Worker 重写为设置页（导入/导出、备份恢复、主题、快捷键）。
import { useEffect, useState } from 'react';
import { useWorkspace } from '../../core/store';
import { repo } from '../../core/store';
import type { StorageInfo } from '../../core/repo';
import { Badge } from '../../ui/Badge';
import { Segmented } from '../../ui/Segmented';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';

export function SettingsPage() {
  const theme = useWorkspace((state) => state.ui.theme);
  const setUi = useWorkspace((state) => state.setUi);
  const workspace = useWorkspace((state) => state.workspace);
  const [info, setInfo] = useState<StorageInfo | null>(null);

  useEffect(() => {
    let alive = true;
    repo
      .storageInfo()
      .then((next) => {
        if (alive) setInfo(next);
      })
      .catch(() => {
        if (alive) setInfo(null);
      });
    return () => {
      alive = false;
    };
  }, [workspace.updatedAt]);

  return (
    <div className="page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>设置</h1>
          <p>存储、备份与工作区。</p>
        </div>
        <Badge tone={repo.isTauri() ? 'ok' : 'warn'} dot>
          {repo.isTauri() ? '桌面模式' : '浏览器调试模式'}
        </Badge>
      </div>

      <div className="placeholder-card">
        <Segmented
          ariaLabel="主题"
          value={theme}
          onChange={(value) => setUi({ theme: value })}
          options={[
            { value: 'light', label: '浅色', icon: <Icon name="sun" size={13} /> },
            { value: 'dark', label: '深色', icon: <Icon name="moon" size={13} /> },
          ]}
        />
        <EmptyState
          compact
          icon={<Icon name="settings" size={20} />}
          title="设置页占位"
          description={
            info
              ? `数据目录：${info.dataDir} · 备份 ${info.backupCount} 份 · revision ${info.revision}`
              : '正在读取存储信息…'
          }
        />
        <p className="placeholder-note">TODO(module): src/modules/appshell/SettingsPage.tsx</p>
      </div>
    </div>
  );
}
