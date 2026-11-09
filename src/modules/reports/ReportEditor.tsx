/**
 * 中栏：标题 / 报告人 + 各节正文（存储顺序即展示顺序；模板缺节按相对位置补齐）。
 *
 * 输入全部是「受控 + 本地缓冲」：本组件不碰 store，
 * 每个 onChange 只把新值交给页面层（页面层做 600ms 防抖后再整份 `updateReport`）。
 * `report.status === 'final'` 时整块只读：输入 readOnly、按钮 disabled。
 *
 * 每节工具条的「AI 参考」只回调 `onAiSection(key)`：页面层负责切到右栏的 AI 标签并
 * 把这一节设为生成目标；参考结果只进右栏，不会直接改正文。
 *
 * 可访问名：节内按钮的可见文案（「重新汇总 / 清空 / AI 参考 / 上移 / 下移 / 删除」）
 * 在每节都重复，因此都带 `aria-label={`<动作>：<节名>`}`（文案由
 * `reportView.sectionActionAriaLabel` 统一生成），屏幕阅读器与语音控制才能区分是哪一节；
 * 可见文案与视觉不变。
 *
 * 章节集合（自定义章节）：本组件只做「看得见、点得动」，增删改排全部回调页面层，
 * 写回用的一定是**存储数组**（`draft.sections`），而不是这里展示用的 `orderedSections`
 * 结果——展示列表里补出来的模板空节不许落盘（见 `sections.ts` 文件头第 2 条）。
 * 展示顺序与存储顺序一致，所以上移 / 下移只对「已经写进报告」的节开放：补出来的空节
 * 在存储里没有位置，移动它无处可写，按钮直接禁用，避免点了没反应。
 * 已知限制（产品层面，本次不修）：下移一格换的是**存储里**的相邻位置，若这一节与它存储里的
 * 下一节之间正好夹着一个补出来的占位节，屏幕上看起来会像跳过了两行；反向的上移同理。
 * 要根治得先让占位节也参与排序，那是另一轮契约改动，这里只记下来免得被当成 bug 反复报。
 *
 * 章节数有存储上限（`core/repo` 的 `MAX_REPORT_SECTIONS`）：到顶后「添加章节」置灰，
 * 因为再写进去的一节会在下次加载被裁掉（见 `sections.canAddSection`）。
 *
 * 自建节标题的长度与空白由**编辑器写入**统一规范化（`sections.renameSection` /
 * `sections.addSection`，上限 `MAX_SECTION_TITLE_CHARS`）：本组件的 `maxLength` 只是
 * 挡手输与粘贴的防御纵深，不是唯一口径。
 *
 * 但「标题永远是单行且不超长」只是**写入口**的承诺，不是全链路的存储不变量：AI、导入、
 * 脚本写进来的标题**不会**在加载时被改写，它们照原样躺在 `report.sections[].title` 里。
 * 兜底分三层，谁都不依赖别人先做过：编辑器写入做规范化；导出层把标题**压成一行**再拼进
 * `### `（不裁剪、不加省略号，不吞用户文字）；AI 提示层（`prompts.sectionTitleText`）
 * 另按自己的预算裁短。所以这里显示超长 / 带空白的标题是预期内的，不是漏了规范化。
 *
 * 每节的「编辑 / 预览」：预览只替换正文的 `<TextArea>`，节头、徽标、操作按钮、字数、
 * 防抖与写回路径全都不变——预览是**纯展示**，不参与存储，也不影响导出（导出永远是原始
 * Markdown 文本）。默认全部「编辑」：用户点进报告是要改字的，预览是按需查看。
 * 定稿（`report.status === 'final'`）时强制预览、不给切换：内容已冻结，这时「读」比
 * 「改」更重要，也就没有编辑态可言。
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { Report, ReportSectionOrigin } from '../../core/model';
import { REPORT_STATUS_LABELS } from '../../core/model';
// 上限与存储层同源：提示语里的数字由它插值，不另写一份 40（见 `SECTION_LIMIT_HINT`）。
// `core/repo` 不 import `modules/reports`，这条依赖不构成环（`sections.ts` 也这么取）。
import { MAX_REPORT_SECTIONS } from '../../core/repo';
import { formatDateTime } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import type { BadgeTone } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { Field, TextArea, TextInput } from '../../ui/Field';
import { Segmented } from '../../ui/Segmented';
import type { SegmentedOption } from '../../ui/Segmented';
import { Icon } from '../../ui/icons';
import type { ReportTemplate } from './draft';
import { MarkdownView } from './MarkdownView';
import { periodLabel } from './period';
import {
  addSectionAriaLabel,
  orderedSections,
  sectionActionAriaLabel,
  sectionAiAriaLabel,
  wordCount,
} from './reportView';
import type { ReportDraft } from './reportView';
import { MAX_SECTION_TITLE_CHARS, canAddSection, isCustomSectionKey } from './sections';

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

type SectionMode = 'edit' | 'preview';

/** 每节的编辑 / 预览切换：沿用页面里已有的 `Segmented`（sm），不另造一套控件。 */
const SECTION_MODE_OPTIONS: SegmentedOption<SectionMode>[] = [
  { value: 'edit', label: '编辑', title: '直接改这一节的 Markdown 正文' },
  { value: 'preview', label: '预览', title: '按排版看这一节（只读，不改内容）' },
];

/** 空集合常量：默认「没有一节在预览」，不必每次渲染都新建 Set。 */
const NO_PREVIEW_KEYS: ReadonlySet<string> = new Set<string>();

/**
 * 章节数到达存储上限后，「添加章节」的 `title` 提示语。
 *
 * 数字由 `core/repo` 的 `MAX_REPORT_SECTIONS` **插值**而来，不再手写：加载时每份报告的
 * `sections` 会被裁到该上限，UI 多放行一节，用户就会看到「加好了 → 下次打开没了」。
 * 文案只出现一处，`title` 与可访问名不会各说各话；上限调大调小时提示语自己跟着走，
 * 也就不会出现「常量改了、这段话还写着旧数字」的走样。
 *
 * 措辞只承诺界面真的做得到的事：编辑器只给**自定义章节**提供删除按钮（模板节删了会被
 * `displaySections` 重新补齐，所以没有删除键）。已知限制（本次不修）：若一份报告的
 * `MAX_REPORT_SECTIONS` 节全都不是 `custom-*`（例如历史模板遗留 key 占满），界面上没有
 * 一节可删，这条提示就成了死胡同——只能靠导入 / 撤销之类的工作区级路径收拾。提示先写
 * 准确，死胡同本身留待后续。
 *
 * 只进 `title`，**不进** `aria-label`：置灰不该改名，可访问名在两种状态下都保持
 * `addSectionAriaLabel()`（含可见文案「添加章节」）。否则屏幕阅读器读到的名字里没有
 * 可见文字，违反 WCAG 2.5.3 label-in-name——本编辑器其余按钮都在守这条。
 * 禁用态本身由 `disabled` 属性宣告，原因说明放 `title` 足够。
 */
const SECTION_LIMIT_HINT = `报告最多 ${MAX_REPORT_SECTIONS} 节（存储上限）：只有自定义章节可以删除`;

interface SectionTitleInputProps {
  title: string;
  /** 刚点「添加章节」建出来的那一节：挂载后自动聚焦，用户可以直接改名。 */
  autoFocus: boolean;
  onCommit: (title: string) => void;
}

/**
 * 自建章节的标题输入（模板节标题是口径来源，永不进入这里）。
 *
 * 本地 state 是刻意的：用户逐字输入期间**一次都不写盘**，只在失焦或回车时提交一次，
 * 否则每敲一个字就会刷新 `updatedAt`、改写 origin，还会把 80 步撤销历史冲掉。
 * Esc 放弃本次输入。为什么用 ref 记「放弃」：真正的提交发生在 blur 回调里，
 * 那时已经读不到按键事件，只能靠 ref 把这个意图传过去。
 *
 * 标题长度/空白有**两层**约束，是刻意的防御纵深：这里的 `maxLength` 只挡住手输与粘贴，
 * 让输入框在敲的过程中就到不了上限；真正的规范化在**编辑器写入**那一层
 * （`sections.renameSection`：压空白、去首尾、按 `MAX_SECTION_TITLE_CHARS` 裁剪）。
 * 别把这条当成全链路的保证：AI、导入、脚本写进来的标题在加载时不会被改写，它们由导出层
 * （压成一行输出）与 AI 提示层（独立裁剪）各自兜住——输入框里原样显示是预期行为。
 */
function SectionTitleInput({ title, autoFocus, onCommit }: SectionTitleInputProps) {
  const [value, setValue] = useState(title);
  /** 输入框是否持有焦点：重新渲染（store 回写、撤销）时不打断正在输入的人。 */
  const focusedRef = useRef(false);
  const revertRef = useRef(false);

  // 外部改了标题（撤销、重新打开报告、别处改名）时同步本地值；正在输入时不覆盖。
  useEffect(() => {
    if (!focusedRef.current) setValue(title);
  }, [title]);

  /** 失焦 / 回车提交：只在真的变了时回调；空标题就地还原，不把无名章节留在列表里。 */
  const commit = () => {
    if (revertRef.current) {
      revertRef.current = false;
      setValue(title);
      return;
    }
    const next = value.trim();
    if (!next || next === title) {
      setValue(title);
      return;
    }
    onCommit(next);
  };

  return (
    <TextInput
      className="reports-section-title-input"
      value={value}
      autoFocus={autoFocus}
      maxLength={MAX_SECTION_TITLE_CHARS}
      aria-label={`章节标题：${title}`}
      title="改章节名：回车或失焦保存，Esc 取消"
      spellCheck={false}
      onChange={(event) => setValue(event.target.value)}
      onFocus={() => {
        focusedRef.current = true;
      }}
      onBlur={() => {
        focusedRef.current = false;
        commit();
      }}
      onKeyDown={(event) => {
        if (event.key === 'Enter') {
          event.preventDefault();
          // 回车等价于「提交并离开」：走同一条 blur → commit 路径，不另写一套逻辑。
          event.currentTarget.blur();
        } else if (event.key === 'Escape') {
          revertRef.current = true;
          event.currentTarget.blur();
        }
      }}
    />
  );
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
  /** 上移（-1）/ 下移（+1）本节：改动的是存储顺序，导出也跟着变。 */
  onMoveSection: (key: string, delta: -1 | 1) => void;
  /** 改自建节标题（模板节不可改名）；只在失焦 / 回车时调用一次。 */
  onRenameSection: (key: string, title: string) => void;
  /** 删除自建节（模板节删了会被补齐，因此不提供删除）。 */
  onRemoveSection: (key: string) => void;
  /** 追加一个自建节，返回新节 key：本组件用它把焦点落到新节的标题框。 */
  onAddSection: () => string | null;
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
  onMoveSection,
  onRenameSection,
  onRemoveSection,
  onAddSection,
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
  /**
   * 还能不能加自建节：只数**存储数组**（`draft.sections`），展示列表里补出来的模板空节
   * 不落盘、也不占上限。到顶就置灰按钮，而不是让用户加一节再被加载期裁掉。
   */
  const canAddMore = canAddSection(draft.sections);

  /** key → 存储下标：上移 / 下移的边界判定必须看存储顺序，展示列表里可能夹着补出来的空节。 */
  const storedIndex = useMemo(() => {
    const map = new Map<string, number>();
    draft.sections.forEach((section, index) => {
      if (!map.has(section.key)) map.set(section.key, index);
    });
    return map;
  }, [draft.sections]);

  /** 刚添加的章节 key：挂载后自动聚焦一次，随后清空（否则之后切报告会再抢焦点）。 */
  const [pendingFocus, setPendingFocus] = useState<string | null>(null);
  useEffect(() => {
    if (pendingFocus !== null) setPendingFocus(null);
  }, [pendingFocus]);

  /**
   * 模板里的节 key 集合（每渲染算一次，供整张列表复用）。
   *
   * 「重新汇总」只在**模板节**上渲染：这个动作要按模板标题重算正文，`rebuildSection`
   * 对模板外的 key 一律返回 null，点了只会弹「未知章节：…」。以前按 `isCustomSectionKey`
   * 反着判断，历史模板遗留的非 `custom-*` key 因此会拿到一个必然失败的按钮；这里改成
   * 正向判据，自建节与遗留节都只保留「清空 / AI 参考」。
   */
  const templateKeys = useMemo(
    () => new Set(template.sections.map((entry) => entry.key)),
    [template],
  );

  /**
   * 预览态只记「哪些节在预览」：集合为空即全部在编辑，于是新增章节天然默认编辑，
   * 不需要在 `onAddSection` 里补一次「设为编辑」。
   *
   * key 会跨报告重复（`overview` / `custom-1`），所以连 `report.id` 一起存：换一份报告时
   * id 不匹配就直接按「全部编辑」展示。这样不用 `useEffect` 重置 state（那会多一帧
   * 「上一份报告的预览态」闪烁），也不会把 A 报告的预览选择带到 B 报告上。
   */
  const [previewState, setPreviewState] = useState<{ reportId: string; keys: ReadonlySet<string> }>(
    () => ({ reportId: report.id, keys: NO_PREVIEW_KEYS }),
  );
  const previewKeys = previewState.reportId === report.id ? previewState.keys : NO_PREVIEW_KEYS;

  const handleModeChange = (key: string, mode: SectionMode) => {
    setPreviewState((previous) => {
      const keys = new Set(previous.reportId === report.id ? previous.keys : NO_PREVIEW_KEYS);
      if (mode === 'preview') keys.add(key);
      else keys.delete(key);
      return { reportId: report.id, keys };
    });
  };

  const handleAdd = () => {
    const key = onAddSection();
    if (key) setPendingFocus(key);
  };

  /**
   * 删除一节：先把它从预览集合里摘掉，再通知页面层。
   *
   * 自建 key 会被**复用**（`nextCustomKey` 取最小空位：删掉 `custom-1` 再加一节还是
   * `custom-1`）。预览态只按 key 记账，不清理的话新节一挂载就继承上一节的「预览」——
   * 一个刚建好的空节顶着预览模式，用户连输入框都看不见。只在同一份报告内清理
   * （`reportId` 不同说明预览态本就不生效，无需写 state 触发多余渲染）。
   */
  const handleRemove = (key: string) => {
    setPreviewState((previous) => {
      if (previous.reportId !== report.id || !previous.keys.has(key)) return previous;
      const keys = new Set(previous.keys);
      keys.delete(key);
      return { reportId: previous.reportId, keys };
    });
    onRemoveSection(key);
  };

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
          const custom = isCustomSectionKey(section.key);
          // -1 表示这一节只存在于展示列表（旧报告缺的模板节，还没写进存储）：移动无处可写。
          const index = storedIndex.get(section.key) ?? -1;
          const canMoveUp = index > 0;
          const canMoveDown = index >= 0 && index < draft.sections.length - 1;
          // 定稿报告强制预览（内容冻结，没有编辑态）；草稿按本节自己的开关。
          const previewing = readOnly || previewKeys.has(section.key);
          return (
            <article className="reports-section" key={section.key}>
              <div className="reports-section-head">
                {custom && !readOnly ? (
                  // 自建节：标题就地可改。仍然用 h3 包住输入框——标题文字换成文本框，
                  // 但「每节一个标题」的文档大纲不能因此断掉（屏幕阅读器按标题跳读）。
                  // 输入框只在失焦 / 回车时提交，见 `SectionTitleInput`。
                  <h3 className="reports-section-title reports-section-title--editing">
                    <SectionTitleInput
                      title={section.title}
                      autoFocus={pendingFocus === section.key}
                      onCommit={(title) => onRenameSection(section.key, title)}
                    />
                  </h3>
                ) : (
                  <h3 className="reports-section-title">{section.title}</h3>
                )}
                <div className="reports-section-actions">
                  {/* 定稿后不给切换：内容已冻结，预览是唯一有意义的形态。 */}
                  {readOnly ? null : (
                    <Segmented<SectionMode>
                      className="reports-section-mode"
                      size="sm"
                      ariaLabel={`${section.title}：编辑或预览`}
                      value={previewing ? 'preview' : 'edit'}
                      onChange={(mode) => handleModeChange(section.key, mode)}
                      options={SECTION_MODE_OPTIONS}
                    />
                  )}
                  <Badge tone={origin.tone}>{origin.label}</Badge>
                  {readOnly ? null : (
                    <>
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={!canMoveUp}
                        aria-label={sectionActionAriaLabel('moveUp', section.title)}
                        onClick={() => onMoveSection(section.key, -1)}
                        title="上移一节，顺序会写进导出"
                      >
                        上移
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={!canMoveDown}
                        aria-label={sectionActionAriaLabel('moveDown', section.title)}
                        onClick={() => onMoveSection(section.key, 1)}
                        title="下移一节，顺序会写进导出"
                      >
                        下移
                      </Button>
                      {/* 模板节没有删除：删掉也会被 displaySections 补回来，留着按钮等于骗人。 */}
                      {custom ? (
                        <Button
                          variant="ghost"
                          size="sm"
                          className="reports-section-remove"
                          aria-label={sectionActionAriaLabel('remove', section.title)}
                          onClick={() => handleRemove(section.key)}
                          title="删除本节（可用 Ctrl/⌘+Z 撤销）"
                        >
                          删除
                        </Button>
                      ) : null}
                      {/* 重新汇总按模板标题重算，模板外（自建 / 历史遗留）的 key 没有 builder：
                          隐藏而不是渲染一个点了必然报「未知章节」的死按钮。 */}
                      {templateKeys.has(section.key) ? (
                        <Button
                          variant="ghost"
                          size="sm"
                          aria-label={sectionActionAriaLabel('rebuild', section.title)}
                          onClick={() => onRebuildSection(section.key)}
                          title="用当前工作区数据重写本节（会覆盖手写内容）"
                        >
                          重新汇总
                        </Button>
                      ) : null}
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
              {previewing ? (
                // 预览只替换正文框：节头、徽标、操作、字数、防抖与写回路径都不动。
                // 容器带 role="region" + 可访问名，屏幕阅读器能分辨这是哪一节的预览。
                <MarkdownView body={section.body} ariaLabel={`预览：${section.title}`} />
              ) : (
                <TextArea
                  className="reports-section-body"
                  aria-label={section.title}
                  value={section.body}
                  rows={rowsFor(section.body)}
                  readOnly={readOnly}
                  spellCheck={false}
                  onChange={(event) => onSectionChange(section.key, event.target.value)}
                />
              )}
            </article>
          );
        })}

        {/* 定稿后隐藏：新增章节会直接改写已冻结的内容。 */}
        {readOnly ? null : (
          <div className="reports-section-add">
            <Button
              variant="secondary"
              size="sm"
              iconLeft={<Icon name="plus" size={14} />}
              disabled={!canAddMore}
              aria-label={addSectionAriaLabel()}
              onClick={handleAdd}
              title={canAddMore ? '在列表末尾追加一个自定义章节' : SECTION_LIMIT_HINT}
            >
              添加章节
            </Button>
          </div>
        )}
      </div>
    </section>
  );
}
