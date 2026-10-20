import { Icon } from '../../ui/icons';
import type { IconName } from '../../ui/icons';

export interface StatCard {
  id: string;
  label: string;
  value: string;
  unit?: string;
  meta: string;
  tone?: 'neutral' | 'accent' | 'ok' | 'warn' | 'danger' | 'info';
  icon: IconName;
  ariaLabel: string;
  onClick: () => void;
}

export function StatCards({ cards }: { cards: StatCard[] }) {
  return (
    <div className="dash-stats">
      {cards.map((card) => (
        <button
          key={card.id}
          type="button"
          className="dash-stat"
          data-tone={card.tone ?? 'neutral'}
          aria-label={card.ariaLabel}
          onClick={card.onClick}
        >
          <span className="dash-stat-top">
            <span className="dash-stat-label">{card.label}</span>
            <Icon name={card.icon} size={15} />
          </span>
          <span className="dash-stat-value">
            {card.value}
            {card.unit ? <span className="dash-stat-unit">{card.unit}</span> : null}
          </span>
          <span className="dash-stat-meta" title={card.meta}>
            {card.meta}
          </span>
        </button>
      ))}
    </div>
  );
}
