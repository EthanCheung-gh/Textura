/**
 * 大模型调用层：只做「发请求 + 解析响应」，不含 UI、store、报告模型逻辑。
 *
 * 协议：
 * - `openai` / `custom` → OpenAI 兼容 `POST {baseUrl}/chat/completions`，
 *   读 `choices[0].message.content`；
 * - `anthropic` → Messages 协议 `POST {baseUrl}/messages`，把 system 消息抽到顶层
 *   `system` 字段，读 `content[]` 里 `type === 'text'` 的片段并拼接。
 *
 * 契约：
 * - 不缓存、不重试、非流式；是否重试由 UI 决定；
 * - 所有失败都收敛成 `AiRequestError`，`kind` 供 UI 分流提示文案；
 * - **任何 message / detail 都不包含 apiKey**：响应体回显密钥时先按 `maskSecret` 脱敏；
 * - 超时（内部定时器）与外部取消（用户 `AbortSignal`）共用同一个 controller，
 *   但用 `abortReason` 区分，分别映射成 `timeout` / `aborted`；
 * - **取消 / 超时的判定优先于其它一切失败**：即使已经拿到响应头、正在读 body，
 *   底层只抛出 `AbortError` / `TypeError: terminated` / 空 body，也一律报
 *   `aborted` / `timeout`（`mapFailure` 是唯一判定点，不做异常消息匹配）；
 * - `fetch` 从调用方注入（测试）或 `globalThis.fetch` 取，不引入任何 HTTP 依赖。
 */
import { maskSecret, validateAiConfig } from './config';
import type { AiConfig, AiProvider } from './config';

export type AiErrorKind =
  | 'config'
  | 'auth'
  | 'rate-limit'
  | 'timeout'
  | 'aborted'
  | 'network'
  | 'server'
  | 'response'
  | 'unknown';

export interface AiRequestErrorInit {
  /** HTTP 状态码（仅响应类错误有）。 */
  status?: number;
  /** 供 toast 展示的补充说明，绝不含 apiKey。 */
  detail?: string;
  cause?: unknown;
}

/** 调用层唯一对外错误类型；`kind` 是 UI 分流文案的依据。 */
export class AiRequestError extends Error {
  readonly kind: AiErrorKind;
  readonly status?: number;
  readonly detail?: string;

  constructor(kind: AiErrorKind, message: string, init: AiRequestErrorInit = {}) {
    super(message, init.cause === undefined ? undefined : { cause: init.cause });
    this.name = 'AiRequestError';
    this.kind = kind;
    if (init.status !== undefined) this.status = init.status;
    if (init.detail !== undefined) this.detail = init.detail;
  }
}

export interface AiMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface AiCallOptions {
  /** 用户取消（关闭弹窗、切换报告等）。 */
  signal?: AbortSignal;
  /** 默认 60_000；非有限值或 <= 0 时回退默认值。 */
  timeoutMs?: number;
  /** 测试注入，生产环境走 globalThis.fetch。 */
  fetchImpl?: typeof fetch;
}

/** 默认超时（毫秒）。 */
export const DEFAULT_TIMEOUT_MS = 60_000;

const OPENAI_PATH = 'chat/completions';
const ANTHROPIC_PATH = 'messages';
const ANTHROPIC_VERSION = '2023-06-01';
/** 各协议自己的完整端点形态（不重复拼路径；不跨协议复用）。 */
const OPENAI_ENDPOINT_PATTERN = /\/chat\/completions$/i;
const ANTHROPIC_ENDPOINT_PATTERN = /\/messages$/i;
const MAX_DETAIL_CHARS = 300;

/* ------------------------------------------------------------------ */
/* 就绪校验                                                            */
/* ------------------------------------------------------------------ */

function isSupportedProvider(value: string): value is AiProvider {
  return value === 'openai' || value === 'anthropic' || value === 'custom';
}

/**
 * 便于 UI 判断是否可用：`enabled` + 配置校验通过。
 * 不满足时抛 `AiRequestError('config')`（message 与 detail 均不含密钥）。
 */
export function assertAiReady(config: AiConfig): void {
  if (!config.enabled) {
    throw new AiRequestError('config', '大模型未启用，请先在设置中开启');
  }
  if (!isSupportedProvider(config.provider)) {
    throw new AiRequestError('config', `未知的服务商：${String(config.provider)}`);
  }
  if (!config.apiKey.trim()) {
    throw new AiRequestError('config', '请先填写大模型 API Key');
  }
  const { ok, errors } = validateAiConfig(config);
  if (!ok) {
    const detail = Object.entries(errors)
      .map(([field, message]) => `${field}：${message}`)
      .join('；');
    throw new AiRequestError('config', '大模型配置未通过校验', { detail });
  }
}

/* ------------------------------------------------------------------ */
/* 请求构造                                                            */
/* ------------------------------------------------------------------ */

/**
 * URL 归一：
 * - 末尾有 / 先去掉，再拼一次路径，避免 `//chat/completions`；
 * - 用户已经把端点填全时原样使用，不重复拼接；
 * - 端点判定**按协议各认一份**：openai/custom 只认 `/chat/completions`，
 *   anthropic 只认 `/messages`。否则 `provider='openai'` + 以 `/messages` 结尾的
 *   baseUrl 会被误判成「已填全」，直接打到错端点。
 */
function endpointFor(baseUrl: string, provider: 'openai' | 'anthropic'): string {
  const base = baseUrl.trim().replace(/\/+$/, '');
  const pattern = provider === 'anthropic' ? ANTHROPIC_ENDPOINT_PATTERN : OPENAI_ENDPOINT_PATTERN;
  if (pattern.test(base)) return base;
  return `${base}/${provider === 'anthropic' ? ANTHROPIC_PATH : OPENAI_PATH}`;
}

function splitSystem(messages: AiMessage[]): { system: string; rest: AiMessage[] } {
  const systemParts: string[] = [];
  const rest: AiMessage[] = [];
  for (const message of messages) {
    if (message.role === 'system') systemParts.push(message.content);
    else rest.push(message);
  }
  return { system: systemParts.join('\n\n').trim(), rest };
}

interface PreparedRequest {
  url: string;
  init: RequestInit;
}

function preparedRequest(config: AiConfig, messages: AiMessage[]): PreparedRequest {
  if (config.provider === 'anthropic') {
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'x-api-key': config.apiKey,
      'anthropic-version': ANTHROPIC_VERSION,
      // 浏览器 / Tauri webview 直连时 Anthropic 要求显式声明该头。
      'anthropic-dangerous-direct-browser-access': 'true',
    };
    const { system, rest } = splitSystem(messages);
    const body: Record<string, unknown> = {
      model: config.model,
      max_tokens: config.maxTokens,
      temperature: config.temperature,
      messages: rest.map((message) => ({ role: message.role, content: message.content })),
    };
    if (system) body.system = system;
    return {
      url: endpointFor(config.baseUrl, 'anthropic'),
      init: { method: 'POST', headers, body: JSON.stringify(body) },
    };
  }

  const headers: Record<string, string> = {
    'content-type': 'application/json',
    authorization: `Bearer ${config.apiKey}`,
  };
  const body = {
    model: config.model,
    messages: messages.map((message) => ({ role: message.role, content: message.content })),
    temperature: config.temperature,
    max_tokens: config.maxTokens,
    stream: false,
  };
  return {
    url: endpointFor(config.baseUrl, 'openai'),
    init: { method: 'POST', headers, body: JSON.stringify(body) },
  };
}

/* ------------------------------------------------------------------ */
/* 错误映射                                                            */
/* ------------------------------------------------------------------ */

function clipDetail(text: string, secret: string): string | undefined {
  const cleaned = redact(text, secret).replace(/\s+/g, ' ').trim();
  if (!cleaned) return undefined;
  return cleaned.length > MAX_DETAIL_CHARS ? `${cleaned.slice(0, MAX_DETAIL_CHARS)}…` : cleaned;
}

/** 把任何形式的密钥回显替换成 `maskSecret` 片段（分割拼接，避开正则元字符）。 */
function redact(text: string, secret: string): string {
  const key = secret.trim();
  if (!key || !text.includes(key)) return text;
  return text.split(key).join(maskSecret(key));
}

function describeError(error: unknown): string {
  if (error instanceof Error) return `${error.name}: ${error.message}`;
  if (typeof error === 'string') return error;
  return String(error);
}

/** 状态码 → (kind, message)。见文件头错误映射契约。 */
function statusError(status: number): { kind: AiErrorKind; message: string } {
  if (status === 401 || status === 403) {
    return { kind: 'auth', message: `鉴权失败（HTTP ${status}），请检查 API Key 与网关权限` };
  }
  if (status === 429) {
    return { kind: 'rate-limit', message: '请求被限流（HTTP 429），请稍后重试' };
  }
  if (status >= 500) {
    return { kind: 'server', message: `模型服务异常（HTTP ${status}），请稍后重试` };
  }
  if (status >= 400) {
    return {
      kind: 'response',
      message: `请求被拒绝（HTTP ${status}），请检查 Base URL、模型名与参数`,
    };
  }
  if (status >= 300) {
    return { kind: 'network', message: `网关返回异常状态（HTTP ${status}），请检查 Base URL` };
  }
  return { kind: 'unknown', message: `请求失败（HTTP ${status}）` };
}

function timeoutLabel(timeoutMs: number): string {
  return timeoutMs >= 1000 ? `${Math.round(timeoutMs / 1000)} 秒` : `${timeoutMs} 毫秒`;
}

function abortError(reason: 'timeout' | 'external', timeoutMs: number): AiRequestError {
  if (reason === 'timeout') {
    return new AiRequestError(
      'timeout',
      `请求超时（${timeoutLabel(timeoutMs)}），请检查网络或稍后重试`,
    );
  }
  return new AiRequestError('aborted', '请求已取消');
}

function isAbortError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const name = (error as { name?: unknown }).name;
  return name === 'AbortError' || name === 'TimeoutError';
}

/**
 * 失败映射上下文：**取消 / 超时的唯一真源**。
 * `abortReason` 非 null 即代表已 abort（监听器先写 reason 再 `controller.abort()`），
 * fetch 阶段与 body 读取阶段都读同一个对象，不存在第二套判定。
 */
interface FailureContext {
  abortReason: 'timeout' | 'external' | null;
  timeoutMs: number;
  secret: string;
}

/** 失败发生的位置：只影响「无法归类时」的兜底 kind，不影响取消/超时判定。 */
type FailureStage = 'request' | 'body';

function networkError(error: unknown, secret: string): AiRequestError {
  // 浏览器里 fetch / body 读取抛 TypeError 基本都是 CORS 拒绝、传输中断或网关不可达。
  return new AiRequestError('network', '网络请求失败，无法连接模型网关', {
    detail: clipDetail(
      `可能是跨域限制（CORS）或网关不可达；原始错误：${describeError(error)}`,
      secret,
    ),
    cause: error,
  });
}

/**
 * 统一的失败映射（唯一判定点）。
 *
 * 顺序至关重要：
 * 1. **先看 `abortReason`**：取消 / 超时可能发生在「已拿到响应头、正在读 body」之间，
 *    此时底层异常形态很不可靠（`AbortError`、`TypeError: terminated`，甚至
 *    `response.text()` 直接 resolve 出空串），一律按 abortReason 报 `aborted` / `timeout`，
 *    绝不退化成 `response` / `network`，也不做异常消息的字符串匹配；
 * 2. 已成型为 `AiRequestError` 的结构性错误（`response`）直通；
 * 3. 未带 reason 的 `AbortError` 归 `aborted`；
 * 4. `TypeError` → `network`；
 * 5. 其余按阶段兜底：body 读取 → `response`，请求阶段 → `unknown`。
 */
function mapFailure(error: unknown, ctx: FailureContext, stage: FailureStage): AiRequestError {
  if (ctx.abortReason) return abortError(ctx.abortReason, ctx.timeoutMs);
  if (error instanceof AiRequestError) return error;
  if (isAbortError(error)) return new AiRequestError('aborted', '请求已取消');
  if (error instanceof TypeError) return networkError(error, ctx.secret);
  if (stage === 'body') {
    return new AiRequestError('response', '读取模型响应体失败', {
      detail: clipDetail(describeError(error), ctx.secret),
      cause: error,
    });
  }
  return new AiRequestError('unknown', '大模型请求失败', {
    detail: clipDetail(describeError(error), ctx.secret),
    cause: error,
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function safeStringify(value: unknown): string {
  try {
    return JSON.stringify(value) ?? '';
  } catch {
    return '';
  }
}

/**
 * 读取响应体文本（成功路径与非 2xx 都要用）。
 *
 * 不吞异常：读取中被打断时交给 `mapFailure(..., 'body')`，
 * 「已 abort」优先判成 `aborted` / `timeout`，其次 `TypeError` → `network`，其余 → `response`。
 */
async function readBodyText(response: Response, failure: FailureContext): Promise<string> {
  try {
    return await response.text();
  } catch (error) {
    throw mapFailure(error, failure, 'body');
  }
}

async function readJsonBody(response: Response, failure: FailureContext): Promise<unknown> {
  const text = await readBodyText(response, failure);
  if (!text.trim()) throw new AiRequestError('response', '模型返回了空响应体');
  try {
    return JSON.parse(text) as unknown;
  } catch (error) {
    throw new AiRequestError('response', '模型返回内容不是合法 JSON', {
      detail: clipDetail(text, failure.secret),
      cause: error,
    });
  }
}

async function httpError(response: Response, failure: FailureContext): Promise<AiRequestError> {
  const body = await readBodyText(response, failure);
  const mapped = statusError(response.status);
  return new AiRequestError(mapped.kind, mapped.message, {
    status: response.status,
    detail: clipDetail(body, failure.secret),
  });
}

/* ------------------------------------------------------------------ */
/* 响应解析                                                            */
/* ------------------------------------------------------------------ */

function normalizeContent(content: unknown): string {
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    const parts: string[] = [];
    for (const part of content) {
      if (typeof part === 'string') parts.push(part);
      else if (isRecord(part) && typeof part.text === 'string') parts.push(part.text);
    }
    return parts.join('').trim();
  }
  return '';
}

function openAiText(payload: unknown, secret: string): string {
  const choices = isRecord(payload) ? payload.choices : undefined;
  if (!Array.isArray(choices) || choices.length === 0) {
    throw new AiRequestError('response', '响应结构不符：缺少 choices', {
      detail: clipDetail(safeStringify(payload), secret),
    });
  }
  const first = choices[0];
  const message = isRecord(first) ? first.message : undefined;
  const text = normalizeContent(isRecord(message) ? message.content : undefined);
  if (!text) {
    throw new AiRequestError('response', '模型返回内容为空', {
      detail: clipDetail(safeStringify(first), secret),
    });
  }
  return text;
}

function anthropicText(payload: unknown, secret: string): string {
  const content = isRecord(payload) ? payload.content : undefined;
  if (!Array.isArray(content)) {
    throw new AiRequestError('response', '响应结构不符：缺少 content 数组', {
      detail: clipDetail(safeStringify(payload), secret),
    });
  }
  const parts: string[] = [];
  for (const block of content) {
    if (isRecord(block) && block.type === 'text' && typeof block.text === 'string') {
      parts.push(block.text);
    }
  }
  const text = parts.join('').trim();
  if (!text) {
    throw new AiRequestError('response', '模型返回内容为空', {
      detail: clipDetail(safeStringify(payload), secret),
    });
  }
  return text;
}

/* ------------------------------------------------------------------ */
/* 入口                                                                */
/* ------------------------------------------------------------------ */

function normalizeTimeout(timeoutMs: number | undefined): number {
  if (typeof timeoutMs !== 'number' || !Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    return DEFAULT_TIMEOUT_MS;
  }
  return Math.round(timeoutMs);
}

/**
 * 包一层而不是直接取 `globalThis.fetch` 的引用：
 * 浏览器 / Tauri webview 的 fetch 需要 window 作为 receiver，裸引用会 Illegal invocation。
 */
function resolveFetch(impl: typeof fetch | undefined): typeof fetch {
  if (impl) return impl;
  return (input, init) => globalThis.fetch(input, init);
}

/**
 * 单轮非流式补全：成功返回模型文本（已 trim），失败抛 `AiRequestError`。
 * 无缓存、无重试、无副作用。
 */
export async function completeChat(
  config: AiConfig,
  messages: AiMessage[],
  options: AiCallOptions = {},
): Promise<string> {
  assertAiReady(config);
  if (messages.length === 0) throw new AiRequestError('config', '没有可发送的消息');

  const timeoutMs = normalizeTimeout(options.timeoutMs);
  if (options.signal?.aborted) throw abortError('external', timeoutMs);

  /**
   * 取消 / 超时的单一真源：fetch 阶段与 body 读取阶段都读它。
   * `secret` 只用于脱敏（把响应体里回显的密钥替换成 maskSecret 片段），绝不写进 message / detail。
   */
  const failure: FailureContext = {
    abortReason: null,
    timeoutMs,
    secret: config.apiKey.trim(),
  };
  const fetchImpl = resolveFetch(options.fetchImpl);
  const request = preparedRequest(config, messages);
  const externalSignal = options.signal;

  const controller = new AbortController();

  const aborted = new Promise<never>((_resolve, reject) => {
    controller.signal.addEventListener(
      'abort',
      () => reject(abortError(failure.abortReason ?? 'external', failure.timeoutMs)),
      { once: true },
    );
  });

  const onExternalAbort = () => {
    if (failure.abortReason === null) failure.abortReason = 'external';
    controller.abort();
  };
  externalSignal?.addEventListener('abort', onExternalAbort, { once: true });

  const timer = setTimeout(() => {
    if (failure.abortReason === null) failure.abortReason = 'timeout';
    controller.abort();
  }, timeoutMs);

  try {
    // 用 race 兜住「fetch 实现不响应 signal」的情况（部分网关 / 注入的桩），
    // 保证超时一定能落地。
    const response = await Promise.race([
      fetchImpl(request.url, { ...request.init, signal: controller.signal }),
      aborted,
    ]);
    if (!response.ok) throw await httpError(response, failure);
    const payload = await readJsonBody(response, failure);
    return config.provider === 'anthropic'
      ? anthropicText(payload, failure.secret)
      : openAiText(payload, failure.secret);
  } catch (error) {
    // 唯一判定点：fetch 阶段与 body 读取阶段的失败都走 mapFailure，
    // 已 abort 时（即使底层只报出空 body / TypeError）一律收敛成 aborted / timeout。
    throw mapFailure(error, failure, 'request');
  } finally {
    clearTimeout(timer);
    externalSignal?.removeEventListener('abort', onExternalAbort);
  }
}
