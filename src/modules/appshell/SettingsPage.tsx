import { useCallback, useEffect, useRef, useState } from 'react';
import type { ChangeEvent } from 'react';
import { buildDemoWorkspace } from '../../core/fixtures';
import type { Workspace } from '../../core/model';
import type { BackupInfo, StorageInfo } from '../../core/repo';
import { getWorkspace, repo, useWorkspace } from '../../core/store';
import { formatDateTime } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/icons';
import { Modal } from '../../ui/Modal';
import { Segmented } from '../../ui/Segmented';
import { AiSettingsCard } from '../ai/AiSettingsCard';
import { parseImportText, summarizeImport } from './importValidation';
import { exportWorkspaceToFile, pickWorkspaceFile } from './workspaceIO';
import './appshell.css';

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function formatSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return '—';
  if (bytes < 1024) return `${bytes} B`;
  return `${(bytes / 1024).toFixed(1)} KB`;
}

interface PendingImport {
  workspace: Workspace;
  source: string;
}

export function SettingsPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const theme = useWorkspace((state) => state.ui.theme);
  const saveState = useWorkspace((state) => state.saveState);
  const setUi = useWorkspace((state) => state.setUi);
  const save = useWorkspace((state) => state.save);
  const replaceWorkspace = useWorkspace((state) => state.replaceWorkspace);
  const reload = useWorkspace((state) => state.reload);
  const undo = useWorkspace((state) => state.undo);
  const redo = useWorkspace((state) => state.redo);
  const canUndo = useWorkspace((state) => state.canUndo);
  const canRedo = useWorkspace((state) => state.canRedo);
  const notify = useWorkspace((state) => state.notify);

  const tauri = repo.isTauri();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [info, setInfo] = useState<StorageInfo | null>(null);
  const [backups, setBackups] = useState<BackupInfo[]>([]);
  const [infoError, setInfoError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [restoreTarget, setRestoreTarget] = useState<BackupInfo | null>(null);
  const [resetOpen, setResetOpen] = useState(false);
  const [pendingImport, setPendingImport] = useState<PendingImport | null>(null);
  const [importError, setImportError] = useState<string | null>(null);
  const [resetError, setResetError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const next = await repo.storageInfo();
      setInfo(next);
      setInfoError(null);
      if (repo.isTauri()) {
        setBackups(await repo.listBackups());
      } else {
        setBackups([]);
      }
    } catch (error) {
      setInfoError(errorMessage(error));
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh, workspace.updatedAt]);

  const undoable = canUndo();
  const redoable = canRedo();
  const importSummary = pendingImport ? summarizeImport(pendingImport.workspace) : null;

  const saveNow = async () => {
    setBusy('save');
    try {
      await save();
      const state = getWorkspace();
      if (state.saveState === 'error') {
        notify(state.error ?? '保存失败', 'error');
      } else {
        notify('工作区已保存', 'success');
      }
      await refresh();
    } catch (error) {
      notify(`保存失败：${errorMessage(error)}`, 'error');
    } finally {
      setBusy(null);
    }
  };

  const handleExport = async () => {
    setBusy('export');
    try {
      const target = await exportWorkspaceToFile(getWorkspace().workspace);
      if (target) notify(`已导出到 ${target}`, 'success');
      else notify('已取消导出', 'info');
    } catch (error) {
      notify(`导出失败：${errorMessage(error)}`, 'error');
    } finally {
      setBusy(null);
    }
  };

  const handleFilePicked = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    try {
      const text = await file.text();
      const parsed = parseImportText(text);
      setImportError(null);
      setPendingImport({ workspace: parsed, source: file.name });
    } catch (error) {
      notify(`导入失败：${errorMessage(error)}`, 'error');
    }
  };

  const handlePickImport = async () => {
    if (!tauri) {
      fileInputRef.current?.click();
      return;
    }
    setBusy('import-pick');
    try {
      const picked = await pickWorkspaceFile();
      if (!picked) return;
      const parsed = parseImportText(picked.text);
      setImportError(null);
      setPendingImport({ workspace: parsed, source: picked.path });
    } catch (error) {
      notify(`导入失败：${errorMessage(error)}`, 'error');
    } finally {
      setBusy(null);
    }
  };

  const applyImport = async () => {
    if (!pendingImport) return;
    setBusy('import');
    setImportError(null);
    const imported = pendingImport.workspace;
    try {
      // 唯一入口：归一化 + 历史快照 + 原子落盘，失败会抛出。
      await replaceWorkspace(imported);
      notify(
        `已导入 ${imported.items.length} 条记录、${imported.areas.length} 个领域、${imported.runs.length} 条运行记录；可用 Ctrl+Z 回退`,
        'success',
      );
      setPendingImport(null);
      void refresh();
    } catch (error) {
      const message = errorMessage(error);
      setImportError(message);
      notify(`导入失败：${message}`, 'error');
    } finally {
      setBusy(null);
    }
  };

  const applyReset = async () => {
    setBusy('reset');
    setResetError(null);
    try {
      await replaceWorkspace(buildDemoWorkspace());
      notify('已重置为演示数据；可用 Ctrl+Z 回退整次重置', 'success');
      setResetOpen(false);
      void refresh();
    } catch (error) {
      const message = errorMessage(error);
      setResetError(message);
      notify(`重置失败：${message}`, 'error');
    } finally {
      setBusy(null);
    }
  };

  const applyRestore = async () => {
    if (!restoreTarget) return;
    setBusy('restore');
    try {
      await repo.restoreBackup(restoreTarget.name);
      await reload();
      await refresh();
      notify(`已恢复备份 ${restoreTarget.name}`, 'success');
    } catch (error) {
      notify(`恢复失败：${errorMessage(error)}`, 'error');
    } finally {
      setBusy(null);
      setRestoreTarget(null);
    }
  };

  return (
    <div className="page settings-page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>设置</h1>
          <p>存储、备份、大模型与工具。</p>
        </div>
        <div className="page-actions">
          <Badge tone={tauri ? 'ok' : 'warn'} dot>
            {tauri ? '桌面模式' : '浏览器调试模式'}
          </Badge>
          <Button
            size="sm"
            variant="secondary"
            iconLeft={<Icon name="flag" size={14} />}
            onClick={() => setUi({ shortcutsOpen: true })}
          >
            快捷键
          </Button>
        </div>
      </div>

      <div className="settings-grid">
        <div className="settings-stack">
          <section className="settings-card" aria-labelledby="settings-appearance">
            <header className="settings-card-head">
              <div>
                <h2 className="settings-card-title" id="settings-appearance">
                  <Icon name={theme === 'dark' ? 'moon' : 'sun'} size={15} />
                  外观
                </h2>
                <p className="settings-card-desc">
                  主题立即生效，并记录在 localStorage（textura.theme），下次启动沿用。
                </p>
              </div>
              <Segmented
                ariaLabel="主题"
                size="sm"
                value={theme}
                onChange={(value) => setUi({ theme: value })}
                options={[
                  { value: 'light', label: '浅色', icon: <Icon name="sun" size={13} /> },
                  { value: 'dark', label: '深色', icon: <Icon name="moon" size={13} /> },
                ]}
              />
            </header>
            <div className="settings-card-body">
              <p className="settings-note">
                浅色是暖纸感的工作台，深色适合夜间复盘。主题只影响界面，不改动工作区数据。
              </p>
            </div>
          </section>

          <section className="settings-card" aria-labelledby="settings-storage">
            <header className="settings-card-head">
              <div>
                <h2 className="settings-card-title" id="settings-storage">
                  <Icon name="folder" size={15} />
                  数据与备份
                </h2>
                <p className="settings-card-desc">
                  {tauri
                    ? '工作区原子写入单个 JSON 文件，保存前生成 .bak 并轮换保留 30 份备份。'
                    : '浏览器调试模式写入 localStorage，不提供文件级备份。'}
                </p>
              </div>
              <Badge tone={saveState === 'error' ? 'danger' : saveState === 'saving' ? 'warn' : 'ok'} dot>
                {saveState === 'error'
                  ? '保存失败'
                  : saveState === 'saving'
                    ? '正在保存'
                    : saveState === 'saved'
                      ? '已保存'
                      : '自动保存'}
              </Badge>
            </header>
            <div className="settings-card-body">
              <div className="settings-rows">
                <div className="settings-row">
                  <span className="settings-row-label">运行模式</span>
                  <span className="settings-row-value">
                    {tauri ? 'Tauri 桌面（文件持久化）' : '浏览器调试模式（localStorage）'}
                  </span>
                </div>
                <div className="settings-row">
                  <span className="settings-row-label">数据目录</span>
                  <span className="settings-row-value">{info?.dataDir ?? '读取中…'}</span>
                </div>
                <div className="settings-row">
                  <span className="settings-row-label">工作区文件</span>
                  <span className="settings-row-value">{info?.workspacePath ?? '读取中…'}</span>
                </div>
                <div className="settings-row">
                  <span className="settings-row-label">轮换备份</span>
                  <span className="settings-row-value">
                    {tauri ? `${info?.backupCount ?? 0} 份` : '浏览器调试模式不提供'}
                  </span>
                </div>
              </div>

              <div className="settings-actions">
                <Button
                  size="sm"
                  variant="secondary"
                  iconLeft={<Icon name="check" size={14} />}
                  onClick={() => void saveNow()}
                  disabled={busy !== null}
                >
                  立即保存
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => void refresh()}
                  disabled={busy !== null}
                >
                  刷新信息
                </Button>
              </div>

              {infoError ? <p className="settings-error">读取存储信息失败：{infoError}</p> : null}

              {tauri ? (
                backups.length === 0 ? (
                  <p className="settings-note">还没有轮换备份。保存一次工作区后会生成。</p>
                ) : (
                  <ul className="settings-backups" aria-label="备份列表">
                    {backups.map((backup) => (
                      <li className="settings-backup-row" key={backup.name}>
                        <span className="settings-backup-main">
                          <span className="settings-backup-name">{backup.name}</span>
                          <span className="settings-backup-meta">
                            {formatDateTime(backup.createdAt)} · {formatSize(backup.size)}
                          </span>
                        </span>
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => setRestoreTarget(backup)}
                          disabled={busy !== null}
                          aria-label={`恢复备份 ${backup.name}`}
                        >
                          恢复
                        </Button>
                      </li>
                    ))}
                  </ul>
                )
              ) : (
                <p className="settings-note">
                  浏览器调试模式不提供备份列表与恢复。需要备份时请使用下方「导出 JSON」。
                </p>
              )}
            </div>
          </section>

          <section className="settings-card" aria-labelledby="settings-transfer">
            <header className="settings-card-head">
              <div>
                <h2 className="settings-card-title" id="settings-transfer">
                  <Icon name="link" size={15} />
                  导入 / 导出
                </h2>
                <p className="settings-card-desc">
                  导出一份完整 JSON；导入会整份替换当前工作区（items / edges / areas / runs）。
                </p>
              </div>
            </header>
            <div className="settings-card-body">
              <div className="settings-actions">
                <Button
                  size="sm"
                  variant="secondary"
                  iconLeft={<Icon name="folder" size={14} />}
                  onClick={() => void handleExport()}
                  disabled={busy !== null}
                >
                  导出 JSON
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  iconLeft={<Icon name="link" size={14} />}
                  onClick={() => void handlePickImport()}
                  disabled={busy !== null}
                >
                  导入 JSON…
                </Button>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="application/json,.json"
                  className="sr-only"
                  aria-label="选择要导入的 JSON 文件"
                  onChange={(event) => void handleFilePicked(event)}
                />
              </div>
              <p className="settings-note">
                导入会先校验 JSON，再通过 replaceWorkspace 整份替换并立即原子保存；导入前会记录一次历史快照，可用 Ctrl+Z 回退整次导入。当前工作区：{workspace.items.length} 条记录 · {workspace.areas.length} 个领域 ·{' '}
                {workspace.runs.length} 条 SOP 运行记录。
              </p>
            </div>
          </section>
        </div>

        <div className="settings-stack">
          <AiSettingsCard />

          <section className="settings-card" aria-labelledby="settings-maintenance">
            <header className="settings-card-head">
              <div>
                <h2 className="settings-card-title" id="settings-maintenance">
                  <Icon name="workflow" size={15} />
                  维护
                </h2>
                <p className="settings-card-desc">历史栈最多 80 步，撤销 / 重做会同步写回磁盘。</p>
              </div>
            </header>
            <div className="settings-card-body">
              <div className="settings-row">
                <span className="settings-row-label">可撤销</span>
                <span className="settings-row-value">{undoable ? '有历史记录' : '没有可撤销的操作'}</span>
              </div>
              <div className="settings-row">
                <span className="settings-row-label">可重做</span>
                <span className="settings-row-value">{redoable ? '有重做记录' : '没有可重做的操作'}</span>
              </div>
              <div className="settings-actions">
                <Button
                  size="sm"
                  variant="secondary"
                  iconLeft={<Icon name="chevron-left" size={14} />}
                  disabled={!undoable}
                  onClick={() => {
                    undo();
                    notify('已撤销上一步', 'success');
                  }}
                >
                  撤销
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  iconLeft={<Icon name="chevron-right" size={14} />}
                  disabled={!redoable}
                  onClick={() => {
                    redo();
                    notify('已重做一步', 'success');
                  }}
                >
                  重做
                </Button>
              </div>
              <p className="settings-note">
                重置会通过 replaceWorkspace 用内置演示数据整份替换并立即保存，可用 Ctrl+Z 回退整次重置。
              </p>
              <div className="settings-actions">
                <Button
                  size="sm"
                  variant="danger"
                  iconLeft={<Icon name="trash" size={14} />}
                  onClick={() => {
                    setResetError(null);
                    setResetOpen(true);
                  }}
                  disabled={busy !== null}
                >
                  重置为演示数据
                </Button>
              </div>
            </div>
          </section>

          <section className="settings-card" aria-labelledby="settings-about">
            <header className="settings-card-head">
              <div>
                <h2 className="settings-card-title" id="settings-about">
                  <Icon name="settings" size={15} />
                  关于
                </h2>
                <p className="settings-card-desc">Textura · 织理 — 单机优先的结构化执行工作台。</p>
              </div>
            </header>
            <div className="settings-card-body">
              <dl className="settings-about-list">
                <dt>版本</dt>
                <dd>0.1.0</dd>
                <dt>技术栈</dt>
                <dd>Tauri v2 · React 18.3 · TypeScript strict · Zustand 5 · Vite 7</dd>
                <dt>数据模型</dt>
                <dd>
                  统一 Item 内核：OKR / GTD / 甘特 / SOP 共享同一实体，各视图读取不同的数据块。
                </dd>
                <dt>快捷键</dt>
                <dd>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => setUi({ shortcutsOpen: true })}
                  >
                    查看快捷键帮助
                  </Button>
                </dd>
              </dl>
            </div>
          </section>
        </div>
      </div>

      <Modal
        open={restoreTarget !== null}
        onClose={() => setRestoreTarget(null)}
        title="恢复这个备份？"
        description={restoreTarget?.name}
        width={460}
        footer={
          <>
            <Button variant="ghost" size="sm" onClick={() => setRestoreTarget(null)}>
              取消
            </Button>
            <Button
              variant="danger"
              size="sm"
              onClick={() => void applyRestore()}
              disabled={busy !== null}
            >
              覆盖当前工作区并恢复
            </Button>
          </>
        }
      >
        <p className="settings-warning">
          恢复会用这份备份整份替换当前工作区，当前未保存的修改会丢失。Rust 侧在写回前会自动生成
          .bak 单次回滚文件。
        </p>
      </Modal>

      <Modal
        open={pendingImport !== null}
        onClose={() => setPendingImport(null)}
        title="导入并覆盖工作区？"
        description={pendingImport?.source}
        width={480}
        footer={
          <>
            <Button variant="ghost" size="sm" onClick={() => setPendingImport(null)}>
              取消
            </Button>
            <Button
              variant="danger"
              size="sm"
              onClick={() => void applyImport()}
              disabled={busy !== null}
            >
              覆盖并导入
            </Button>
          </>
        }
      >
        <p className="settings-warning">
          导入会通过 replaceWorkspace 整份替换当前工作区；导入前会记录一次历史快照，可用 Ctrl+Z
          回退整次导入。请确认这是你要导入的文件。
        </p>
        {importSummary && importSummary.items === 0 && importSummary.areas === 0 && importSummary.runs === 0 ? (
          <p className="settings-note settings-note--spaced">
            注意：这份文件是空工作区，导入后工作区将为空（不会自动播种演示数据）。
          </p>
        ) : null}
        {importError ? (
          <p className="settings-error settings-error--spaced" role="alert">
            导入失败：{importError}
          </p>
        ) : null}
        {importSummary ? (
          <dl className="settings-about-list settings-import-stats">
            <dt>条目</dt>
            <dd>{importSummary.items} 条</dd>
            <dt>领域</dt>
            <dd>{importSummary.areas} 个</dd>
            <dt>边</dt>
            <dd>{importSummary.edges} 条</dd>
            <dt>SOP 运行</dt>
            <dd>{importSummary.runs} 条</dd>
            <dt>版本</dt>
            <dd>{importSummary.version}</dd>
          </dl>
        ) : null}
      </Modal>

      <Modal
        open={resetOpen}
        onClose={() => setResetOpen(false)}
        title="重置为演示数据？"
        width={480}
        footer={
          <>
            <Button variant="ghost" size="sm" onClick={() => setResetOpen(false)}>
              取消
            </Button>
            <Button
              variant="danger"
              size="sm"
              onClick={() => void applyReset()}
              disabled={busy !== null}
            >
              覆盖并重置
            </Button>
          </>
        }
      >
        <p className="settings-warning">
          这会通过 replaceWorkspace 覆盖当前工作区，写入内置演示数据（目标、关键结果、SOP、官网改版项目与收件箱）。
          重置前会记录一次历史快照，可用 Ctrl+Z 回退整次重置。
        </p>
        {resetError ? (
          <p className="settings-error settings-error--spaced" role="alert">
            重置失败：{resetError}
          </p>
        ) : null}
      </Modal>
    </div>
  );
}
