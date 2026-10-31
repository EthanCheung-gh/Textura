import { useState } from 'react';
import { TOOL_DEFINITIONS } from '@textura/mcp';
import { useWorkspace } from '../../core/store';
import { formatDateTime } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { Field, Select, TextArea, TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { Segmented } from '../../ui/Segmented';
import {
  AI_PROVIDERS,
  DEFAULT_AI_CONFIG,
  PROVIDER_PRESETS,
  TEMPERATURE_OPTIONS,
  applyProviderPreset,
  clearAiConfig,
  loadAiConfig,
  maskSecret,
  saveAiConfig,
  validateAiConfig,
} from './config';
import type { AiConfig, AiConfigErrors, AiProvider } from './config';
import './ai.css';

export function AiSettingsCard() {
  const notify = useWorkspace((state) => state.notify);
  const [config, setConfig] = useState<AiConfig>(() => loadAiConfig());
  const [errors, setErrors] = useState<AiConfigErrors>({});
  const [showKey, setShowKey] = useState(false);
  const [savedAt, setSavedAt] = useState<string | null>(null);

  function patchField<K extends keyof AiConfig>(key: K, value: AiConfig[K]) {
    setConfig((prev) => ({ ...prev, [key]: value }));
    setErrors((prev) => {
      if (!prev[key]) return prev;
      const next = { ...prev };
      delete next[key];
      return next;
    });
  }

  function handleProviderChange(value: string) {
    const provider = value as AiProvider;
    setConfig((prev) => applyProviderPreset(prev, provider));
    setErrors({});
  }

  function handleSave() {
    const next: AiConfig = {
      ...config,
      baseUrl: config.baseUrl.trim(),
      apiKey: config.apiKey.trim(),
      model: config.model.trim(),
    };
    const result = validateAiConfig(next);
    setErrors(result.errors);
    if (!result.ok) {
      notify('配置未通过校验，请检查标红字段', 'error');
      return;
    }
    if (!saveAiConfig(next)) {
      notify('无法写入本机配置存储', 'error');
      return;
    }
    setConfig(next);
    setSavedAt(new Date().toISOString());
    notify('大模型配置已保存到本机', 'success');
  }

  function handleTest() {
    const result = validateAiConfig(config);
    setErrors(result.errors);
    if (!result.ok) {
      notify('请先补全配置再测试连接', 'error');
      return;
    }
    notify('本轮仅保存本地配置，联网连通性测试将在网络层接入后启用', 'info');
  }

  function handleReset() {
    setConfig({ ...DEFAULT_AI_CONFIG });
    setErrors({});
    setSavedAt(null);
    setShowKey(false);
    clearAiConfig();
    notify('已恢复默认配置并清除本机密钥', 'info');
  }

  const temperatureOptions = Array.from(
    new Set<number>([...TEMPERATURE_OPTIONS, config.temperature]),
  )
    .sort((a, b) => a - b)
    .map((value) => ({ value: String(value), label: String(value) }));

  return (
    <section className="settings-card" aria-labelledby="settings-ai">
      <header className="settings-card-head">
        <div>
          <h2 className="settings-card-title" id="settings-ai">
            <Icon name="link" size={15} />
            大模型
          </h2>
          <p className="settings-card-desc">
            配置模型网关与密钥。密钥只保存在本机 localStorage，不写入工作区、导出或备份。
          </p>
        </div>
        <Badge tone={config.enabled ? 'ok' : 'neutral'} dot>
          {config.enabled ? '已启用' : '未启用'}
        </Badge>
      </header>
      <div className="settings-card-body">
        <div className="ai-config-head-row">
          <span className="settings-note">启用后由内置 MCP 工具承接模型的动作请求。</span>
          <Segmented
            ariaLabel="启用大模型"
            size="sm"
            value={config.enabled ? 'on' : 'off'}
            onChange={(value) => patchField('enabled', value === 'on')}
            options={[
              { value: 'off', label: '关闭' },
              { value: 'on', label: '启用' },
            ]}
          />
        </div>

        <div className="ai-config-grid">
          <Field label="服务商" htmlFor="ai-provider">
            <Select
              id="ai-provider"
              value={config.provider}
              onChange={(event) => handleProviderChange(event.target.value)}
              options={AI_PROVIDERS.map((provider) => ({
                value: provider,
                label: PROVIDER_PRESETS[provider].label,
              }))}
            />
          </Field>

          <Field label="模型" htmlFor="ai-model" required error={errors.model}>
            <TextInput
              id="ai-model"
              value={config.model}
              onChange={(event) => patchField('model', event.target.value)}
              placeholder="例如 gpt-4o-mini"
              spellCheck={false}
            />
          </Field>

          <Field
            label="Base URL"
            htmlFor="ai-base-url"
            required
            error={errors.baseUrl}
            hint={PROVIDER_PRESETS[config.provider].hint}
            className="ai-field--wide"
          >
            <TextInput
              id="ai-base-url"
              value={config.baseUrl}
              onChange={(event) => patchField('baseUrl', event.target.value)}
              placeholder="https://api.example.com/v1"
              spellCheck={false}
            />
          </Field>

          <Field
            label="API Key"
            htmlFor="ai-api-key"
            error={errors.apiKey}
            hint={`当前密钥：${maskSecret(config.apiKey)}`}
            className="ai-field--wide"
          >
            <div className="ai-secret-row">
              <TextInput
                id="ai-api-key"
                type={showKey ? 'text' : 'password'}
                value={config.apiKey}
                onChange={(event) => patchField('apiKey', event.target.value)}
                autoComplete="off"
                spellCheck={false}
                placeholder="sk-…"
              />
              <Button size="sm" variant="ghost" onClick={() => setShowKey((value) => !value)}>
                {showKey ? '隐藏' : '显示'}
              </Button>
            </div>
          </Field>

          <Field label="温度" htmlFor="ai-temperature" error={errors.temperature}>
            <Select
              id="ai-temperature"
              value={String(config.temperature)}
              onChange={(event) => patchField('temperature', Number(event.target.value))}
              options={temperatureOptions}
            />
          </Field>

          <Field label="最大输出 token" htmlFor="ai-max-tokens" error={errors.maxTokens}>
            <TextInput
              id="ai-max-tokens"
              type="number"
              min={128}
              max={8192}
              step={128}
              value={config.maxTokens}
              onChange={(event) => patchField('maxTokens', Number(event.target.value))}
            />
          </Field>

          <Field label="系统提示词" htmlFor="ai-system-prompt" className="ai-field--wide">
            <TextArea
              id="ai-system-prompt"
              rows={3}
              value={config.systemPrompt}
              onChange={(event) => patchField('systemPrompt', event.target.value)}
            />
          </Field>
        </div>

        <div className="settings-actions">
          <Button
            size="sm"
            variant="secondary"
            iconLeft={<Icon name="check" size={14} />}
            onClick={handleSave}
          >
            保存配置
          </Button>
          <Button size="sm" variant="ghost" onClick={handleTest}>
            测试连接
          </Button>
          <Button
            size="sm"
            variant="ghost"
            iconLeft={<Icon name="trash" size={14} />}
            onClick={handleReset}
          >
            恢复默认
          </Button>
        </div>

        {savedAt ? (
          <p className="settings-note">上次保存：{formatDateTime(savedAt)}</p>
        ) : (
          <p className="settings-note">配置尚未保存。</p>
        )}

        <p className="settings-note">
          内置 MCP 已随应用启动，共 {TOOL_DEFINITIONS.length} 个工具；模型可通过它新增事项、更新状态与建立关联。保存配置不会发起网络请求。
        </p>
      </div>
    </section>
  );
}

