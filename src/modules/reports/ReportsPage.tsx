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
 */
import clsx from 'clsx';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Report, ReportPatch, ReportPeriodKind } from '../../core/model';
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
  reportsOfKind,
  sortReportsDesc,
} from './reportView';
import type { ReportDraft } from './reportView';
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
      const next = patchDraft((current) => ({ ...current, title: value }));
      if (next) scheduleSave(next.id, { title: value });
    },
    [patchDraft, scheduleSave],
  );

  const handleAuthorChange = useCallback(
    (value: string) => {
      const next = patchDraft((current) => ({ ...current, author: value }));
      if (next) scheduleSave(next.id, { author: value });
    },
    [patchDraft, scheduleSave],
  );

  const handleSectionChange = useCallback(
    (key: string, body: string) => {
      const next = patchDraft((current) => ({
        ...current,
        sections: mergeSectionBodies(current.sections, key, body, {
          origin: 'manual',
          updatedAt: nowIso(),
          title: templateTitle(key),
        }),
      }));
      if (next) scheduleSave(next.id, { sections: next.sections });
    },
    [patchDraft, scheduleSave, templateTitle],
  );

  const handleInsertFact = useCallback(
    (fact: ReportFact) => {
      const current = draftRef.current;
      if (!current) return;
      const sectionKey = FACT_SECTION_KEY[fact.kind];
      const existing = current.sections.find((section) => section.key === sectionKey);
      const sections = mergeSectionBodies(
        current.sections,
        sectionKey,
        appendLine(existing?.body ?? '', fact.line),
        { origin: 'manual', updatedAt: nowIso(), title: templateTitle(sectionKey) },
      );
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
      notify(`已插入到「${templateTitle(sectionKey) ?? sectionKey}」`, 'success');
    },
    [commitNow, notify, templateTitle],
  );

  const handleClearSection = useCallback(
    (key: string) => {
      const current = draftRef.current;
      if (!current) return;
      const sections = mergeSectionBodies(current.sections, key, '', {
        origin: 'manual',
        updatedAt: nowIso(),
        title: templateTitle(key),
      });
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
    },
    [commitNow, templateTitle],
  );

  /** AI 参考「采用本节」：参考区只回调到这里，写回正文的唯一入口。 */
  const handleAdoptSection = useCallback(
    (key: string, body: string) => {
      const current = draftRef.current;
      if (!current || readOnly) return;
      // 纵深防御：`mergeSectionBodies` 对未知 key 是「追加新节」，
      // 所以只放行当前模板里的节（面板已按模板过滤，这里再兜一层）。
      if (!template.sections.some((section) => section.key === key)) return;
      const sections = mergeSectionBodies(current.sections, key, body, {
        origin: 'ai',
        updatedAt: nowIso(),
        title: templateTitle(key),
      });
      draftRef.current = { ...current, sections };
      setDraft(draftRef.current);
      commitNow({ sections });
      notify(`已采用「${templateTitle(key) ?? key}」的 AI 参考`, 'success');
    },
    [commitNow, notify, readOnly, template, templateTitle],
  );

  /** 「全部采用」：一次写入所有节，一次历史快照（一条 Ctrl/⌘+Z 回退）。 */
  const handleAdoptAll = useCallback(
    (items: { key: string; body: string }[]) => {
      const current = draftRef.current;
      if (!current || readOnly) return;
      // 同上：未知 key 一律丢弃，不写盘也不「顺手」新建节。
      const known = new Set(template.sections.map((section) => section.key));
      const accepted = items.filter((item) => known.has(item.key));
      if (accepted.length === 0) {
        notify('没有可采用的章节：模型返回的 key 都不在当前模板里', 'error');
        return;
      }
      const updatedAt = nowIso();
      let sections = current.sections;
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
      const sections = mergeSectionBodies(current.sections, action.key, body, {
        origin: 'auto',
        updatedAt: nowIso(),
      });
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
              sections={draft?.sections ?? []}
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
