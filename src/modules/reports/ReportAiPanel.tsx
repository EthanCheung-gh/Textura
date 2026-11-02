/**
 * 右栏「AI 参考」标签的内容容器。
 *
 * 边界（重要，违反其中任何一条都算设计回退）：
 * - **不读也不写 store**：采用只回调 `onAdoptSection` / `onAdoptAll`，`mergeSectionBodies` + `commitNow`
 *   的写回全部由页面层完成（本文件不 import 任何 store API）；
 * - 结果只落在参考区，**绝不直接写正文**；采用后结果保留，方便再次采用或换节对比；
 * - 不缓存、不做自动重试：一次点击 = 一次请求，是否重试由用户点「重试」决定；
 * - 取消：每次请求都从页面层注入的句柄取新的 `AbortSignal`（`begin()` 会 abort 旧的），
 *   切标签 / 卸载 / 切报告（由页面层 `abort()`）都会落地；`kind === 'aborted'` 静默忽略；
 * - 不把 `apiKey` 写进 DOM 或日志：只展示 provider 文案与模型名。
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import clsx from 'clsx';
import type { ReportPeriodKind, ReportSection } from '../../core/model';
import { Button } from '../../ui/Button';
import { TextArea } from '../../ui/Field';
import { Modal } from '../../ui/Modal';
import { AiRequestError, assertAiReady, completeChat } from '../ai/client';
import type { AiMessage } from '../ai/client';
import { PROVIDER_PRESETS, loadAiConfig, validateAiConfig } from '../ai/config';
import type { AiConfig } from '../ai/config';
import {
  buildFactsDigest,
  parseReportSections,
  reportMessages,
  sectionMessages,
} from '../ai/prompts';
import { aiErrorText, buildAiContext, digestSizeText, filterSectionsByTemplate } from './aiView';
import type { AiErrorView } from './aiView';
import type { ReportNotifier } from './exportReport';
import type { ReportTemplate } from './draft';
import type { ReportFactsDetailed } from './facts';
import type { PeriodRange } from './period';

/** 当前 AI 目标：整份，或编辑器里点开的那一节（`requestId` 每次点击递增，用来区分「再点一次」）。 */
export type AiTarget =
  | { mode: 'report' }
  | { mode: 'section'; key: string; requestId: number };

/** 页面层持有的取消句柄：面板每次发请求前 `begin()`，页面在切报告 / 切周期时 `abort()`。 */
export interface AiAbortHandle {
  /** 取消当前请求（没有在途请求时忽略）。 */
  abort(): void;
  /** 取消旧请求并返回新请求的 signal。 */
  begin(): AbortSignal;
}

interface SectionBody {
  key: string;
  body: string;
}

interface LoadingState {
  mode: 'section' | 'report';
  /** 仅 `mode === 'section'` 有值。 */
  key: string | null;
}

/** 「重试」要重发的目标（不带 `requestId`：重试是用户显式动作，不需要防重）。 */
type LastRequest = { mode: 'report' } | { mode: 'section'; key: string };

export interface ReportAiPanelProps {
  /** 右栏是否停在「AI 参考」标签：切走时取消在途请求（已有结果保留）。 */
  active: boolean;
  /** 报告 / 期次标识：变化时清空参考结果（在途请求由句柄取消）。 */
  resetKey: string;
  kind: ReportPeriodKind;
  /** 期次键（如 `2026-W44`）。 */
  period: string;
  /** 期次中文标题。 */
  label: string;
  range: PeriodRange | null;
  author: string;
  /** 草稿正文（未落盘的编辑也在里面）。 */
  sections: ReportSection[];
  template: ReportTemplate;
  facts: ReportFactsDetailed | null;
  /** 已定稿：生成与采用全部禁用。 */
  readOnly: boolean;
  /** 没有草稿就没有写回目标。 */
  hasDraft: boolean;
  target: AiTarget;
  request: AiAbortHandle;
  onAdoptSection: (key: string, body: string) => void;
  onAdoptAll: (sections: SectionBody[]) => void;
  onOpenSettings: () => void;
  notify: ReportNotifier;
}

/** 一行正文的自适应行数：短结果不占半屏，长结果在 max-height 内滚动。 */
function resultRows(body: string): number {
  const lines = body ? body.split('\n').length : 1;
  return Math.min(14, Math.max(5, lines + 1));
}

/** 配置缺口清单：给「大模型未启用」引导卡用，直接说清还差什么。 */
function configIssues(config: AiConfig): string[] {
  const issues: string[] = [];
  const { errors } = validateAiConfig(config);
  if (!config.enabled) issues.push('大模型未启用（设置 → 大模型 → 启用）');
  if (!config.apiKey.trim()) issues.push('缺少 API Key');
  if (errors.baseUrl) issues.push(`Base URL 非法：${errors.baseUrl}`);
  if (errors.model) issues.push('缺少模型名称');
  if (errors.temperature) issues.push(`温度非法：${errors.temperature}`);
  if (errors.maxTokens) issues.push(`最大 token 非法：${errors.maxTokens}`);
  return issues;
}

/** 能否发起请求：与 `assertAiReady` 同一口径（启用 + 密钥 + 配置校验），不额外读 apiKey。 */
function canRun(config: AiConfig): boolean {
  try {
    assertAiReady(config);
    return true;
  } catch {
    return false;
  }
}

/** 系统提示词来自配置（提示词层不写人格设定），作为 messages 头注入。 */
function withSystem(config: AiConfig, messages: AiMessage[]): AiMessage[] {
  const system = config.systemPrompt.trim();
  return system ? [{ role: 'system', content: system }, ...messages] : messages;
}

function isAborted(error: unknown): boolean {
  if (error instanceof AiRequestError) return error.kind === 'aborted';
  const name = (error as { name?: unknown } | null)?.name;
  return name === 'AbortError';
}

export function ReportAiPanel({
  active,
  resetKey,
  kind,
  period,
  label,
  range,
  author,
  sections,
  template,
  facts,
  readOnly,
  hasDraft,
  target,
  request,
  onAdoptSection,
  onAdoptAll,
  onOpenSettings,
  notify,
}: ReportAiPanelProps) {
  // 「面板打开时 loadAiConfig()」：面板一次挂载只读一次，之后每次发起请求前再读一次，
  // 这样用户在设置页改完配置回来（页面会重新挂载）或中途改配置都不会用到旧值。
  const [config, setConfig] = useState<AiConfig>(() => loadAiConfig());
  const [loading, setLoading] = useState<LoadingState | null>(null);
  const [error, setError] = useState<AiErrorView | null>(null);
  const [sectionResult, setSectionResult] = useState<SectionBody | null>(null);
  const [reportResult, setReportResult] = useState<SectionBody[] | null>(null);
  const [confirmAll, setConfirmAll] = useState(false);

  /** 请求序号：只让「最新一次请求」写状态，旧请求的迟到结果 / finally 全部丢弃。 */
  const seqRef = useRef(0);
  /** 是否仍挂载：`seqRef` 只管「旧请求不覆盖新请求」，卸载后不再 setState 由它负责。 */
  const mountedRef = useRef(true);
  /** 最近一次实际发起的请求，供「重试」按钮复用（不做自动重试）。 */
  const lastRequestRef = useRef<LastRequest | null>(null);
  /** 自动发起单节生成的回调（每次渲染更新，避免 effect 依赖整个 runSection）。 */
  const autoRunRef = useRef<(key: string) => void>(() => {});
  /** 已经消费过的 `requestId`：同一次点击只发一次请求。 */
  const lastAutoRef = useRef<number | null>(null);

  // 卸载标记：await 之后一律先过它再 setState（在途请求卸载后仍会 settle）。
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  /** await 之后写状态的唯一守卫：既拦卸载，也拦被新请求取代的旧请求。 */
  const canWriteState = useCallback(
    (seq: number) => mountedRef.current && seqRef.current === seq,
    [],
  );

  const issues = useMemo(() => configIssues(config), [config]);
  const ready = issues.length === 0;
  const busy = loading !== null;
  const disabled = readOnly || !hasDraft;

  const digest = useMemo(() => {
    if (!facts) return '';
    // buildFactsDigest 只读 facts 与头部字段（周期 / 作者 / 范围），与 sections 无关：
    // 这里传空数组，避免每输入一个字都重算一遍摘要。
    return buildFactsDigest({ kind, periodLabel: label, range, author, facts, sections: [] });
  }, [author, facts, kind, label, range]);

  const sectionTitle = useCallback(
    (key: string) => template.sections.find((section) => section.key === key)?.title ?? key,
    [template],
  );

  const buildContext = useCallback(() => {
    if (!facts) return null;
    return buildAiContext({ kind, period, range, author, sections, facts, template });
  }, [author, facts, kind, period, range, sections, template]);

  /* ---------------- 生成 ---------------- */

  const runSection = useCallback(
    async (key: string) => {
      lastRequestRef.current = { mode: 'section', key };
      if (disabled) return;
      // 每次发起前重读配置：设置页改完（或 localStorage 被别处更新）不必等重挂载。
      const next = loadAiConfig();
      setConfig(next);
      // 配置不可用时不发请求，只靠引导卡提示（避免一次必然失败的往返）。
      if (!canRun(next)) return;
      const context = buildContext();
      if (!context) return;

      let messages: AiMessage[];
      try {
        messages = sectionMessages(context, key);
      } catch (requestError) {
        lastRequestRef.current = null;
        setError(aiErrorText(requestError));
        return;
      }

      const seq = seqRef.current + 1;
      seqRef.current = seq;
      setLoading({ mode: 'section', key });
      setError(null);
      // begin() 会 abort 上一次请求：同一时刻只允许一个在途请求。
      const signal = request.begin();
      try {
        const text = await completeChat(next, withSystem(next, messages), { signal });
        if (!canWriteState(seq)) return;
        setSectionResult({ key, body: text });
      } catch (requestError) {
        if (!canWriteState(seq)) return;
        if (isAborted(requestError)) return;
        setError(aiErrorText(requestError));
      } finally {
        if (canWriteState(seq)) setLoading(null);
      }
    },
    [buildContext, canWriteState, disabled, request],
  );

  const runReport = useCallback(async () => {
    lastRequestRef.current = { mode: 'report' };
    if (disabled) return;
    const next = loadAiConfig();
    setConfig(next);
    if (!canRun(next)) return;
    const context = buildContext();
    if (!context) return;

    let messages: AiMessage[];
    try {
      messages = reportMessages(context);
    } catch (requestError) {
      lastRequestRef.current = null;
      setError(aiErrorText(requestError));
      return;
    }

    const seq = seqRef.current + 1;
    seqRef.current = seq;
    setLoading({ mode: 'report', key: null });
    setError(null);
    const signal = request.begin();
    try {
      const text = await completeChat(next, withSystem(next, messages), { signal });
      if (!canWriteState(seq)) return;
      const filtered = filterSectionsByTemplate(parseReportSections(text), template);
      // parseReportSections 已过滤未知 key，这里再按当前模板筛一次：
      // 换过模板的报告只保留本节存在的章节，全被筛掉时明确报「格式异常」而不是给空列表。
      if (filtered.length === 0) {
        throw new AiRequestError('response', '模型返回的章节都不在当前模板内');
      }
      setReportResult(filtered);
    } catch (requestError) {
      if (!canWriteState(seq)) return;
      if (isAborted(requestError)) return;
      setError(aiErrorText(requestError));
    } finally {
      if (canWriteState(seq)) setLoading(null);
    }
  }, [buildContext, canWriteState, disabled, request, template]);

  const retry = useCallback(() => {
    const last = lastRequestRef.current;
    if (!last) return;
    if (last.mode === 'section') void runSection(last.key);
    else void runReport();
  }, [runReport, runSection]);

  /* ---------------- 自动发起 / 取消 ---------------- */

  // 回调用 ref 转一手：自动发起只应随「目标」变化，不该随函数身份变化重跑。
  useEffect(() => {
    autoRunRef.current = (key: string) => {
      void runSection(key);
    };
  }, [runSection]);

  useEffect(() => {
    if (target.mode !== 'section') {
      lastAutoRef.current = null;
      return;
    }
    // 面板不可见时先不消费这次请求，等切到 AI 标签再发一次。
    if (!active) return;
    if (lastAutoRef.current === target.requestId) return;
    lastAutoRef.current = target.requestId;
    autoRunRef.current(target.key);
  }, [active, target]);

  // 切标签：取消在途请求，但保留已有结果（切回来还能继续采用）。
  useEffect(() => {
    if (!active) request.abort();
  }, [active, request]);

  // 切报告 / 切期次：清空参考区（在途请求已由页面层 abort）。
  useEffect(() => {
    seqRef.current += 1;
    lastAutoRef.current = null;
    lastRequestRef.current = null;
    setLoading(null);
    setError(null);
    setSectionResult(null);
    setReportResult(null);
    setConfirmAll(false);
  }, [resetKey]);

  // 卸载（切路由 / 页面关闭）：取消在途请求。
  useEffect(() => () => request.abort(), [request]);

  /* ---------------- 复制 / 采用 ---------------- */

  const copyBody = useCallback(
    async (body: string) => {
      try {
        const clipboard = typeof navigator === 'undefined' ? undefined : navigator.clipboard;
        if (!clipboard || typeof clipboard.writeText !== 'function') {
          throw new Error('当前环境不支持剪贴板');
        }
        await clipboard.writeText(body);
        notify('已复制参考文本', 'success');
      } catch (copyError) {
        const reason = copyError instanceof Error ? copyError.message : String(copyError);
        notify(`复制失败：${reason}`, 'error');
      }
    },
    [notify],
  );

  const adoptAll = useCallback(() => {
    setConfirmAll(false);
    if (!reportResult || reportResult.length === 0) return;
    onAdoptAll(reportResult);
  }, [onAdoptAll, reportResult]);

  /* ---------------- 渲染 ---------------- */

  const providerLabel = PROVIDER_PRESETS[config.provider]?.label ?? config.provider;
  const targetKey = target.mode === 'section' ? target.key : null;

  return (
    <section className={clsx('reports-ai', !active && 'is-hidden')} aria-label="AI 参考">
      <div className="reports-ai-head">
        <h2 className="reports-ai-title">AI 参考</h2>
        <span className="reports-ai-digest">{digestSizeText(digest)}</span>
      </div>

      <p className="reports-ai-meta">
        <span>{config.enabled ? providerLabel : '未启用'}</span>
        <span className="reports-ai-model">{config.model.trim() || '未填写模型'}</span>
      </p>

      {readOnly ? (
        <p className="reports-ai-notice">已定稿，内容冻结，AI 参考不可用</p>
      ) : !hasDraft ? (
        <p className="reports-ai-notice">先生成本期草稿，AI 参考需要一份能写回的正文。</p>
      ) : !facts ? (
        <p className="reports-ai-notice">本期数据不可用，换一个合法期次再看。</p>
      ) : null}

      {ready ? null : (
        <div className="reports-ai-guide">
          <p className="reports-ai-guide-title">
            {config.enabled ? '大模型配置不完整' : '大模型未启用'}
          </p>
          <ul className="reports-ai-guide-list">
            {issues.map((issue) => (
              <li key={issue}>{issue}</li>
            ))}
          </ul>
          <Button variant="secondary" size="sm" onClick={onOpenSettings}>
            去设置
          </Button>
        </div>
      )}

      <div className="reports-ai-actions">
        <Button
          variant="primary"
          size="sm"
          disabled={disabled || !ready || busy}
          onClick={() => void runReport()}
          title="基于本期事实摘要生成整份参考稿（只进参考区，不写正文）"
        >
          {loading?.mode === 'report' ? '生成中…' : '整份生成参考'}
        </Button>
      </div>

      {targetKey ? (
        <div className="reports-ai-target">
          <span className="reports-ai-target-title">{sectionTitle(targetKey)}</span>
          <Button
            variant="secondary"
            size="sm"
            disabled={disabled || !ready || busy}
            onClick={() => void runSection(targetKey)}
            title="只生成这一节的参考稿"
          >
            {loading?.mode === 'section' && loading.key === targetKey ? '生成中…' : '重新生成本节'}
          </Button>
        </div>
      ) : null}

      {error ? (
        <div className="reports-ai-error" role="alert">
          <p className="reports-ai-error-title">{error.title}</p>
          {error.hint ? <p className="reports-ai-error-hint">{error.hint}</p> : null}
          <div className="reports-ai-error-actions">
            {error.needsSettings ? (
              <Button variant="secondary" size="sm" onClick={onOpenSettings}>
                去设置
              </Button>
            ) : null}
            {error.canRetry ? (
              <Button variant="ghost" size="sm" onClick={retry}>
                重试
              </Button>
            ) : null}
          </div>
        </div>
      ) : null}

      {sectionResult ? (
        <article className="reports-ai-result">
          <div className="reports-ai-result-head">
            <h3 className="reports-ai-result-title">{sectionTitle(sectionResult.key)}</h3>
            <div className="reports-ai-result-actions">
              <Button variant="ghost" size="sm" onClick={() => void copyBody(sectionResult.body)}>
                复制
              </Button>
              <Button
                variant="secondary"
                size="sm"
                disabled={disabled}
                onClick={() => onAdoptSection(sectionResult.key, sectionResult.body)}
                title="用这段参考替换该节正文（可用 Ctrl/⌘+Z 撤销）"
              >
                采用本节
              </Button>
            </div>
          </div>
          <TextArea
            className="reports-ai-result-body"
            aria-label={`${sectionTitle(sectionResult.key)} 的 AI 参考`}
            value={sectionResult.body}
            rows={resultRows(sectionResult.body)}
            readOnly
            spellCheck={false}
          />
        </article>
      ) : null}

      {reportResult ? (
        <div className="reports-ai-report">
          <div className="reports-ai-report-head">
            <span className="reports-ai-report-count">共 {reportResult.length} 节参考</span>
            <Button
              variant="secondary"
              size="sm"
              disabled={disabled}
              onClick={() => setConfirmAll(true)}
              title="把这些节的正文一次性替换为 AI 参考"
            >
              全部采用
            </Button>
          </div>
          {reportResult.map((item) => (
            <article className="reports-ai-card" key={item.key}>
              <div className="reports-ai-card-head">
                <h3 className="reports-ai-card-title">{sectionTitle(item.key)}</h3>
                <div className="reports-ai-card-actions">
                  <Button variant="ghost" size="sm" onClick={() => void copyBody(item.body)}>
                    复制
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    disabled={disabled}
                    onClick={() => onAdoptSection(item.key, item.body)}
                  >
                    采用本节
                  </Button>
                </div>
              </div>
              <div className="reports-ai-card-body">{item.body}</div>
            </article>
          ))}
        </div>
      ) : null}

      {!sectionResult && !reportResult && !error && ready ? (
        <p className="reports-ai-empty">
          还没有参考结果。整份生成，或用段落工具条上的「AI 参考」按节生成。
        </p>
      ) : null}

      <Modal
        open={confirmAll}
        onClose={() => setConfirmAll(false)}
        title="全部采用 AI 参考"
        description={
          reportResult
            ? `将覆盖这 ${reportResult.length} 节的现有正文，没有参考结果的节保持不变。`
            : ''
        }
        footer={
          <>
            <Button variant="secondary" onClick={() => setConfirmAll(false)}>
              取消
            </Button>
            <Button variant="primary" onClick={adoptAll}>
              覆盖并采用
            </Button>
          </>
        }
      >
        <p className="reports-confirm-note">采用后可以用 Ctrl/⌘+Z 撤销；参考结果会保留，方便再次采用。</p>
      </Modal>
    </section>
  );
}
