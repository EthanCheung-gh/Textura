export type AiProvider = 'openai' | 'anthropic' | 'custom';

export interface AiConfig {
  enabled: boolean;
  provider: AiProvider;
  baseUrl: string;
  apiKey: string;
  model: string;
  temperature: number;
  maxTokens: number;
  systemPrompt: string;
}

export type AiConfigErrors = Partial<Record<keyof AiConfig, string>>;

export interface AiConfigStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface ProviderPreset {
  label: string;
  baseUrl: string;
  model: string;
  hint: string;
}

export const AI_CONFIG_KEY = 'textura.ai.config.v1';

export const AI_PROVIDERS: AiProvider[] = ['openai', 'anthropic', 'custom'];

export const PROVIDER_PRESETS: Record<AiProvider, ProviderPreset> = {
  openai: {
    label: 'OpenAI 兼容',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    hint: '适用于 OpenAI 及兼容 /chat/completions 的网关。',
  },
  anthropic: {
    label: 'Anthropic',
    baseUrl: 'https://api.anthropic.com/v1',
    model: 'claude-3-5-sonnet-latest',
    hint: '使用 Anthropic Messages 协议的网关地址。',
  },
  custom: {
    label: '自定义网关',
    baseUrl: '',
    model: '',
    hint: '自行填写内网或第三方网关的地址与模型名。',
  },
};

export const DEFAULT_AI_CONFIG: AiConfig = {
  enabled: false,
  provider: 'openai',
  baseUrl: PROVIDER_PRESETS.openai.baseUrl,
  apiKey: '',
  model: PROVIDER_PRESETS.openai.model,
  temperature: 0.3,
  maxTokens: 2048,
  systemPrompt: '你是 Textura 的执行助理。用简洁的中文把用户意图整理成可执行事项。',
};

export const TEMPERATURE_OPTIONS = [0, 0.2, 0.3, 0.5, 0.7, 1] as const;

function resolveStorage(): AiConfigStorage | null {
  return typeof localStorage === 'undefined' ? null : localStorage;
}

function asString(value: unknown, fallback: string): string {
  return typeof value === 'string' ? value : fallback;
}

function asBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function asNumber(value: unknown, fallback: number, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return fallback;
  return Math.min(max, Math.max(min, value));
}

function isAiProvider(value: string): value is AiProvider {
  return (AI_PROVIDERS as readonly string[]).includes(value);
}

export function normalizeAiConfig(input: unknown): AiConfig {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    return { ...DEFAULT_AI_CONFIG };
  }
  const raw = input as Record<string, unknown>;
  const providerValue = asString(raw.provider, DEFAULT_AI_CONFIG.provider);
  const provider = isAiProvider(providerValue) ? providerValue : DEFAULT_AI_CONFIG.provider;
  return {
    enabled: asBoolean(raw.enabled, DEFAULT_AI_CONFIG.enabled),
    provider,
    baseUrl: asString(raw.baseUrl, PROVIDER_PRESETS[provider].baseUrl),
    apiKey: asString(raw.apiKey, ''),
    model: asString(raw.model, PROVIDER_PRESETS[provider].model),
    temperature: asNumber(raw.temperature, DEFAULT_AI_CONFIG.temperature, 0, 2),
    maxTokens: Math.round(asNumber(raw.maxTokens, DEFAULT_AI_CONFIG.maxTokens, 128, 8192)),
    systemPrompt: asString(raw.systemPrompt, DEFAULT_AI_CONFIG.systemPrompt),
  };
}

export function validateAiConfig(config: AiConfig): { ok: boolean; errors: AiConfigErrors } {
  const errors: AiConfigErrors = {};
  const baseUrl = config.baseUrl.trim();
  if (!baseUrl) {
    errors.baseUrl = '请填写 Base URL';
  } else if (!/^https?:\/\/\S+$/i.test(baseUrl)) {
    errors.baseUrl = 'Base URL 需以 http:// 或 https:// 开头';
  }
  if (!config.model.trim()) {
    errors.model = '请填写模型名称';
  }
  if (config.enabled && !config.apiKey.trim()) {
    errors.apiKey = '启用大模型时必须填写 API Key';
  }
  if (!Number.isFinite(config.temperature) || config.temperature < 0 || config.temperature > 2) {
    errors.temperature = '温度需在 0–2 之间';
  }
  if (
    !Number.isInteger(config.maxTokens) ||
    config.maxTokens < 128 ||
    config.maxTokens > 8192
  ) {
    errors.maxTokens = '最大 token 需为 128–8192 的整数';
  }
  return { ok: Object.keys(errors).length === 0, errors };
}

export function maskSecret(secret: string): string {
  const value = secret.trim();
  if (!value) return '未填写';
  if (value.length <= 8) return '••••••';
  return `${value.slice(0, 4)}••••${value.slice(-4)}`;
}

export function applyProviderPreset(config: AiConfig, provider: AiProvider): AiConfig {
  if (provider === 'custom') return { ...config, provider };
  const preset = PROVIDER_PRESETS[provider];
  return { ...config, provider, baseUrl: preset.baseUrl, model: preset.model };
}

export function loadAiConfig(storage: AiConfigStorage | null = resolveStorage()): AiConfig {
  if (!storage) return { ...DEFAULT_AI_CONFIG };
  try {
    const text = storage.getItem(AI_CONFIG_KEY);
    if (!text) return { ...DEFAULT_AI_CONFIG };
    return normalizeAiConfig(JSON.parse(text));
  } catch {
    return { ...DEFAULT_AI_CONFIG };
  }
}

export function saveAiConfig(
  config: AiConfig,
  storage: AiConfigStorage | null = resolveStorage(),
): boolean {
  if (!storage) return false;
  try {
    storage.setItem(AI_CONFIG_KEY, JSON.stringify(config));
    return true;
  } catch {
    return false;
  }
}

export function clearAiConfig(storage: AiConfigStorage | null = resolveStorage()): boolean {
  if (!storage) return false;
  try {
    storage.removeItem(AI_CONFIG_KEY);
    return true;
  } catch {
    return false;
  }
}