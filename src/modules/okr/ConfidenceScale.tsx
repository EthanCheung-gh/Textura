import { useRef } from 'react';
import clsx from 'clsx';
import { confidenceBucket } from './okrMath';

interface ConfidenceScaleProps {
  value: number;
  onChange: (value: number) => void;
  ariaLabel: string;
  size?: 'sm' | 'md';
}

const SCORES = Array.from({ length: 10 }, (_, index) => index + 1);

/**
 * 1–10 信心刻度。单选按钮组：方向键切换、Home/End 跳转，
 * 只保留当前值一个 tab 停靠点，键盘可达。
 */
export function ConfidenceScale({ value, onChange, ariaLabel, size = 'sm' }: ConfidenceScaleProps) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const active = Math.min(10, Math.max(1, Math.round(Number.isFinite(value) ? value : 5)));
  const bucket = confidenceBucket(active);

  const move = (next: number) => {
    const clamped = Math.min(10, Math.max(1, next));
    onChange(clamped);
    refs.current[clamped - 1]?.focus();
  };

  return (
    <div
      className={clsx('okr-conf', `okr-conf--${size}`, `okr-conf--${bucket}`)}
      role="radiogroup"
      aria-label={ariaLabel}
    >
      {SCORES.map((score) => {
        const checked = score === active;
        return (
          <button
            key={score}
            ref={(node) => {
              refs.current[score - 1] = node;
            }}
            type="button"
            role="radio"
            aria-checked={checked}
            aria-label={`信心 ${score} 分`}
            title={`信心 ${score}/10`}
            tabIndex={checked ? 0 : -1}
            className={clsx(
              'okr-conf-btn',
              checked && 'is-active',
              `okr-conf-btn--${confidenceBucket(score)}`,
            )}
            onClick={() => onChange(score)}
            onKeyDown={(event) => {
              if (event.key === 'ArrowRight' || event.key === 'ArrowUp') {
                event.preventDefault();
                move(active + 1);
              } else if (event.key === 'ArrowLeft' || event.key === 'ArrowDown') {
                event.preventDefault();
                move(active - 1);
              } else if (event.key === 'Home') {
                event.preventDefault();
                move(1);
              } else if (event.key === 'End') {
                event.preventDefault();
                move(10);
              }
            }}
          >
            {score}
          </button>
        );
      })}
    </div>
  );
}
