import type { ReactNode } from 'react';
import clsx from 'clsx';
import { Icon } from '../../ui/icons';
import type { IconName } from '../../ui/icons';

export type GtdSectionKey = 'inbox' | 'next' | 'waiting' | 'someday' | 'projects';

export interface GtdSectionProps {
  id: GtdSectionKey;
  title: string;
  icon: IconName;
  count?: number;
  hint?: ReactNode;
  action?: ReactNode;
  highlighted?: boolean;
  onRef?: (element: HTMLDivElement | null) => void;
  children: ReactNode;
}

/** 流程台里的统一分区外壳：标题、计数、键盘提示、聚焦高亮。 */
export function GtdSection({
  id,
  title,
  icon,
  count,
  hint,
  action,
  highlighted,
  onRef,
  children,
}: GtdSectionProps) {
  return (
    <section
      ref={onRef}
      id={`gtd-${id}`}
      className={clsx('gtd-section', highlighted && 'gtd-section--focus')}
      aria-labelledby={`gtd-${id}-title`}
    >
      <header className="gtd-section-header">
        <div className="gtd-section-heading">
          <span className="gtd-section-icon" aria-hidden="true">
            <Icon name={icon} size={15} />
          </span>
          <h2 className="gtd-section-title" id={`gtd-${id}-title`}>
            {title}
          </h2>
          <span className="gtd-count" aria-hidden="true">
            {count ?? 0}
          </span>
          {hint ? <span className="gtd-section-hint">{hint}</span> : null}
        </div>
        {action ? <div className="gtd-section-action">{action}</div> : null}
      </header>
      {children}
    </section>
  );
}
