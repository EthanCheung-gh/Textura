import clsx from 'clsx';

export type ProgressTone = 'accent' | 'ok' | 'warn' | 'danger' | 'info';

export interface ProgressProps {
  value: number;
  tone?: ProgressTone;
  size?: 'sm' | 'md';
  showLabel?: boolean;
  ariaLabel?: string;
  className?: string;
}

export function Progress({
  value,
  tone = 'accent',
  size = 'md',
  showLabel = false,
  ariaLabel = '进度',
  className,
}: ProgressProps) {
  const safe = Math.min(100, Math.max(0, Math.round(Number.isFinite(value) ? value : 0)));
  return (
    <div className={clsx('progress-row', className)}>
      <div
        className={clsx('progress', `progress--${size}`)}
        role="progressbar"
        aria-label={ariaLabel}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={safe}
      >
        <span className={clsx('progress-fill', `progress-fill--${tone}`)} style={{ width: `${safe}%` }} />
      </div>
      {showLabel ? <span className="progress-label">{safe}%</span> : null}
    </div>
  );
}
