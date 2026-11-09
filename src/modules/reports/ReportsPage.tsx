/**
 * 周报 / 月报 / 季报页面（包 C：只做 UI 接线与交互，不重写模型层与聚合层）。
 *
 * 三栏：期次列表 → 正文编辑 → 数据源 / AI 参考。状态与数据流：
 * - 「哪一期 / 哪份报告」是页面状态（kind / period / selectedId）；
 * - 正文与标题、报告人先落在本地草稿缓冲（`draftRef` 是权威副本），
 *   输入 600ms 防抖后才 `updateReport`，避免每个按键都写 store（80 步历史会被冲掉）；
 * - 切期 / 切报告 / 定稿 / 页面卸载（切路由）前一律 `flush()` 把未落盘的编辑写回；
 * - 「插入 / 清空 / 重新汇总」是离散动作，连同缓冲里的标题、报告人立即落盘一次；
 * - 正文重算一律走聚合层的 `buildReportSections` / `rebuildSection`。聚合层每次调用都重算
 *   （没有跨调用缓存），记忆化只发生在页面层：`buildReportSections` / `collectFactsDetailed`
 *   都包在 `useMemo([workspace, kind, period])` 里；
 * - 右栏两个标签：数据源（素材插入）与 AI 参考。AI 请求的取消句柄在本层（`aiHandle`），
 *   切报告 / 切期次 / 卸载都会 `abort()`；**AI 结果只进参考区**，采用时由本层用
 *   `mergeSectionBodies(origin: 'ai')` + `commitNow({ sections })` 写回正文。
 * - 写回的目标节可能只存在于**展示列表**（旧报告缺的模板节由 `displaySections` 补出来），
 *   所以每条写回路径都先 `ensureSection` 把它按展示位置落进存储，再 merge：直接 merge
 *   会追加到末尾，既重排整份列表，也让正在输入的输入框失焦。
 */
import clsx from 'clsx';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Report, ReportPatch, ReportPeriodKind, ReportSection } from '../../core/model';
import { REPORT_STATUS_LABELS } from '../../core/model';
import { nowIso } from '../../core/utils';
import { useWorkspace } from '../../core/store';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { IconButton } from '../../ui/IconButton';
import { Modal } from '../../ui/Modal';
import { Segmented } from '../../ui/Segmented';
import type { SegmentedOption } from '../../ui/Segmented';
import { buildReportSections, rebuildSection, templateById, templateFor } from './draft';
import type { ReportTemplate } from './draft';
import { collectFactsDetailed } from './facts';
import type { FactKind, ReportFact } from './facts';
import { currentPeriodKey, periodLabel, periodRange, shiftPeriod } from './period';
import { ReportEditor } from './ReportEditor';
import { ReportAiPanel } from './ReportAiPanel';
import type { AiTarget } from './ReportAiPanel';
import { ReportIndex } from './ReportIndex';
import { ReportSourcePanel } from './ReportSourcePanel';
import { copyReportMarkdown, downloadReportMarkdown } from './exportReport';
import {
  appendLine,
  draftFromReport,
  filterReports,
  findReport,
  mergeSectionBodies,
  orderedSections,
  reportsOfKind,
  sectionBodyChanged,
  sortReportsDesc,
  textFieldChanged,
} from './reportView';
import type { ReportDraft } from './reportView';
import { addSection, canAddSection, ensureSection, moveSection, removeSection, renameSection } from './sections';
import './reports.css';

const KIND_OPTIONS: SegmentedOption<ReportPeriodKind>[] = [
  { value: 'week', label: '周报' },
  { value: 'month', label: '月报' },
  { value: 'quarter', label: '季报' },
];

/** 右栏两个标签：默认数据源，切到 AI 才发请求。 */
type SideTab = 'source' | 'ai';

const SIDE_TABS: SegmentedOption<SideTab>[] = [
  { value: 'source', label: '数据源' },
  { value: 'ai', label: 'AI 参考' },
];

/** 「插入素材」落到哪一节：fact.kind → 模板节 key（见 draft.ts 的模板定义）。 */
const FACT_SECTION_KEY: Record<FactKind, string> = {
  completed: 'progress',
  risk: 'risks',
  kr: 'metrics',
  run: 'metrics',
  nextUp: 'next',
};

/** 正文落盘防抖窗口。 */
const SAVE_DELAY_MS = 600;

/**
 * 章节顺序是否真的动了。
 *
 * `sections.moveSection` 对空操作（已到两端 / key 不存在）也返回新数组（见该文件头的契约），
 * 所以不能用「同一引用」判断，只能按 key 序列比较——上移 / 下移只改顺序，不动标题与正文。
 */
function sectionOrderChanged(before: readonly ReportSection[], after: readonly ReportSection[]): boolean {
  if (before.length !== after.length) return true;
  return before.some((section, index) => section.key !== after[index].key);
}

type ConfirmAction =
  | { type: 'rebuild'; key: string }
  | { type: 'finalize' }
  | { type: 'delete' };

export function ReportsPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const createReport = useWorkspace((state) => state.createReport);
  const updateReport = useWorkspace((state) => state.updateReport);
  const finalizeReport = useWorkspace((state) => state.finalizeReport);
  const reopenReport = useWorkspace((state) => state.reopenReport);
  const deleteReport = useWorkspace((state) => state.deleteReport);
  const notify = useWorkspace((state) => state.notify);
  const setUi = useWorkspace((state) => state.setUi);

  const reports = useMemo(() => workspace.reports ?? [], [workspace.reports]);

  const [kind, setKind] = useState<ReportPeriodKind>('week');
  const [period, setPeriod] = useState<string>(() => currentPeriodKey('week'));
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [draft, setDraft] = useState<ReportDraft | null>(null);
  const [confirm, setConfirm] = useState<ConfirmAction | null>(null);
  const [sideTab, setSideTab] = useState<SideTab>('source');
  /** AI 目标：整份，或编辑器里刚点开的那一节（`requestId` 递增，面板据此只发一次）。 */
  const [aiTarget, setAiTarget] = useState<AiTarget>({ mode: 'report' });

  /** 草稿缓冲的权威副本：事件处理器与定时器都读它，避免闭包读到过期的 state。 */
  const draftRef = useRef<ReportDraft | null>(null);
  /** 还在防抖窗口里的补丁（同一份报告多次编辑合并成一次写入）。 */
  const pendingRef = useRef<{ id: string; patch: ReportPatch } | null>(null);
  const timerRef = useRef<number | null>(null);
  /** 已经从 store 同步过的版本标记（`id:updatedAt`），防止自己写回后覆盖输入。 */
  const syncedRef = useRef<string | null>(null);
  /** AI 请求的在途控制器：同一时刻只允许一个在途请求。 */
  const aiAbortRef = useRef<AbortController | null>(null);
  /** 单节入口的点击序号：同一个按钮连点两次也要各发一次请求。 */
  const aiRequestSeq = useRef(0);

  const range = useMemo(() => periodRange(kind, period), [kind, period]);
  const label = periodLabel(kind, period);

  const selectedReport = useMemo(
    () => (selectedId ? reports.find((report) => report.id === selectedId) ?? null : null),
    [reports, selectedId],
  );

  /** 已定稿：正文、素材插入与 AI 采用全部冻结。 */
  const readOnly = selectedReport?.status === 'final';

  const template = useMemo<ReportTemplate>(() => {
    if (!selectedReport) return templateFor(kind);
    const candidate = templateById(selectedReport.templateId);
    // 模板与报告粒度不一致（历史数据 / 手改过 templateId）时按粒度回落。
    return candidate.kind === selectedReport.kind ? candidate : templateFor(selectedReport.kind);
  }, [selectedReport, kind]);

  /*
   * 10k 条目下这两个聚合各 4–8ms，必须记忆化：输入正文时 workspace 每次落盘都会变，
   * 但只有 (workspace, kind, period) 变了才需要重算。注意聚合层自身不做缓存，
   * 缓存只在这一层；空态下 facts 与 generatedSections 各跑一次（后者内部要再汇总一次事实），
   * 聚合层没有注入 facts 的入口，因此保持重复计算。
   */
  const facts = useMemo(
    () => (range ? collectFactsDetailed(workspace, kind, period) : null),
    [workspace, kind, period, range],
  );
  const generatedSections = useMemo(
    () => (range && !selectedReport ? buildReportSections(workspace, kind, period) : null),
    [workspace, kind, period, range, selectedReport],
  );

  const kindReports = useMemo(() => reportsOfKind(reports, kind), [reports, kind]);
  const visibleReports = useMemo(
    () => sortReportsDesc(filterReports(kindReports, query)),
    [kindReports, query],
  );

  /**
   * 交给 AI 面板的章节列表：与编辑器同一口径（`orderedSections`），
   * 自定义章节因此也会出现在面板的「选择章节 / 整份生成」里。
   * 注意这只是**展示**列表：写回仍走 `current.sections`（存储数组），
   * 补出来的模板空节不会被采纳动作带进存储。
   */
  const aiSections = useMemo(() => {
    if (!selectedReport || !draft) return [];
    return orderedSections(template, { ...selectedReport, sections: draft.sections });
  }, [draft, selectedReport, template]);

  /* ---------------- 防抖落盘 ---------------- */

  const clearTimer = useCallback(() => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  /** 补丁目标是否仍是现存报告：撤销删除 / 外部删除后 id 就失效了，不能再用它写盘。 */
  const isLiveReport = useCallback(
    // 直接读 store 快照：这里要的是「此刻」是否存在，闭包里的 reports 可能已经过期。
    (id: string) => (useWorkspace.getState().workspace.reports ?? []).some((report) => report.id === id),
    [],
  );

  const writePending = useCallback(() => {
    const pending = pendingRef.current;
    pendingRef.current = null;
    if (!pending) return;
    // 目标报告已消失：丢弃补丁，不用失效 id 调 updateReport。
    if (!isLiveReport(pending.id)) return;
    updateReport(pending.id, pending.patch);
  }, [isLiveReport, updateReport]);

  /** 立刻把防抖窗口里的编辑写回 store。 */
  const flush = useCallback(() => {
    clearTimer();
    writePending();
  }, [clearTimer, writePending]);

  const scheduleSave = useCallback(
    (id: string, patch: ReportPatch) => {
      // 报告已被撤销删除 / 外部删除：不再接受新补丁（草稿缓冲也会在下一轮同步里清掉）。
      if (!isLiveReport(id)) return;
      const previous = pendingRef.current;
      pendingRef.current = {
        id,
        patch: previous && previous.id === id ? { ...previous.patch, ...patch } : { ...patch },
      };
      clearTimer();
      timerRef.current = window.setTimeout(() => {
        timerRef.current = null;
        writePending();
      }, SAVE_DELAY_MS);
    },
    [clearTimer, isLiveReport, writePending],
  );

  /** 离散动作立即落盘：把缓冲里的标题 / 报告人与本次补丁合成一次写入。 */
  const commitNow = useCallback(
    (patch: ReportPatch) => {
      const current = draftRef.current;
      // 报告已消失时同样丢弃（与 flush / scheduleSave 同一道防线）。
      if (!current || !isLiveReport(current.id)) return;
      clearTimer();
      const pending = pendingRef.current;
      pendingRef.current = null;
      updateReport(current.id, {
        ...(pending && pending.id === current.id ? pending.patch : {}),
        ...patch,
      });
    },
    [clearTimer, isLiveReport, updateReport],
  );

  // 切路由会卸载本页：卸载时把未落盘编辑写回，绝不丢字。
  useEffect(() => flush, [flush]);

  /* ---------------- 草稿同步 ---------------- */

  useEffect(() => {
    if (!selectedReport) {
      // 报告消失（撤销删除 / 外部删除 / 切到空期次）：连同未落盘的补丁一起作废，
      // 否则 600ms 定时器或卸载 flush 会拿已失效的 id 去 updateReport。
      clearTimer();
      pendingRef.current = null;
      draftRef.current = null;
      syncedRef.current = null;
      setDraft(null);
      return;
    }
    // 有未落盘编辑时不覆盖输入；落盘后 store 会回写新的 updatedAt，本效果再同步一次。
    if (pendingRef.current) return;
    const token = `${selectedReport.id}:${selectedReport.updatedAt}`;
    if (syncedRef.current === token) return;
    syncedRef.current = token;
    const next = draftFromReport(selectedReport);
    draftRef.current = next;
    setDraft(next);
  }, [clearTimer, selectedReport]);

  // 首次进入 / 换期后当前期次已有报告就直接打开（空态只留给「真的没有」）。
  useEffect(() => {
    if (selectedId) {
      // 选中的报告被撤销 / 重载掉了：清掉选择，下一轮本效果会自动重新选。
      if (!reports.some((report) => report.id === selectedId)) setSelectedId(null);
      return;
    }
    const existing = findReport(reports, kind, period);
    if (existing) setSelectedId(existing.id);
  }, [reports, kind, period, selectedId]);

  /* ---------------- 期次导航 ---------------- */

  const goTo = useCallback(
    (nextKind: ReportPeriodKind, nextPeriod: string) => {
      flush();
      setKind(nextKind);
      setPeriod(nextPeriod);
      setSelectedId(findReport(reports, nextKind, nextPeriod)?.id ?? null);
    },
    [flush, reports],
  );

  const previousPeriod = useMemo(() => shiftPeriod(kind, period, -1), [kind, period]);
  const nextPeriod = useMemo(() => shiftPeriod(kind, period, 1), [kind, period]);

  const handleKindChange = useCallback(
    (nextKind: ReportPeriodKind) => {
      if (nextKind === kind) return;
      goTo(nextKind, currentPeriodKey(nextKind));
    },
    [goTo, kind],
  );

  const handleShift = useCallback(
    (delta: number) => {
      // `shiftPeriod` 返回 null 表示该方向没有合法期次：按钮已禁用，这里再兜一层。
      const target = shiftPeriod(kind, period, delta);
      if (!target) return;
      goTo(kind, target);
    },
    [goTo, kind, period],
  );

  const handleSelect = useCallback(
    (report: Report) => {
      if (report.id === draftRef.current?.id) return;
      flush();
      setSelectedId(report.id);
      setKind(report.kind);
      setPeriod(report.period);
    },
    [flush],
  );

  /* ---------------- AI 参考 ---------------- */

  /** 取消在途 AI 请求（没有在途请求时忽略）。 */
  const abortAi = useCallback(() => {
    aiAbortRef.current?.abort();
    aiAbortRef.current = null;
  }, []);

  /** 新请求前先取消旧的，返回本次请求的 signal。 */
  const beginAi = useCallback((): AbortSignal => {
    abortAi();
    const controller = new AbortController();
    aiAbortRef.current = controller;
    return controller.signal;
  }, [abortAi]);

  const aiHandle = useMemo(() => ({ abort: abortAi, begin: beginAi }), [abortAi, beginAi]);

  // 切报告 / 切期次：取消在途生成，并把目标退回「整份」，不残留上一份报告的节 key。
  // 面板据 `resetKey` 清空参考结果，两者一起构成「切换即重置参考态」。
  useEffect(() => {
    abortAi();
    setAiTarget({ mode: 'report' });
  }, [abortAi, kind, period, selectedId]);

  // 切路由会卸载本页：卸载时取消在途请求（未落盘的编辑由上面的 flush 负责）。
  useEffect(() => abortAi, [abortAi]);

  /** 编辑器每节工具条的「AI 参考」：切到 AI 标签 + 设为该节目标（面板自动生成一次）。 */
  const handleAiSection = useCallback((key: string) => {
    aiRequestSeq.current += 1;
    setSideTab('ai');
    setAiTarget({ mode: 'section', key, requestId: aiRequestSeq.current });
  }, []);

  const handleOpenSettings = useCallback(() => setUi({ route: 'settings' }), [setUi]);

  /* ---------------- 草稿增删改 ---------------- */

  const patchDraft = useCallback(
    (updater: (current: ReportDraft) => ReportDraft): ReportDraft | null => {
      const current = draftRef.current;
      if (!current) return null;
      const next = updater(current);
      draftRef.current = next;
      setDraft(next);
      return next;
    },
    [],
  );

  /** 目标节的模板标题（旧报告缺这一节时，新节用它而不是用 key 当标题）。 */
  const templateTitle = useCallback(
    (key: string) => template.sections.find((section) => section.key === key)?.title,
    [template],
  );

  /**
   * 某一节当前的标题：草稿优先（**自建节的标题只活在报告里**，模板里没有），
   * 再回落模板标题，最后才用 key 兜底。读 `draftRef` 而不是 state，
   * 保证事件处理器里拿到的总是最新值（与其余处理器同一口径）。
   */
  const sectionTitleOf = useCallback(
    (key: string) =>
      draftRef.current?.sections.find((section) => section.key === key)?.title ??
      templateTitle(key) ??
      key,
    [templateTitle],
  );

  const handleCreate = useCallback(() => {
    if (!range) return;
    const existing = findReport(reports, kind, period);
    if (existing) {
      setSelectedId(existing.id);
      return;
    }
    flush();
    const sections = generatedSections ?? buildReportSections(workspace, kind, period);
    // 标题留给 store 的默认标题（与「2026 年第 44 周报」一致），不在这里再拼一遍。
    const created = createReport({
      kind,
      period,
      templateId: templateFor(kind).id,
      sections,
    });
    setSelectedId(created.id);
    notify(`已生成 ${periodLabel(kind, period)}报草稿`, 'success');
  }, [
    createReport,
    flush,
    generatedSections,
    kind,
    notify,
    period,
    range,
    reports,
    workspace,
  ]);

  const handleTitleChange = useCallback(
    (value: string) => {
      const current = draftRef.current;
      // 值没变（浏览器原生撤销同样会派发一次 onChange）就不写盘：
      // 否则 updatedAt 被刷新、历史里多一条空快照。判据见 `reportView.textFieldChanged`。
      if (!current || !textFieldChanged(current.title, value)) return;
      const next = patchDraft((draft) => ({ ...draft, title: value }));
      if (next) scheduleSave(next.id, { title: value });
    },
    [patchDraft, scheduleSave],
  );

  const handleAuthorChange = useCallback(
    (value: string) => {
      const current = draftRef.current;
      if (!current || !textFieldChanged(current.author, value)) return;
      const next = patchDraft((draft) => ({ ...draft, author: value }));
      if (next) scheduleSave(next.id, { author: value });
    },
    [patchDraft, scheduleSave],
  );

  const handleSectionChange = useCallback(
    (key: string, body: string) => {
      const current = draftRef.current;
      // 正文逐字相同（原生撤销的 onChange）直接返回：不 patch、不排期、不改 origin、
      // 不刷新 updatedAt。判据见 `reportView.sectionBodyChanged`。
      if (!current || !sectionBodyChanged(current, key, body)) return;
      const updatedAt = nowIso();
      const next = patchDraft((draft) => ({
        ...draft,
        sections: mergeSectionBodies(
          // 只存在于展示列表的模板空节先按展示位置落位：否则 merge 会追加到末尾，
          // 列表重排 + 输入框重挂载丢焦点（见 `sections.ensureSection`）。
          ensureSection(draft.sections, template, key, updatedAt),
          key,
          body,
          { origin: 'manual', updatedAt, title: templateTitle(key) },
        ),
      }));
      if (next) scheduleSave(next.id, { sections: next.sections });
    },
    [patchDraft, scheduleSave, template, templateTitle],
  );

  const handleInsertFact = useCallback(
    (fact: ReportFact) => {
      const current = draftRef.current;
      if (!current) return;
      const sectionKey = FACT_SECTION_KEY[fact.kind];
      const updatedAt = nowIso();
      const ensured = ensureSection(current.sections, template, sectionKey, updatedAt);
      const existing = ensured.find((section) => section.key === sectionKey);
      const sections = mergeSectionBodies(
        ensured,
        sectionKey,
        appendLine(existing?.body ?? '', fact.line),
        { origin: 'manual', updatedAt, title: templateTitle(sectionKey) },
      );
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
      notify(`已插入到「${templateTitle(sectionKey) ?? sectionKey}」`, 'success');
    },
    [commitNow, notify, template, templateTitle],
  );

  const handleClearSection = useCallback(
    (key: string) => {
      const current = draftRef.current;
      if (!current) return;
      const updatedAt = nowIso();
      const sections = mergeSectionBodies(
        ensureSection(current.sections, template, key, updatedAt),
        key,
        '',
        { origin: 'manual', updatedAt, title: templateTitle(key) },
      );
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
    },
    [commitNow, template, templateTitle],
  );

  /* ---------------- 章节集合（新增 / 改名 / 移动 / 删除） ---------------- */

  /*
   * 四个处理器都只碰**存储数组**（`current.sections`）：展示列表里补出来的模板空节
   * 不参与写回（见 `sections.ts` 文件头第 2 条）。它们和「清空」一样是离散动作，
   * 因此不走 600ms 防抖，直接 `commitNow` 落一次盘、留一条撤销快照。
   */

  /**
   * 追加一个自建章节，返回它的 key：编辑器据此把焦点落到新节的标题框。
   * 标题用 `sections.ts` 的默认标题（「自定义章节 n」），用户想改就地改。
   */
  const handleAddSection = useCallback((): string | null => {
    const current = draftRef.current;
    if (!current || readOnly) return null;
    // 页面级兜底：置灰的按钮是主闸门，这里再拦一层，保证任何路径（键盘回车、
    // 外部调用）都写不出第 41 节——它下次加载会被裁掉，等于静默丢数据。
    // 到顶就直接返回：不写盘，也不弹提示（禁用态已经说明了原因）。
    if (!canAddSection(current.sections)) return null;
    const sections = addSection(current.sections, nowIso());
    // `addSection` 保证追加在末尾，新节就是最后一个——不靠序号反推 key，契约变了也不会错位。
    const added = sections[sections.length - 1];
    draftRef.current = { ...current, sections };
    setDraft(draftRef.current);
    commitNow({ sections });
    notify(`已添加「${added.title}」，可直接改标题`, 'success');
    return added.key;
  }, [commitNow, notify, readOnly]);

  const handleRenameSection = useCallback(
    (key: string, title: string) => {
      const current = draftRef.current;
      if (!current || readOnly) return;
      const sections = renameSection(current.sections, key, title, nowIso());
      // 空标题 / 模板节 / key 不存在 / 规范化后与存储值相同都是「同一引用」的空操作：
      // 不写盘，也不弹「改好了」。
      if (sections === current.sections) return;
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
      // 提示语里的标题从**刚存回去的数组**里读（`sectionTitleOf` 读 `draftRef.current`），
      // 而不是用入参：入参可能带多余空白，也可能被裁到上限并补了省略号——只有存下来的
      // 那个值才是用户下次打开看到的，提示语跟它不一致就是在报告假消息。
      notify(`已改名为「${sectionTitleOf(key)}」`, 'success');
    },
    [commitNow, notify, readOnly, sectionTitleOf],
  );

  const handleMoveSection = useCallback(
    (key: string, delta: -1 | 1) => {
      const current = draftRef.current;
      if (!current || readOnly) return;
      const sections = moveSection(current.sections, key, delta);
      // 已到两端时返回的是新的同序数组：按 key 序列比较后才决定写不写。
      if (!sectionOrderChanged(current.sections, sections)) return;
      const title = sectionTitleOf(key);
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
      notify(`已${delta < 0 ? '上移' : '下移'}「${title}」`, 'success');
    },
    [commitNow, notify, readOnly, sectionTitleOf],
  );

  const handleRemoveSection = useCallback(
    (key: string) => {
      const current = draftRef.current;
      if (!current || readOnly) return;
      const title = sectionTitleOf(key);
      const sections = removeSection(current.sections, key);
      // 模板节（删了会被重新补齐）与未知 key 都是同一引用的空操作：跳过写盘与提示。
      if (sections === current.sections) return;
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
      notify(`已删除「${title}」，可用 Ctrl/⌘+Z 撤销`, 'info');
    },
    [commitNow, notify, readOnly, sectionTitleOf],
  );

  /** AI 参考「采用本节」：参考区只回调到这里，写回正文的唯一入口。 */
  const handleAdoptSection = useCallback(
    (key: string, body: string) => {
      const current = draftRef.current;
      if (!current || readOnly) return;
      const updatedAt = nowIso();
      // 先按展示位置把目标节落成真实的一节：AI 面板列的是**展示列表**，里面的模板空节
      // 在存储里还没有位置。直接 merge 会把它追加到末尾（列表重排）；先落位后写入，
      // 「采用本节」对这类节也就从「静默无反应」变成真的可用。
      const ensured = ensureSection(current.sections, template, key, updatedAt);
      // 纵深防御：`mergeSectionBodies` 对未知 key 是「追加新节」，落位后仍不存在的 key
      // 说明它既不是模板节也不是已有节（模型可能编了个 key）——丢弃，并明确告诉用户，
      // 不再像以前那样静默返回（点了没反应最容易被当成按钮坏了）。
      if (!ensured.some((section) => section.key === key)) {
        notify('这一节已不在当前报告里，无法采用', 'error');
        return;
      }
      const sections = mergeSectionBodies(ensured, key, body, {
        origin: 'ai',
        updatedAt,
        title: templateTitle(key),
      });
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
      // 自建节的标题不在模板里，提示要用草稿标题（`sectionTitleOf`）而不是 key。
      notify(`已采用「${sectionTitleOf(key)}」的 AI 参考`, 'success');
    },
    [commitNow, notify, readOnly, sectionTitleOf, template, templateTitle],
  );

  /** 「全部采用」：一次写入所有节，一次历史快照（一条 Ctrl/⌘+Z 回退）。 */
  const handleAdoptAll = useCallback(
    (items: { key: string; body: string }[]) => {
      const current = draftRef.current;
      if (!current || readOnly) return;
      const updatedAt = nowIso();
      // 逐个「先落位、再写入」：和「采用本节」同一条路径，模板空节按展示位置插进存储，
      // 不会被追加到末尾；未知 key 落位后仍不存在，一律丢弃（不写盘，也不顺手造节）。
      let sections = current.sections;
      const accepted: { key: string; body: string }[] = [];
      for (const item of items) {
        const ensured = ensureSection(sections, template, item.key, updatedAt);
        if (!ensured.some((section) => section.key === item.key)) continue;
        sections = ensured;
        accepted.push(item);
      }
      if (accepted.length === 0) {
        notify('没有可采用的章节：模型返回的 key 都不在当前报告里', 'error');
        return;
      }
      for (const item of accepted) {
        sections = mergeSectionBodies(sections, item.key, item.body, {
          origin: 'ai',
          updatedAt,
          title: templateTitle(item.key),
        });
      }
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
      notify(`已采用 ${accepted.length} 节的 AI 参考`, 'success');
    },
    [commitNow, notify, readOnly, template, templateTitle],
  );

  const handleReopen = useCallback(() => {
    if (!selectedReport) return;
    reopenReport(selectedReport.id);
    notify('已取消定稿，可以继续编辑', 'info');
  }, [notify, reopenReport, selectedReport]);

  /* ---------------- 导出 ---------------- */

  /** 用当前缓冲拼 Markdown：刚敲的字不必等防抖落盘也能导出。 */
  const exportTarget = useCallback((): Report | null => {
    const current = draftRef.current;
    if (!selectedReport || !current) return null;
    return { ...selectedReport, title: current.title, author: current.author, sections: current.sections };
  }, [selectedReport]);

  const handleCopyMarkdown = useCallback(() => {
    const target = exportTarget();
    if (!target) return;
    void copyReportMarkdown(target, notify);
  }, [exportTarget, notify]);

  const handleDownloadMarkdown = useCallback(() => {
    const target = exportTarget();
    if (!target) return;
    downloadReportMarkdown(target, notify);
  }, [exportTarget, notify]);

  /* ---------------- 二次确认 ---------------- */

  const confirmSectionTitle =
    confirm?.type === 'rebuild' ? (templateTitle(confirm.key) ?? confirm.key) : '';

  const runConfirm = useCallback(() => {
    const action = confirm;
    setConfirm(null);
    if (!action) return;

    if (action.type === 'rebuild') {
      const current = draftRef.current;
      if (!current) return;
      let body: string | null;
      try {
        body = rebuildSection(workspace, kind, period, action.key);
      } catch (error) {
        notify(error instanceof Error ? error.message : String(error), 'error');
        return;
      }
      if (body === null) {
        notify(`未知章节：${action.key}`, 'error');
        return;
      }
      const updatedAt = nowIso();
      const sections = mergeSectionBodies(
        // 旧报告缺这一节时，重新汇总同样要先按展示位置落位，否则追加到末尾会重排列表。
        ensureSection(current.sections, template, action.key, updatedAt),
        action.key,
        body,
        { origin: 'auto', updatedAt },
      );
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
      notify('已按最新数据重算本节', 'success');
      return;
    }

    if (!selectedReport) return;

    if (action.type === 'finalize') {
      flush();
      finalizeReport(selectedReport.id);
      notify('已定稿，内容已冻结', 'success');
      return;
    }

    // 删除：缓冲内容随报告一起丢弃，不再 flush，避免留下一次无意义的历史。
    clearTimer();
    pendingRef.current = null;
    deleteReport(selectedReport.id);
    const fallback = shiftPeriod(kind, period, -1);
    if (fallback) {
      setPeriod(fallback);
      setSelectedId(findReport(reports, kind, fallback)?.id ?? null);
    } else {
      setSelectedId(null);
    }
    notify('已删除报告', 'info');
  }, [
    clearTimer,
    commitNow,
    confirm,
    deleteReport,
    finalizeReport,
    flush,
    kind,
    notify,
    period,
    reports,
    selectedReport,
    template,
    workspace,
  ]);

  /* ---------------- 渲染 ---------------- */

  const displayPeriod = label || period;

  const confirmTitle =
    confirm?.type === 'rebuild'
      ? '重新汇总本节'
      : confirm?.type === 'finalize'
        ? '定稿并冻结内容'
        : '删除这份报告';
  const confirmDescription =
    confirm?.type === 'rebuild'
      ? `将用当前工作区数据重写「${confirmSectionTitle}」，本节已手写的内容会被覆盖。`
      : confirm?.type === 'finalize'
        ? '定稿后正文只读：不能再汇总、插入或清空，需要改动得先「取消定稿」。'
        : `删除后「${displayPeriod}」的正文与导出内容一起消失，且只能靠撤销恢复。`;
  const confirmLabel =
    confirm?.type === 'rebuild' ? '覆盖并重新汇总' : confirm?.type === 'finalize' ? '定稿' : '删除';

  return (
    <div className="page reports-page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>周报</h1>
          <p>按周/月/季沉淀对外汇报</p>
        </div>
        <div className="page-actions reports-actions">
          <Segmented
            options={KIND_OPTIONS}
            value={kind}
            onChange={handleKindChange}
            size="sm"
            ariaLabel="报告粒度切换"
          />
          <div className="reports-period-nav" role="group" aria-label="期次切换">
            <IconButton
              label="上一期"
              size="sm"
              disabled={!previousPeriod}
              onClick={() => handleShift(-1)}
            >
              <Icon name="chevron-left" size={14} />
            </IconButton>
            <span className="reports-period-label">{displayPeriod}</span>
            <IconButton
              label="下一期"
              size="sm"
              disabled={!nextPeriod}
              onClick={() => handleShift(1)}
            >
              <Icon name="chevron-right" size={14} />
            </IconButton>
          </div>

          {selectedReport ? (
            <>
              <Badge tone={readOnly ? 'ok' : 'warn'} dot>
                {REPORT_STATUS_LABELS[selectedReport.status]}
              </Badge>
              {readOnly ? (
                <Button
                  variant="secondary"
                  iconLeft={<Icon name="edit" size={14} />}
                  onClick={handleReopen}
                >
                  取消定稿
                </Button>
              ) : (
                <Button
                  variant="primary"
                  iconLeft={<Icon name="check" size={14} />}
                  onClick={() => setConfirm({ type: 'finalize' })}
                >
                  定稿
                </Button>
              )}
              <Button
                variant="danger"
                iconLeft={<Icon name="trash" size={14} />}
                onClick={() => setConfirm({ type: 'delete' })}
              >
                删除
              </Button>
            </>
          ) : (
            <Button
              variant="primary"
              disabled={!range}
              iconLeft={<Icon name="plus" size={14} />}
              onClick={handleCreate}
            >
              生成本期草稿
            </Button>
          )}
        </div>
      </div>

      <div className="reports-layout">
        <ReportIndex
          reports={visibleReports}
          kind={kind}
          selectedId={selectedId}
          query={query}
          totalCount={kindReports.length}
          onQueryChange={setQuery}
          onSelect={handleSelect}
        />

        <div className="reports-main">
          {selectedReport && draft ? (
            <ReportEditor
              report={selectedReport}
              draft={draft}
              template={template}
              readOnly={readOnly}
              onTitleChange={handleTitleChange}
              onAuthorChange={handleAuthorChange}
              onSectionChange={handleSectionChange}
              onRebuildSection={(key) => setConfirm({ type: 'rebuild', key })}
              onClearSection={handleClearSection}
              onAiSection={handleAiSection}
              onMoveSection={handleMoveSection}
              onRenameSection={handleRenameSection}
              onRemoveSection={handleRemoveSection}
              onAddSection={handleAddSection}
              onCopyMarkdown={handleCopyMarkdown}
              onDownloadMarkdown={handleDownloadMarkdown}
            />
          ) : (
            <div className="reports-empty">
              <EmptyState
                icon={<Icon name="doc" size={22} />}
                title={`还没有 ${displayPeriod}报`}
                description="生成的草稿会按模板把本期的完成、风险、指标与计划汇总成可编辑的正文。"
                action={
                  <Button
                    variant="primary"
                    disabled={!range}
                    iconLeft={<Icon name="plus" size={14} />}
                    onClick={handleCreate}
                  >
                    生成本期草稿
                  </Button>
                }
              />
            </div>
          )}
        </div>

        {/* 右栏两个标签共用同一列：AI 面板用 CSS 隐藏而不卸载，切标签回来结果还在。 */}
        <div className="reports-side">
          <div className="reports-side-tabs">
            <Segmented
              options={SIDE_TABS}
              value={sideTab}
              onChange={setSideTab}
              size="sm"
              ariaLabel="右栏内容切换"
            />
          </div>
          <div className={clsx('reports-side-pane', sideTab !== 'source' && 'is-hidden')}>
            <ReportSourcePanel
              facts={facts}
              disabled={!draft || readOnly}
              onInsert={handleInsertFact}
            />
          </div>
          <div className={clsx('reports-side-pane', sideTab !== 'ai' && 'is-hidden')}>
            <ReportAiPanel
              active={sideTab === 'ai'}
              resetKey={`${selectedId ?? 'none'}:${kind}:${period}`}
              kind={kind}
              period={period}
              label={label}
              range={range}
              author={draft?.author ?? ''}
              sections={aiSections}
              template={template}
              facts={facts}
              readOnly={readOnly}
              hasDraft={Boolean(draft)}
              target={aiTarget}
              request={aiHandle}
              onAdoptSection={handleAdoptSection}
              onAdoptAll={handleAdoptAll}
              onOpenSettings={handleOpenSettings}
              notify={notify}
            />
          </div>
        </div>
      </div>

      <Modal
        open={confirm !== null}
        onClose={() => setConfirm(null)}
        title={confirmTitle}
        description={confirmDescription}
        footer={
          <>
            <Button variant="secondary" onClick={() => setConfirm(null)}>
              取消
            </Button>
            <Button
              variant={confirm?.type === 'delete' ? 'danger' : 'primary'}
              onClick={runConfirm}
            >
              {confirmLabel}
            </Button>
          </>
        }
      >
        <p className="reports-confirm-note">
          {confirm?.type === 'delete'
            ? '删除只影响本报告本身，工作区条目不受影响。'
            : '这一步可以用 Ctrl/⌘+Z 撤销。'}
        </p>
      </Modal>
    </div>
  );
}
