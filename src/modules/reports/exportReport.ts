/**
 * 周报的 Markdown 导出（纯字符串 + 浏览器 API，无 Tauri 命令）。
 *
 * 能力边界：
 * - 「复制 Markdown」用 `navigator.clipboard`，Tauri webview 与浏览器都可用，是主路径；
 * - 「下载 .md」是 Blob + `<a download>`，浏览器可靠，桌面端 webview 可能直接忽略下载
 *   事件（不报错也不落文件），所以界面上两个按钮都保留，出错时提示改用复制；
 * - 不新增任何 Rust 命令：导出不写工作区数据目录，也就没有宿主侧副作用。
 *
 * `notify` 由调用方注入（页面层传 store 的 `notify`），
 * 这样本文件保持零依赖，可以在 node 环境里直接单测字符串产物。
 */

import type { Report } from '../../core/model';
import { REPORT_STATUS_LABELS } from '../../core/model';
import { formatDateTime } from '../../core/utils';
import { periodLabel, periodRange } from './period';
import { REPORT_KIND_LABELS } from './reportView';

export type ReportNotifyTone = 'info' | 'success' | 'error';
export type ReportNotifier = (message: string, tone?: ReportNotifyTone) => void;

/**
 * 章节正文已自带 `### 小标题`（见 draft.ts），这里只给没有标题的正文补上。
 * 空正文（`body.trim() === ''`）返回 null 表示**整节不输出**：
 * 用户点过「清空」的节不应在导出里留下一个孤立标题。
 */
function sectionBlock(title: string, body: string): string | null {
  const trimmed = body.trim();
  if (!trimmed) return null;
  if (/^#{1,6}\s/.test(trimmed)) return trimmed;
  return `### ${title}\n${trimmed}`;
}

function rangeText(report: Report): string {
  const range = periodRange(report.kind, report.period);
  return range ? `${range.start} ～ ${range.end}` : '—';
}

/**
 * 整份报告的 Markdown：标题、期次、报告人、状态、各节正文、末尾生成时间。
 * 正文按 `report.sections` 的现有顺序输出（模板顺序由页面层保证），
 * 空正文的节被跳过，因此「清空」过的节不会留下孤立标题。
 */
export function reportMarkdown(report: Report, now: Date = new Date()): string {
  const label = periodLabel(report.kind, report.period) || report.period;
  const header = [
    // 标题缺失时用期次文案兜底，避免导出文件首行是空的。
    `# ${report.title.trim() || label}`,
    '',
    `- 期次：${label}（${rangeText(report)}）`,
    `- 报告人：${report.author.trim() ? report.author.trim() : '未填写'}`,
    `- 状态：${REPORT_STATUS_LABELS[report.status]}`,
  ];
  if (report.status === 'final' && report.finalizedAt) {
    header.push(`- 定稿时间：${formatDateTime(report.finalizedAt)}`);
  }
  const blocks = report.sections
    .map((section) => sectionBlock(section.title, section.body))
    .filter((block): block is string => block !== null);
  const tail = ['---', '', `生成时间：${formatDateTime(now.toISOString())}`, ''];
  return [...header, '', ...blocks.flatMap((block) => [block, '']), ...tail].join('\n');
}

/** 文件名：期次 + 粒度，标题不进文件名（含空格与中文标点，越长越难在终端里用）。 */
export function reportFileName(report: Report): string {
  const base = `${report.period}-${REPORT_KIND_LABELS[report.kind]}`;
  return `${base.replace(/[\\/:*?"<>|\s]+/g, '-')}.md`;
}

/**
 * 复制到剪贴板。成功返回 true；失败（无剪贴板权限 / 非安全上下文）返回 false 并 notify 提示。
 */
export async function copyReportMarkdown(
  report: Report,
  notify?: ReportNotifier,
  now: Date = new Date(),
): Promise<boolean> {
  const markdown = reportMarkdown(report, now);
  try {
    const clipboard = typeof navigator === 'undefined' ? undefined : navigator.clipboard;
    if (!clipboard || typeof clipboard.writeText !== 'function') {
      throw new Error('当前环境不支持剪贴板');
    }
    await clipboard.writeText(markdown);
    notify?.('已复制 Markdown 到剪贴板', 'success');
    return true;
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    notify?.(`复制失败：${reason}（可改用「下载 .md」）`, 'error');
    return false;
  }
}

/**
 * 触发 `.md` 下载。返回是否成功「发起」下载：
 * webview 忽略 `<a download>` 时不会抛错，所以这里只能保证发起动作成功，
 * 界面提示语按「若未生成文件，请改用复制」写，不谎报结果。
 */
export function downloadReportMarkdown(
  report: Report,
  notify?: ReportNotifier,
  now: Date = new Date(),
): boolean {
  try {
    if (typeof document === 'undefined' || typeof URL.createObjectURL !== 'function') {
      throw new Error('当前环境不支持文件下载');
    }
    const blob = new Blob([reportMarkdown(report, now)], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = reportFileName(report);
    anchor.rel = 'noopener';
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    // 立刻 revoke 会让部分 webview 拿不到数据，交给下一个宏任务回收。
    window.setTimeout(() => URL.revokeObjectURL(url), 0);
    notify?.('已发起 Markdown 下载；若浏览器未保存文件，请改用「复制 Markdown」', 'info');
    return true;
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    notify?.(`下载失败：${reason}，请改用「复制 Markdown」`, 'error');
    return false;
  }
}
