import { describe, expect, it } from 'vitest';
import {
  AI_CONFIG_KEY,
  DEFAULT_AI_CONFIG,
  PROVIDER_PRESETS,
  applyProviderPreset,
  clearAiConfig,
  loadAiConfig,
  maskSecret,
  normalizeAiConfig,
  saveAiConfig,
  validateAiConfig,
} from './config';
import type { AiConfigStorage } from './config';

function createMemoryStorage(): AiConfigStorage & { values: Map<string, string> } {
  const values = new Map<string, string>();
  return {
    values,
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => {
      values.set(key, value);
    },
    removeItem: (key) => {
      values.delete(key);
    },
  };
}

describe('normalizeAiConfig', () => {
  it('非法输入回退默认配置', () => {
    expect(normalizeAiConfig(null)).toEqual(DEFAULT_AI_CONFIG);
    expect(normalizeAiConfig('nope')).toEqual(DEFAULT_AI_CONFIG);
  });

  it('修复非法服务商并保留合法字段', () => {
    const config = normalizeAiConfig({
      provider: 'unknown',
      apiKey: 'sk-1234567890',
      model: 'my-model',
    });
    expect(config.provider).toBe('openai');
    expect(config.baseUrl).toBe(PROVIDER_PRESETS.openai.baseUrl);
    expect(config.apiKey).toBe('sk-1234567890');
    expect(config.model).toBe('my-model');
  });

  it('温度与 token 超出范围时收敛到边界', () => {
    expect(normalizeAiConfig({ temperature: 9 }).temperature).toBe(2);
    expect(normalizeAiConfig({ temperature: -3 }).temperature).toBe(0);
    expect(normalizeAiConfig({ maxTokens: 999999 }).maxTokens).toBe(8192);
    expect(normalizeAiConfig({ maxTokens: 10 }).maxTokens).toBe(128);
    expect(normalizeAiConfig({ maxTokens: 512.6 }).maxTokens).toBe(513);
  });

  it('非布尔 enabled 回退默认值', () => {
    expect(normalizeAiConfig({ enabled: 'yes' }).enabled).toBe(false);
  });
});

describe('validateAiConfig', () => {
  it('默认配置通过校验', () => {
    expect(validateAiConfig(DEFAULT_AI_CONFIG).ok).toBe(true);
  });

  it('缺少 Base URL 与非法地址都会报错', () => {
    expect(validateAiConfig({ ...DEFAULT_AI_CONFIG, baseUrl: '' }).errors.baseUrl).toBeTruthy();
    expect(
      validateAiConfig({ ...DEFAULT_AI_CONFIG, baseUrl: 'api.example.com' }).errors.baseUrl,
    ).toBeTruthy();
  });

  it('启用时必须填写 API Key', () => {
    const result = validateAiConfig({ ...DEFAULT_AI_CONFIG, enabled: true, apiKey: '' });
    expect(result.ok).toBe(false);
    expect(result.errors.apiKey).toBeTruthy();
  });

  it('模型与 token 上限参与校验', () => {
    const result = validateAiConfig({
      ...DEFAULT_AI_CONFIG,
      model: '  ',
      maxTokens: 100,
    });
    expect(result.errors.model).toBeTruthy();
    expect(result.errors.maxTokens).toBeTruthy();
  });
});

describe('maskSecret', () => {
  it('空值与短密钥不泄露内容', () => {
    expect(maskSecret('')).toBe('未填写');
    expect(maskSecret('short')).toBe('••••••');
  });

  it('长密钥只保留首尾四位', () => {
    expect(maskSecret('sk-1234567890abcdef')).toBe('sk-1••••cdef');
    expect(maskSecret('  sk-1234567890abcdef  ')).toBe('sk-1••••cdef');
  });
});

describe('配置持久化', () => {
  it('保存、读取与清除使用独立存储键', () => {
    const storage = createMemoryStorage();
    expect(loadAiConfig(storage)).toEqual(DEFAULT_AI_CONFIG);

    const config = { ...DEFAULT_AI_CONFIG, apiKey: 'sk-test-123456', model: 'gpt-test' };
    expect(saveAiConfig(config, storage)).toBe(true);
    expect(storage.values.has(AI_CONFIG_KEY)).toBe(true);
    expect(loadAiConfig(storage)).toEqual(config);

    expect(clearAiConfig(storage)).toBe(true);
    expect(storage.values.has(AI_CONFIG_KEY)).toBe(false);
    expect(loadAiConfig(storage)).toEqual(DEFAULT_AI_CONFIG);
  });

  it('存储内容损坏时回退默认配置', () => {
    const storage = createMemoryStorage();
    storage.setItem(AI_CONFIG_KEY, '{not json');
    expect(loadAiConfig(storage)).toEqual(DEFAULT_AI_CONFIG);
  });

  it('没有 storage 时安全降级', () => {
    expect(loadAiConfig(null)).toEqual(DEFAULT_AI_CONFIG);
    expect(saveAiConfig(DEFAULT_AI_CONFIG, null)).toBe(false);
    expect(clearAiConfig(null)).toBe(false);
  });
});

describe('applyProviderPreset', () => {
  it('切换预设服务商填充 Base URL 与模型，保留密钥', () => {
    const config = { ...DEFAULT_AI_CONFIG, apiKey: 'sk-keep' };
    const next = applyProviderPreset(config, 'anthropic');
    expect(next.provider).toBe('anthropic');
    expect(next.baseUrl).toBe(PROVIDER_PRESETS.anthropic.baseUrl);
    expect(next.model).toBe(PROVIDER_PRESETS.anthropic.model);
    expect(next.apiKey).toBe('sk-keep');
  });

  it('自定义网关只切换类型，不清空已填内容', () => {
    const next = applyProviderPreset(DEFAULT_AI_CONFIG, 'custom');
    expect(next.provider).toBe('custom');
    expect(next.baseUrl).toBe(DEFAULT_AI_CONFIG.baseUrl);
    expect(next.model).toBe(DEFAULT_AI_CONFIG.model);
  });
});