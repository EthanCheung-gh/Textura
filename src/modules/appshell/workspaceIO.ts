/**
 * 工作区文件导入 / 导出（命令面板与设置页共用）。
 * Tauri 走原生对话框 + Rust 命令；浏览器降级为 Blob 下载。
 */
import { format } from 'date-fns';
import type { Workspace } from '../../core/model';
import { repo } from '../../core/store';

export function workspaceJson(workspace: Workspace): string {
  return `${JSON.stringify(workspace, null, 2)}\n`;
}

export function defaultExportName(): string {
  return `textura-workspace-${format(new Date(), 'yyyyMMdd-HHmm')}.json`;
}

/** 返回导出目标（Tauri 为绝对路径，浏览器为文件名）；取消返回 null。 */
export async function exportWorkspaceToFile(workspace: Workspace): Promise<string | null> {
  const json = workspaceJson(workspace);
  if (repo.isTauri()) {
    const { save } = await import('@tauri-apps/plugin-dialog');
    const path = await save({
      title: '导出工作区',
      defaultPath: defaultExportName(),
      filters: [{ name: 'JSON', extensions: ['json'] }],
    });
    if (!path) return null;
    await repo.exportWorkspace(json, path);
    return path;
  }
  const name = defaultExportName();
  await repo.exportWorkspace(json, name);
  return name;
}

/** Tauri：选择一个 .json 文件并读取文本；取消返回 null。 */
export async function pickWorkspaceFile(): Promise<{ path: string; text: string } | null> {
  if (!repo.isTauri()) return null;
  const { open } = await import('@tauri-apps/plugin-dialog');
  const selected = await open({
    title: '导入工作区',
    multiple: false,
    directory: false,
    filters: [{ name: 'JSON', extensions: ['json'] }],
  });
  const path = Array.isArray(selected) ? selected[0] : selected;
  if (!path) return null;
  const text = await repo.importWorkspace(path);
  return { path, text };
}
