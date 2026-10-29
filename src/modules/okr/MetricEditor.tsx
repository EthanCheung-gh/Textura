import { useEffect, useId, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import clsx from 'clsx';
import type { Item } from '../../core/model';
import { getWorkspace, useWorkspace } from '../../core/store';
import { Badge } from '../../ui/Badge';
import { metricProgress } from './okrMath';
import type { OkrMetric } from './okrMath';
import {
  EMPTY_METRIC,
  METRIC_FIELDS,
  METRIC_NUMBER_FIELDS,
  flushMetricDrafts,
  metricFieldText,
  metricToDraft,
  metricToText,
  parseMetricNumber,
} from './metricDraft';
import type { MetricDraft, MetricField, MetricFlushDecision } from './metricDraft';
import { formatMetric } from './okrDisplay';

const COMMIT_DELAY_MS = 600;

/** 读取 store 里该 KR 的最新 metric，避免不同字段的提交互相覆盖。 */
function readLatestMetric(krId: string): OkrMetric | null {
  const item = getWorkspace().workspace.items.find((entry) => entry.id === krId);
  if (!item) return null;
  return item.okr?.metric ?? EMPTY_METRIC;
}

/**
 * 指标编辑器：起点 / 当前 / 目标 / 单位。
 *
 * 输入只更新本地草稿；blur / Enter / 停止输入 600ms 后才提交一次 updateItem。
 * 每次提交都基于 store 里的最新 metric 合并单个字段，四个字段互不覆盖。
 * 数值字段为空或非法时不写 store，失焦/Esc 后回退到上一个有效值。
 *
 * `onEscape`：字段内 Esc 先回退本字段，再交给父组件收起这一行的编辑态
 *（保持「Esc = 取消当前字段并结束该编辑目标」的统一语义）。
 */
export function MetricEditor({ kr, onEscape }: { kr: Item; onEscape?: () => void }) {
  const updateItem = useWorkspace((state) => state.updateItem);
  const metric = kr.okr?.metric ?? EMPTY_METRIC;
  // 仅用于指标口径提示；KR 行的进度条统一取自 rollupProgress，避免两套进度来源。
  const progressInfo = metricProgress(kr.okr?.metric);
  const flatRange = progressInfo.state === 'flat';
  const hintId = useId();

  const [draft, setDraft] = useState<MetricDraft>(() => metricToDraft(metric));
  const [focused, setFocused] = useState<MetricField | null>(null);
  const draftRef = useRef<MetricDraft>(draft);
  const lastCommitted = useRef<MetricDraft>(metricToDraft(metric));
  const timers = useRef<Record<MetricField, ReturnType<typeof setTimeout> | null>>({
    start: null,
    current: null,
    target: null,
    unit: null,
  });

  const flushPendingRef = useRef<() => MetricFlushDecision | null>(() => null);

  // 每次渲染更新 ref，卸载 cleanup 不依赖首次渲染的过期闭包。
  flushPendingRef.current = () => {
    const latest = readLatestMetric(kr.id);
    if (!latest) return null;
    const decision = flushMetricDrafts(
      latest,
      draftRef.current,
      lastCommitted.current,
      (metric) => updateItem(kr.id, { okr: { metric } }),
    );
    if (decision) {
      for (const field of decision.fields) {
        lastCommitted.current[field] = decision.normalized[field];
        draftRef.current = { ...draftRef.current, [field]: decision.normalized[field] };
      }
    }
    return decision;
  };

  useEffect(() => {
    const handlePageHide = () => {
      // 页面被关闭/隐藏时先 flush 草稿，再立即保存当前工作区（不等待 400ms 防抖）。
      flushPendingRef.current();
      void getWorkspace().save();
    };
    window.addEventListener('pagehide', handlePageHide);

    return () => {
      window.removeEventListener('pagehide', handlePageHide);
      // 卸载时先 flush 所有待提交字段，再清 timer；不 setState，只读 ref。
      flushPendingRef.current();
      for (const field of METRIC_FIELDS) {
        const timer = timers.current[field];
        if (timer !== null) {
          clearTimeout(timer);
          timers.current[field] = null;
        }
      }
    };
  }, []);

  useEffect(() => {
    const next = { ...draftRef.current };
    let changed = false;

    for (const field of METRIC_FIELDS) {
      const storeText = metricFieldText(metric, field);
      if (field === focused) {
        // 只有 store 被外部改动（例如撤销）时才覆盖正在编辑的草稿。
        if (storeText !== lastCommitted.current[field]) {
          next[field] = storeText;
          lastCommitted.current[field] = storeText;
          changed = true;
        }
      } else {
        if (next[field] !== storeText) {
          next[field] = storeText;
          changed = true;
        }
        lastCommitted.current[field] = storeText;
      }
    }

    if (changed) {
      draftRef.current = next;
      setDraft(next);
    }
  }, [kr.id, metric.start, metric.current, metric.target, metric.unit, focused]);

  const writeDraft = (field: MetricField, raw: string) => {
    const next = { ...draftRef.current, [field]: raw };
    draftRef.current = next;
    setDraft(next);
  };

  const cancelTimer = (field: MetricField) => {
    const timer = timers.current[field];
    if (timer !== null) {
      clearTimeout(timer);
      timers.current[field] = null;
    }
  };

  const revertField = (field: MetricField) => {
    const latest = readLatestMetric(kr.id);
    if (!latest) return;
    const text = metricFieldText(latest, field);
    lastCommitted.current[field] = text;
    writeDraft(field, text);
  };

  /** 提交单个字段；返回是否提交了一个有效值（无变化也算有效）。 */
  const commitField = (field: MetricField): boolean => {
    const raw = draftRef.current[field];
    const latest = readLatestMetric(kr.id);
    if (!latest) return false;

    let nextMetric: OkrMetric;
    let committedText: string;
    let changed: boolean;

    if (field === 'unit') {
      // 单位是文本字段，允许清空；只有数值字段拒绝空值。
      const unit = raw.trim();
      nextMetric = { ...latest, unit };
      committedText = unit;
      changed = latest.unit !== unit;
    } else {
      const parsed = parseMetricNumber(raw);
      if (parsed === null) return false;
      nextMetric = { ...latest, [field]: parsed };
      committedText = metricToText(parsed);
      changed = latest[field] !== parsed;
    }

    lastCommitted.current[field] = committedText;
    if (changed) updateItem(kr.id, { okr: { metric: nextMetric } });
    return true;
  };

  const flush = (field: MetricField): boolean => {
    cancelTimer(field);
    return commitField(field);
  };

  const scheduleCommit = (field: MetricField) => {
    cancelTimer(field);
    timers.current[field] = setTimeout(() => {
      timers.current[field] = null;
      commitField(field);
    }, COMMIT_DELAY_MS);
  };

  const handleChange = (field: MetricField, raw: string) => {
    writeDraft(field, raw);
    scheduleCommit(field);
  };

  const handleBlur = (field: MetricField) => {
    flush(field);
    setFocused(null);
  };

  const handleKeyDown = (field: MetricField, event: KeyboardEvent<HTMLInputElement>) => {
    if (event.nativeEvent.isComposing) return;
    if (event.key === 'Enter') {
      event.preventDefault();
      flush(field);
      revertField(field);
    } else if (event.key === 'Escape') {
      event.preventDefault();
      // 字段级取消：不让 Esc 继续冒泡到编辑视图（第一下只回退，不返回列表）。
      event.stopPropagation();
      cancelTimer(field);
      revertField(field);
      onEscape?.();
    }
  };

  const fieldProps = (field: MetricField, extraClassName?: string) => ({
    className: clsx(
      'input',
      'okr-metric-input',
      field === 'unit' && 'okr-metric-input--unit',
      extraClassName,
    ),
    value: draft[field],
    onFocus: () => setFocused(field),
    onBlur: () => handleBlur(field),
    onKeyDown: (event: KeyboardEvent<HTMLInputElement>) => handleKeyDown(field, event),
  });

  return (
    <div className="okr-metric">
      {METRIC_NUMBER_FIELDS.map((field) => (
        <label
          key={field}
          className={clsx('okr-metric-field', field === 'target' && flatRange && 'okr-metric-field--warn')}
        >
          <span className="okr-metric-label">
            {field === 'start' ? '起点' : field === 'current' ? '当前' : '目标'}
          </span>
          <input
            {...fieldProps(field, field === 'target' && flatRange ? 'okr-metric-input--warn' : undefined)}
            type="number"
            step="any"
            inputMode="decimal"
            aria-label={`${kr.title} 指标${field === 'start' ? '起点' : field === 'current' ? '当前值' : '目标值'}`}
            aria-describedby={field === 'target' && flatRange ? hintId : undefined}
            onChange={(event) => handleChange(field, event.target.value)}
          />
        </label>
      ))}
      <label className="okr-metric-field">
        <span className="okr-metric-label">单位</span>
        <input
          {...fieldProps('unit')}
          type="text"
          aria-label={`${kr.title} 指标单位`}
          placeholder="例如 %"
          onChange={(event) => handleChange('unit', event.target.value)}
        />
      </label>

      <span className="okr-metric-summary">
        {kr.okr?.metric ? (
          <>
            <span className="mono">{formatMetric(kr.okr.metric)}</span>
            {progressInfo.percent !== null ? (
              <>
                <span className="okr-metric-pct">换算 {progressInfo.percent}%</span>
                {progressInfo.state === 'over' ? (
                  <Badge tone="ok" dot>
                    已超额
                  </Badge>
                ) : null}
                {progressInfo.state === 'under' ? (
                  <Badge tone="warn" dot>
                    低于起点
                  </Badge>
                ) : null}
              </>
            ) : null}
          </>
        ) : (
          <span className="okr-metric-missing">未设指标 · 进度按完成比计算</span>
        )}
      </span>

      {flatRange ? (
        <span id={hintId} className="okr-metric-flat-hint" role="status">
          起点与目标相同，无法换算进度；请调整目标值，或直接用完成状态标记 KR。
        </span>
      ) : progressInfo.state === 'invalid' ? (
        <span className="okr-metric-flat-hint" role="status">
          指标数值无效，无法换算进度。
        </span>
      ) : null}
    </div>
  );
}
