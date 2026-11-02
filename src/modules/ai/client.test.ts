import { afterEach, describe, expect, it, vi } from 'vitest';
import { AiRequestError, DEFAULT_TIMEOUT_MS, assertAiReady, completeChat } from './client';
import type { AiCallOptions, AiMessage } from './client';
import type { AiConfig } from './config';

/**
 * Tauri IPC 桩：`client.ts` 用 **动态** `import('@tauri-apps/api/core')` 取 `invoke`，
 * 这里用 `vi.mock` 拦截同一个模块，绝不需要真实 Tauri 运行时或网络。
 */
const { invokeMock } = vi.hoisted(() => ({ invokeMock: vi.fn() }));

vi.mock('@tauri-apps/api/core', () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

const API_KEY = 'sk-test-1234567890';

/**
 * 最小化的 `process` 声明：本仓未装 `@types/node`（tsconfig 的 `types` 只有
 * `vite/client`），这里只需要 unhandledRejection 的监听与卸载。
 */
declare const process: {
  on(event: 'unhandledRejection', listener: (reason: unknown) => void): void;
  off(event: 'unhandledRejection', listener: (reason: unknown) => void): void;
};

/** 把当前进程伪装成 Tauri（或还原成浏览器），驱动 `isTauri()` 的分支。 */
function setTauriMode(enabled: boolean): void {
  const scope = globalThis as unknown as { window?: Record<string, unknown> };
  if (enabled) scope.window = { __TAURI_INTERNALS__: {} };
  else delete scope.window;
}

afterEach(() => {
  setTauriMode(false);
  invokeMock.mockReset();
});

function baseConfig(overrides: Partial<AiConfig> = {}): AiConfig {
  return {
    enabled: true,
    provider: 'openai',
    baseUrl: 'https://api.example.com/v1',
    apiKey: API_KEY,
    model: 'gpt-test',
    temperature: 0.2,
    maxTokens: 512,
    systemPrompt: '你是测试助理',
    ...overrides,
  };
}

interface RecordedCall {
  url: string;
  init: RequestInit;
}

function urlOf(input: RequestInfo | URL): string {
  if (typeof input === 'string') return input;
  if (input instanceof URL) return input.toString();
  return input.url;
}

/** mock fetch：只记录请求，绝不发真实网络请求。 */
function mockFetch(handler: (url: string, init: RequestInit) => Response | Promise<Response>) {
  const calls: RecordedCall[] = [];
  const impl = (async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const resolved = init ?? {};
    const url = urlOf(input);
    calls.push({ url, init: resolved });
    return handler(url, resolved);
  }) as typeof fetch;
  return { impl, calls };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

interface StalledBody {
  response: Response;
  /** 在 body 读取过程中让流失败（模拟取消 / 传输中断）。 */
  fail: (error: unknown) => void;
  /** 让流正常结束（读到空 body），模拟「中断只体现在空内容上」。 */
  close: () => void;
}

/**
 * 只返回响应头、body 永远读不完的响应：
 * 用于把失败精确落在「已拿到响应头、正在读 body」这段窗口里，
 * 不依赖真实网络，也不依赖 fetch 是否响应 signal。
 */
function stalledBodyResponse(status = 200): StalledBody {
  let streamController: ReadableStreamDefaultController<Uint8Array> | null = null;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      streamController = controller;
    },
  });
  return {
    response: new Response(stream, { status, headers: { 'content-type': 'application/json' } }),
    fail: (error) => streamController?.error(error),
    close: () => streamController?.close(),
  };
}

function headerOf(init: RequestInit, name: string): string | null {
  return new Headers(init.headers).get(name);
}

function bodyOf(init: RequestInit): Record<string, unknown> {
  return JSON.parse(String(init.body)) as Record<string, unknown>;
}

async function captureError(run: () => Promise<unknown>): Promise<AiRequestError> {
  try {
    await run();
  } catch (error) {
    expect(error).toBeInstanceOf(AiRequestError);
    return error as AiRequestError;
  }
  throw new Error('期望抛出 AiRequestError，但调用成功返回');
}

describe('completeChat · OpenAI 兼容协议', () => {
  it('请求 /chat/completions，带 Bearer 与完整 body，并解析 choices[0].message.content', async () => {
    const messages: AiMessage[] = [
      { role: 'system', content: '你是测试助理' },
      { role: 'user', content: '总结本周' },
    ];
    const { impl, calls } = mockFetch(() =>
      jsonResponse({ choices: [{ message: { role: 'assistant', content: ' 本周完成 3 项 ' } }] }),
    );

    const text = await completeChat(baseConfig(), messages, { fetchImpl: impl });

    expect(text).toBe('本周完成 3 项');
    expect(calls).toHaveLength(1);
    const call = calls[0] as RecordedCall;
    expect(call.url).toBe('https://api.example.com/v1/chat/completions');
    expect(call.init.method).toBe('POST');
    expect(headerOf(call.init, 'authorization')).toBe(`Bearer ${API_KEY}`);
    expect(headerOf(call.init, 'content-type')).toContain('application/json');
    expect(bodyOf(call.init)).toEqual({
      model: 'gpt-test',
      messages,
      temperature: 0.2,
      max_tokens: 512,
      stream: false,
    });
    // 成功路径不留下被 abort 的 signal（定时器已清理）。
    expect(call.init.signal?.aborted).toBe(false);
  });

  it('custom 服务商走同一套 OpenAI 兼容路径', async () => {
    const { impl, calls } = mockFetch(() =>
      jsonResponse({ choices: [{ message: { content: '网关返回' } }] }),
    );

    const text = await completeChat(
      baseConfig({ provider: 'custom', baseUrl: 'https://gw.internal/openai/v1' }),
      [{ role: 'user', content: '你好' }],
      { fetchImpl: impl },
    );

    expect(text).toBe('网关返回');
    expect((calls[0] as RecordedCall).url).toBe(
      'https://gw.internal/openai/v1/chat/completions',
    );
    expect(headerOf((calls[0] as RecordedCall).init, 'authorization')).toBe(`Bearer ${API_KEY}`);
  });
});

describe('completeChat · Anthropic Messages 协议', () => {
  const messages: AiMessage[] = [
    { role: 'system', content: '系统提示 A' },
    { role: 'user', content: '写周报' },
    { role: 'assistant', content: '好的' },
    { role: 'system', content: '系统提示 B' },
    { role: 'user', content: '继续' },
  ];

  it('请求 /messages，带三个 Anthropic header，system 抽到顶层，content[] 多段拼接', async () => {
    const { impl, calls } = mockFetch(() =>
      jsonResponse({
        content: [
          { type: 'text', text: '第一段' },
          { type: 'tool_use', id: 'tool-1', name: 'x', input: {} },
          { type: 'text', text: '第二段' },
        ],
      }),
    );

    const text = await completeChat(baseConfig({ provider: 'anthropic', baseUrl: 'https://api.anthropic.com/v1' }), messages, {
      fetchImpl: impl,
    });

    expect(text).toBe('第一段第二段');
    const call = calls[0] as RecordedCall;
    expect(call.url).toBe('https://api.anthropic.com/v1/messages');
    expect(headerOf(call.init, 'x-api-key')).toBe(API_KEY);
    expect(headerOf(call.init, 'anthropic-version')).toBe('2023-06-01');
    expect(headerOf(call.init, 'anthropic-dangerous-direct-browser-access')).toBe('true');
    expect(headerOf(call.init, 'content-type')).toBe('application/json');
    expect(headerOf(call.init, 'authorization')).toBeNull();

    const body = bodyOf(call.init);
    expect(body.model).toBe('gpt-test');
    expect(body.max_tokens).toBe(512);
    expect(body.temperature).toBe(0.2);
    expect(body.system).toBe('系统提示 A\n\n系统提示 B');
    expect(body.messages).toEqual([
      { role: 'user', content: '写周报' },
      { role: 'assistant', content: '好的' },
      { role: 'user', content: '继续' },
    ]);
    expect(body.stream).toBeUndefined();
  });

  it('没有 system 消息时不发送空的 system 字段', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ content: [{ type: 'text', text: 'ok' }] }));
    await completeChat(baseConfig({ provider: 'anthropic' }), [{ role: 'user', content: 'hi' }], {
      fetchImpl: impl,
    });
    expect(bodyOf((calls[0] as RecordedCall).init)).not.toHaveProperty('system');
  });
});

describe('completeChat · baseUrl 归一', () => {
  it('末尾带斜杠不多拼斜杠', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ choices: [{ message: { content: 'ok' } }] }));
    await completeChat(baseConfig({ baseUrl: 'https://api.example.com/v1/' }), [
      { role: 'user', content: 'hi' },
    ], { fetchImpl: impl });
    expect((calls[0] as RecordedCall).url).toBe('https://api.example.com/v1/chat/completions');
  });

  it('已填到 /chat/completions 时不重复拼接', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ choices: [{ message: { content: 'ok' } }] }));
    await completeChat(baseConfig({ baseUrl: 'https://api.example.com/v1/chat/completions' }), [
      { role: 'user', content: 'hi' },
    ], { fetchImpl: impl });
    expect((calls[0] as RecordedCall).url).toBe('https://api.example.com/v1/chat/completions');
  });

  it('Anthropic 已填到 /messages 时不重复拼接', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ content: [{ type: 'text', text: 'ok' }] }));
    await completeChat(
      baseConfig({ provider: 'anthropic', baseUrl: 'https://proxy.example.com/anthropic/messages/' }),
      [{ role: 'user', content: 'hi' }],
      { fetchImpl: impl },
    );
    expect((calls[0] as RecordedCall).url).toBe('https://proxy.example.com/anthropic/messages');
  });

  it('跨协议混填不复用端点：openai + 以 /messages 结尾仍补 /chat/completions', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ choices: [{ message: { content: 'ok' } }] }));
    await completeChat(baseConfig({ baseUrl: 'https://gw.example.com/v1/messages' }), [
      { role: 'user', content: 'hi' },
    ], { fetchImpl: impl });
    expect((calls[0] as RecordedCall).url).toBe(
      'https://gw.example.com/v1/messages/chat/completions',
    );
  });

  it('跨协议混填不复用端点：anthropic + 以 /chat/completions 结尾仍补 /messages', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ content: [{ type: 'text', text: 'ok' }] }));
    await completeChat(
      baseConfig({ provider: 'anthropic', baseUrl: 'https://gw.example.com/v1/chat/completions' }),
      [{ role: 'user', content: 'hi' }],
      { fetchImpl: impl },
    );
    expect((calls[0] as RecordedCall).url).toBe(
      'https://gw.example.com/v1/chat/completions/messages',
    );
  });
});

describe('completeChat · 错误映射', () => {
  it('401 → auth', async () => {
    const { impl } = mockFetch(() => jsonResponse({ error: 'invalid key' }, 401));
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], { fetchImpl: impl }),
    );
    expect(error.kind).toBe('auth');
    expect(error.status).toBe(401);
  });

  it('429 → rate-limit', async () => {
    const { impl } = mockFetch(() => jsonResponse({ error: 'slow down' }, 429));
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], { fetchImpl: impl }),
    );
    expect(error.kind).toBe('rate-limit');
    expect(error.status).toBe(429);
  });

  it('500 → server', async () => {
    const { impl } = mockFetch(() => jsonResponse({ error: 'boom' }, 500));
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], { fetchImpl: impl }),
    );
    expect(error.kind).toBe('server');
    expect(error.status).toBe(500);
  });

  it('fetch 抛 TypeError → network，detail 提示 CORS / 网关不可达', async () => {
    const impl = (async () => {
      throw new TypeError('Failed to fetch');
    }) as typeof fetch;
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], { fetchImpl: impl }),
    );
    expect(error.kind).toBe('network');
    expect(error.detail).toContain('CORS');
    expect(error.detail).toContain('网关不可达');
  });

  it('200 但 choices 为空 → response', async () => {
    const { impl } = mockFetch(() => jsonResponse({ choices: [] }));
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], { fetchImpl: impl }),
    );
    expect(error.kind).toBe('response');
    expect(error.detail).toContain('choices');
  });

  it('200 但 Anthropic content 没有 text 片段 → response', async () => {
    const { impl } = mockFetch(() => jsonResponse({ content: [{ type: 'tool_use' }] }));
    const error = await captureError(() =>
      completeChat(baseConfig({ provider: 'anthropic' }), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
      }),
    );
    expect(error.kind).toBe('response');
  });

  it('200 但不是合法 JSON → response', async () => {
    const impl = (async () =>
      new Response('<html>gateway</html>', { status: 200 })) as typeof fetch;
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], { fetchImpl: impl }),
    );
    expect(error.kind).toBe('response');
  });

  it('错误信息与 detail 都不含完整 apiKey（响应体回显密钥时脱敏）', async () => {
    const { impl } = mockFetch(() =>
      jsonResponse({ error: 'bad key', received: API_KEY, echo: `Bearer ${API_KEY}` }, 401),
    );
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], { fetchImpl: impl }),
    );
    expect(error.kind).toBe('auth');
    expect(error.message).not.toContain(API_KEY);
    expect(error.detail ?? '').not.toContain(API_KEY);
    // 脱敏后仍保留可辨识片段，便于用户定位是哪把密钥。
    expect(error.detail).toContain('sk-t');
  });
});

describe('completeChat · 超时与取消', () => {
  it('内部超时抛 timeout（fetch 永不 resolve 也能落地）', async () => {
    const impl = (() => new Promise<Response>(() => {})) as unknown as typeof fetch;
    const startedAt = Date.now();
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
        timeoutMs: 20,
      }),
    );
    expect(error.kind).toBe('timeout');
    expect(Date.now() - startedAt).toBeLessThan(2000);
  });

  it('外部 AbortSignal 取消抛 aborted（与 timeout 区分）', async () => {
    const impl = (() => new Promise<Response>(() => {})) as unknown as typeof fetch;
    const controller = new AbortController();
    setTimeout(() => controller.abort(), 10);
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
        timeoutMs: 5000,
        signal: controller.signal,
      }),
    );
    expect(error.kind).toBe('aborted');
    expect(error.message).toContain('取消');
  });

  it('传入已取消的 signal 时直接抛 aborted，不发起请求', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ choices: [{ message: { content: 'x' } }] }));
    const controller = new AbortController();
    controller.abort();
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
        signal: controller.signal,
      }),
    );
    expect(error.kind).toBe('aborted');
    expect(calls).toHaveLength(0);
  });

  it('默认超时是 60 秒', () => {
    expect(DEFAULT_TIMEOUT_MS).toBe(60_000);
  });
});

describe('completeChat · 响应体读取阶段的取消 / 超时', () => {
  it('body 读取中被外部取消 → aborted（不退化成 response / 空响应体）', async () => {
    const { response, fail } = stalledBodyResponse();
    const impl = (async () => response) as typeof fetch;
    const controller = new AbortController();
    setTimeout(() => {
      controller.abort();
      fail(new DOMException('aborted', 'AbortError'));
    }, 10);

    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
        timeoutMs: 5000,
        signal: controller.signal,
      }),
    );

    expect(error.kind).toBe('aborted');
    expect(error.message).toBe('请求已取消');
    expect(error.message).not.toContain('空响应体');
  });

  it('body 读取中触发内部超时 → timeout', async () => {
    const { response, fail } = stalledBodyResponse();
    const impl = (async () => response) as typeof fetch;
    // 超时（20ms）先到，body 随后才报错：中止事实不能被 body 异常覆盖。
    setTimeout(() => fail(new DOMException('aborted', 'AbortError')), 60);

    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
        timeoutMs: 20,
      }),
    );

    expect(error.kind).toBe('timeout');
    expect(error.message).toContain('超时');
  });

  it('body 读取中抛 TypeError → network（传输中断）', async () => {
    const { response, fail } = stalledBodyResponse();
    const impl = (async () => response) as typeof fetch;
    setTimeout(() => fail(new TypeError('network error')), 10);

    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
        timeoutMs: 5000,
      }),
    );

    expect(error.kind).toBe('network');
    expect(error.detail).toContain('CORS');
  });

  it('错误响应（401）的 body 读取被取消时仍是 aborted，不误报 auth', async () => {
    const { response, fail } = stalledBodyResponse(401);
    const impl = (async () => response) as typeof fetch;
    const controller = new AbortController();
    setTimeout(() => {
      controller.abort();
      fail(new DOMException('aborted', 'AbortError'));
    }, 10);

    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
        timeoutMs: 5000,
        signal: controller.signal,
      }),
    );

    expect(error.kind).toBe('aborted');
  });

  it('body 为空且未取消时仍报 response（不吞掉空响应体）', async () => {
    const impl = (async () => new Response('', { status: 200 })) as typeof fetch;
    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], { fetchImpl: impl }),
    );
    expect(error.kind).toBe('response');
    expect(error.message).toContain('空响应体');
  });

  it('取消后 body 才读完（读到空体）仍报 aborted，不被「空响应体」覆盖', async () => {
    const { response, close } = stalledBodyResponse();
    const impl = (async () => response) as typeof fetch;
    const controller = new AbortController();
    setTimeout(() => {
      controller.abort();
      close();
    }, 10);

    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
        timeoutMs: 5000,
        signal: controller.signal,
      }),
    );

    expect(error.kind).toBe('aborted');
    expect(error.message).not.toContain('空响应体');
  });

  it('超时后 body 才读完（读到空体）仍报 timeout', async () => {
    const { response, close } = stalledBodyResponse();
    const impl = (async () => response) as typeof fetch;
    setTimeout(() => close(), 60);

    const error = await captureError(() =>
      completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
        timeoutMs: 20,
      }),
    );

    expect(error.kind).toBe('timeout');
  });
});

describe('assertAiReady', () => {
  it('配置就绪时不抛错', () => {
    expect(() => assertAiReady(baseConfig())).not.toThrow();
  });

  it('enabled 为 false → config', () => {
    let error: AiRequestError | null = null;
    try {
      assertAiReady(baseConfig({ enabled: false }));
    } catch (caught) {
      error = caught as AiRequestError;
    }
    expect(error).toBeInstanceOf(AiRequestError);
    expect(error?.kind).toBe('config');
  });

  it('apiKey 为空 → config，且 detail 不含密钥', () => {
    let error: AiRequestError | null = null;
    try {
      assertAiReady(baseConfig({ apiKey: '   ' }));
    } catch (caught) {
      error = caught as AiRequestError;
    }
    expect(error?.kind).toBe('config');
    expect(error?.message).not.toContain(API_KEY);
    expect(error?.detail ?? '').not.toContain(API_KEY);
  });

  it('非法 baseUrl → config', () => {
    let error: AiRequestError | null = null;
    try {
      assertAiReady(baseConfig({ baseUrl: 'api.example.com' }));
    } catch (caught) {
      error = caught as AiRequestError;
    }
    expect(error?.kind).toBe('config');
    expect(error?.detail).toContain('baseUrl');
  });

  it('completeChat 先做就绪校验：未启用时不发请求', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ choices: [{ message: { content: 'x' } }] }));
    const error = await captureError(() =>
      completeChat(baseConfig({ enabled: false }), [{ role: 'user', content: 'hi' }], {
        fetchImpl: impl,
      }),
    );
    expect(error.kind).toBe('config');
    expect(calls).toHaveLength(0);
  });
});

describe('completeChat · 调用选项', () => {
  it('timeoutMs 非法时回退默认值（不抛错、不中断请求）', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ choices: [{ message: { content: 'ok' } }] }));
    const text = await completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
      fetchImpl: impl,
      timeoutMs: Number.NaN,
    });
    expect(text).toBe('ok');
    expect(calls).toHaveLength(1);
  });

  it('空 messages 直接报 config，不发请求', async () => {
    const { impl, calls } = mockFetch(() => jsonResponse({ choices: [{ message: { content: 'x' } }] }));
    const options: AiCallOptions = { fetchImpl: impl };
    const error = await captureError(() => completeChat(baseConfig(), [], options));
    expect(error.kind).toBe('config');
    expect(calls).toHaveLength(0);
  });
});

/* ------------------------------------------------------------------ */
/* 桌面端 IPC 通道（Rust 命令 ai_proxy，绕开 CSP / CORS）              */
/* ------------------------------------------------------------------ */

interface RecordedProxyRequest {
  url: string;
  headers: Record<string, string>;
  body: string;
  timeoutMs: number;
}

const IPC_MESSAGES: AiMessage[] = [
  { role: 'system', content: '你是测试助理' },
  { role: 'user', content: '总结本周' },
];

/** 取出唯一一次 `invoke('ai_proxy', { request })` 的入参。 */
function onlyProxyCall(): { command: string; request: RecordedProxyRequest } {
  expect(invokeMock).toHaveBeenCalledTimes(1);
  const call = invokeMock.mock.calls[0] as [string, { request: RecordedProxyRequest }];
  return { command: call[0], request: call[1].request };
}

/** 手动控制的 `invoke` 返回，用来模拟「迟到响应」。 */
function deferredInvoke(): { resolve: (value: unknown) => void; reject: (reason: unknown) => void } {
  let resolve!: (value: unknown) => void;
  let reject!: (reason: unknown) => void;
  invokeMock.mockImplementation(
    () =>
      new Promise((res, rej) => {
        resolve = res;
        reject = rej;
      }),
  );
  return {
    resolve: (value) => resolve(value),
    reject: (reason) => reject(reason),
  };
}

describe('completeChat · Tauri IPC 通道', () => {
  it('Tauri 环境选中 IPC 通道：调用 ai_proxy，密钥只在 headers 里', async () => {
    setTauriMode(true);
    invokeMock.mockResolvedValue({
      status: 200,
      body: JSON.stringify({ choices: [{ message: { content: ' 来自 IPC 的总结 ' } }] }),
    });

    const text = await completeChat(baseConfig(), IPC_MESSAGES);

    expect(text).toBe('来自 IPC 的总结');
    const { command, request } = onlyProxyCall();
    expect(command).toBe('ai_proxy');
    expect(request.url).toBe('https://api.example.com/v1/chat/completions');
    expect(request.timeoutMs).toBe(DEFAULT_TIMEOUT_MS);
    expect(request.headers.authorization).toBe(`Bearer ${API_KEY}`);
    expect(request.headers['content-type']).toContain('application/json');
    expect(request.headers['x-api-key']).toBeUndefined();
    expect(JSON.parse(request.body)).toEqual({
      model: 'gpt-test',
      messages: IPC_MESSAGES,
      temperature: 0.2,
      max_tokens: 512,
      stream: false,
    });
    // 请求体里不出现密钥（只允许出现在 headers）。
    expect(request.body).not.toContain(API_KEY);
  });

  it('IPC 返回 401 → auth（与 fetch 通道共用同一套状态码映射）', async () => {
    setTauriMode(true);
    invokeMock.mockResolvedValue({
      status: 401,
      body: JSON.stringify({ error: 'invalid key' }),
    });

    const error = await captureError(() => completeChat(baseConfig(), IPC_MESSAGES));

    expect(error.kind).toBe('auth');
    expect(error.status).toBe(401);
    expect(error.message).toContain('HTTP 401');
  });

  it('IPC 返回 500 → server', async () => {
    setTauriMode(true);
    invokeMock.mockResolvedValue({ status: 500, body: '{"error":"boom"}' });

    const error = await captureError(() => completeChat(baseConfig(), IPC_MESSAGES));

    expect(error.kind).toBe('server');
    expect(error.status).toBe(500);
  });

  it('IPC 返回 200 但 body 为空 → response（证明解析仍走同一套逻辑）', async () => {
    setTauriMode(true);
    invokeMock.mockResolvedValue({ status: 200, body: '' });

    const error = await captureError(() => completeChat(baseConfig(), IPC_MESSAGES));

    expect(error.kind).toBe('response');
    expect(error.message).toContain('空响应体');
  });

  it('IPC 通道下外部取消立即返回 aborted，迟到响应被丢弃、不产生第二次状态', async () => {
    setTauriMode(true);
    const deferred = deferredInvoke();
    const controller = new AbortController();
    const settled: string[] = [];

    const run = completeChat(baseConfig(), IPC_MESSAGES, {
      signal: controller.signal,
      timeoutMs: 5000,
    })
      .then(() => {
        settled.push('resolved');
      })
      .catch((error: AiRequestError) => {
        settled.push(error.kind);
      });

    setTimeout(() => controller.abort(), 10);
    await run;

    // 取消先落地：IPC 那侧从未返回过。
    expect(settled).toEqual(['aborted']);

    // 迟到的成功响应必须被丢弃：既不能再结算一次，也不能变成未处理拒绝。
    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown) => unhandled.push(reason);
    process.on('unhandledRejection', onUnhandled);
    try {
      deferred.resolve({
        status: 200,
        body: JSON.stringify({ choices: [{ message: { content: '迟到的成功' } }] }),
      });
      await new Promise((resolve) => setTimeout(resolve, 30));
    } finally {
      process.off('unhandledRejection', onUnhandled);
    }

    expect(unhandled).toEqual([]);
    expect(settled).toEqual(['aborted']);
  });

  it('IPC 通道内部超时 → timeout（invoke 永不返回也能落地，且把 timeoutMs 下传）', async () => {
    setTauriMode(true);
    deferredInvoke();

    const startedAt = Date.now();
    const error = await captureError(() =>
      completeChat(baseConfig(), IPC_MESSAGES, { timeoutMs: 20 }),
    );

    expect(error.kind).toBe('timeout');
    expect(error.message).toContain('超时');
    expect(Date.now() - startedAt).toBeLessThan(2000);
    // Rust 侧也拿到同一个超时，避免取消后连接一直挂着。
    expect(onlyProxyCall().request.timeoutMs).toBe(20);
  });

  it('IPC 通道自身失败（Rust Err）→ network，且错误串不含 apiKey', async () => {
    setTauriMode(true);
    invokeMock.mockRejectedValue('无法连接模型网关（DNS 解析、TLS 握手失败或网络不可达）');

    const error = await captureError(() => completeChat(baseConfig(), IPC_MESSAGES));

    expect(error.kind).toBe('network');
    expect(error.detail).toContain('无法连接模型网关');
    expect(error.message).not.toContain(API_KEY);
    expect(error.detail ?? '').not.toContain(API_KEY);
  });

  it('IPC 返回结构异常（缺 status / body）→ response，不误当成功', async () => {
    setTauriMode(true);
    invokeMock.mockResolvedValue({ status: '200' });

    const error = await captureError(() => completeChat(baseConfig(), IPC_MESSAGES));

    expect(error.kind).toBe('response');
  });
});

describe('completeChat · IPC 结构化错误分类（{ kind, message }）', () => {
  it('{ kind: timeout } → timeout（不是 network，文案沿用超时口径）', async () => {
    setTauriMode(true);
    invokeMock.mockRejectedValue({
      kind: 'timeout',
      message: '请求超时（60000 毫秒），请检查网络或稍后重试',
    });

    const error = await captureError(() =>
      completeChat(baseConfig(), IPC_MESSAGES, { timeoutMs: 60_000 }),
    );

    expect(error.kind).toBe('timeout');
    expect(error.message).toContain('超时');
    // 与浏览器通道共用同一句超时文案（abortError 单点产出）。
    expect(error.message).not.toContain('无法连接模型网关');
  });

  it('{ kind: url } → config（地址/配置问题，引导去设置而不是重试）', async () => {
    setTauriMode(true);
    invokeMock.mockRejectedValue({
      kind: 'url',
      message: '请求地址指向链路本地 / 云元数据地址，AI 代理已拒绝',
    });

    const error = await captureError(() => completeChat(baseConfig(), IPC_MESSAGES));

    expect(error.kind).toBe('config');
    expect(error.message).toContain('设置');
    // Rust 的具体原因留在 detail，便于用户定位。
    expect(error.detail).toContain('链路本地');
    expect(error.detail ?? '').not.toContain(API_KEY);
  });

  it('{ kind: network } → network（保留 Rust 的具体原因）', async () => {
    setTauriMode(true);
    invokeMock.mockRejectedValue({
      kind: 'network',
      message: '响应体过大（>20 MiB），已中止读取',
    });

    const error = await captureError(() => completeChat(baseConfig(), IPC_MESSAGES));

    expect(error.kind).toBe('network');
    expect(error.detail).toContain('响应体过大');
  });

  it('旧版后端只回纯字符串错误 → 兜底为 network（向后兼容）', async () => {
    setTauriMode(true);
    invokeMock.mockRejectedValue('无法连接模型网关（DNS 解析、TLS 握手失败或网络不可达）');

    const error = await captureError(() => completeChat(baseConfig(), IPC_MESSAGES));

    expect(error.kind).toBe('network');
    expect(error.detail).toContain('无法连接模型网关');
  });

  it('结构化错误不会覆盖取消优先级：已取消时仍报 aborted', async () => {
    setTauriMode(true);
    let reject!: (reason: unknown) => void;
    invokeMock.mockImplementation(
      () =>
        new Promise((_resolve, rejectInvoke) => {
          reject = rejectInvoke;
        }),
    );
    const controller = new AbortController();
    const run = captureError(() =>
      completeChat(baseConfig(), IPC_MESSAGES, { signal: controller.signal, timeoutMs: 5000 }),
    );

    setTimeout(() => controller.abort(), 10);
    const error = await run;
    // 迟到的结构化超时错误不能改写已取消的事实。
    reject({ kind: 'timeout', message: '请求超时（5000 毫秒）' });
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(error.kind).toBe('aborted');
    expect(error.message).toBe('请求已取消');
  });
});

describe('completeChat · 通道选择优先级', () => {
  it('注入 fetchImpl 优先于 IPC 通道（单测可锁定浏览器通道）', async () => {
    setTauriMode(true);
    const { impl, calls } = mockFetch(() =>
      jsonResponse({ choices: [{ message: { content: '走 fetch' } }] }),
    );

    const text = await completeChat(baseConfig(), [{ role: 'user', content: 'hi' }], {
      fetchImpl: impl,
    });

    expect(text).toBe('走 fetch');
    expect(calls).toHaveLength(1);
    expect(invokeMock).not.toHaveBeenCalled();
  });

  it('浏览器模式走 globalThis.fetch，完全不触发 ai_proxy', async () => {
    setTauriMode(false);
    const original = globalThis.fetch;
    const { impl, calls } = mockFetch(() =>
      jsonResponse({ choices: [{ message: { content: '浏览器通道' } }] }),
    );
    globalThis.fetch = impl;
    try {
      const text = await completeChat(baseConfig(), [{ role: 'user', content: 'hi' }]);
      expect(text).toBe('浏览器通道');
      expect(calls).toHaveLength(1);
      expect(calls[0]?.init.method).toBe('POST');
      expect(invokeMock).not.toHaveBeenCalled();
    } finally {
      globalThis.fetch = original;
    }
  });
});
