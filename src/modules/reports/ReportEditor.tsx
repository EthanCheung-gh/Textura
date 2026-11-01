/**
 * 中栏：标题 / 报告人 + 按模板顺序排列的各节正文。
 *
 * 输入全部是「受控 + 本地缓冲」：本组件不碰 store，
 * 每个 onChange 只把新值交给页面层（页面层做 600ms 防抖后再整份 `updateReport`）。
 * `report.status === 'final'` 时整块只读：输入 readOnly、按钮 disabled。
 *
 * 每节工具条的「AI 参考」只回调 `onAiSection(key)`：页面层负责切到右栏的 AI 标签并
 * 把这一节设为生成目标；参考结果只进右栏，不会直接改正文。
 *
 * 可访问名：三个节内按钮的可见文案（「重新汇总 / 清空 / AI 参考」）在每节都重复，
 * 因此都带 `aria-label={`<动作>：<节名>`}`（文案由 `reportView.sectionActionAriaLabel`
 * 统一生成），屏幕阅读器与语音控制才能区分是哪一节；可见文案与视觉不变。
 */
import { useMemo } from 'react';
import type { Report, ReportSectionOrigin } from '../../core/model';
import { REPORT_STATUS_LABELS } from '../../core/model';
import { formatDateTime } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import type { BadgeTone } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { Field, TextArea, TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import type { ReportTemplate } from './draft';
import { periodLabel } from './period';
import { orderedSections, sectionActionAriaLabel, sectionAiAriaLabel, wordCount } from './reportView';
import type { ReportDraft } from './reportView';

const ORIGIN_BADGES: Record<ReportSectionOrigin, { label: string; tone: BadgeTone }> = {
  auto: { label: '自动汇总', tone: 'neutral' },
  manual: { label: '已手改', tone: 'accent' },
  ai: { label: 'AI 生成', tone: 'info' },
};

/** 正文行数自适应，最长 22 行后内部滚动，避免长报告把页面撑成几千像素。 */
function rowsFor(body: string): number {
  const lines = body ? body.split('\n').length : 1;
  return Math.min(22, Math.max(6, lines + 1));
}

export interface ReportEditorProps {
  report: Report;
  draft: ReportDraft;
  template: ReportTemplate;
  readOnly: boolean;
  onTitleChange: (value: string) => void;
  onAuthorChange: (value: string) => void;
  onSectionChange: (key: string, body: string) => void;
  onRebuildSection: (key: string) => void;
  onClearSection: (key: string) => void;
  /** 打开右栏「AI 参考」并针对本节生成一次参考稿（结果只进参考区）。 */
  onAiSection: (key: string) => void;
  onCopyMarkdown: () => void;
  onDownloadMarkdown: () => void;
}

export function ReportEditor({
  report,
  draft,
  template,
  readOnly,
  onTitleChange,
  onAuthorChange,
  onSectionChange,
  onRebuildSection,
  onClearSection,
  onAiSection,
  onCopyMarkdown,
  onDownloadMarkdown,
}: ReportEditorProps) {
  // 草稿正文可能是「模板改版前」生成的，缺节时用模板标题兜底，不让编辑区少一节。
  const sections = useMemo(
    () => orderedSections(template, { ...report, sections: draft.sections }),
    [template, report, draft.sections],
  );
  const words = useMemo(() => wordCount(draft), [draft]);
  const label = periodLabel(report.kind, report.period) || report.period;

  return (
    <section className="reports-editor" aria-label="报告编辑区">
      <div className="reports-editor-toolbar">
        <div className="reports-editor-fields">
          <Field label="标题" htmlFor="report-title">
            <TextInput
              id="report-title"
              value={draft.title}
              readOnly={readOnly}
              onChange={(event) => onTitleChange(event.target.value)}
              placeholder="报告标题"
            />
          </Field>
          <Field label="报告人" htmlFor="report-author">
            <TextInput
              id="report-author"
              value={draft.author}
              readOnly={readOnly}
              onChange={(event) => onAuthorChange(event.target.value)}
              placeholder="填写报告人，留空表示未填"
            />
          </Field>
        </div>

        <div className="reports-editor-export">
          {/* 桌面端 webview 可能忽略 <a download>，复制是主路径，下载是补充。 */}
          <Button
            variant="primary"
            size="sm"
            iconLeft={<Icon name="doc" size={14} />}
            onClick={onCopyMarkdown}
          >
            复制 Markdown
          </Button>
          <Button variant="secondary" size="sm" onClick={onDownloadMarkdown}>
            下载 .md
          </Button>
          <span className="reports-export-hint">下载未落文件时，请改用复制</span>
        </div>
      </div>

      <div className="reports-editor-meta">
        <span>{label}</span>
        <Badge tone={report.status === 'final' ? 'ok' : 'warn'}>
          {REPORT_STATUS_LABELS[report.status]}
        </Badge>
        <span>{words} 字</span>
        {readOnly && report.finalizedAt ? (
          <span className="reports-editor-finalized">
            定稿于 {formatDateTime(report.finalizedAt)} · 内容已冻结
          </span>
        ) : (
          <span className="reports-editor-saving">编辑后自动保存</span>
        )}
      </div>

      <div className="reports-sections">
        {sections.map((section) => {
          const origin = ORIGIN_BADGES[section.origin] ?? ORIGIN_BADGES.auto;
          return (
            <article className="reports-section" key={section.key}>
              <div className="reports-section-head">
                <h3 className="reports-section-title">{section.title}</h3>
                <div className="reports-section-actions">
                  <Badge tone={origin.tone}>{origin.label}</Badge>
                  {readOnly ? null : (
                    <>
                      <Button
                        variant="ghost"
                        size="sm"
                        aria-label={sectionActionAriaLabel('rebuild', section.title)}
                        onClick={() => onRebuildSection(section.key)}
                        title="用当前工作区数据重写本节（会覆盖手写内容）"
                      >
                        重新汇总
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={!section.body.trim()}
                        aria-label={sectionActionAriaLabel('clear', section.title)}
                        onClick={() => onClearSection(section.key)}
                        title="清空本节正文"
                      >
                        清空
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        aria-label={sectionAiAriaLabel(section.title)}
                        onClick={() => onAiSection(section.key)}
                        title="让大模型基于本期数据生成这一节的参考稿（只进右栏参考区，不改正文）"
                      >
                        AI 参考
                      </Button>
                    </>
                  )}
                </div>
              </div>
              <TextArea
                className="reports-section-body"
                aria-label={section.title}
                value={section.body}
                rows={rowsFor(section.body)}
                readOnly={readOnly}
                spellCheck={false}
                onChange={(event) => onSectionChange(section.key, event.target.value)}
              />
            </article>
          );
        })}
      </div>
    </section>
  );
}
