import type { Item } from '../../core/model';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { ENERGY_LABELS, contextOf } from './gtdLogic';
import { activateSomedayItem } from './gtdMutations';

export interface SomedayListProps {
  items: Item[];
}

/** 某天 / 搁置：保持低摩擦，一键激活为下一步。 */
export function SomedayList({ items }: SomedayListProps) {
  if (items.length === 0) {
    return (
      <div className="gtd-section-body gtd-empty-body">
        <EmptyState
          icon={<Icon name="flag" size={20} />}
          title="没有搁置的想法"
          description="暂时不做的事，放在这里不占注意力。"
          compact
        />
      </div>
    );
  }

  return (
    <div className="gtd-side-list">
      {items.map((item) => {
        const context = contextOf(item);
        return (
          <div key={item.id} className="gtd-side-row">
            <div className="gtd-side-body">
              <span className="gtd-row-title gtd-row-title--static">{item.title}</span>
              <div className="gtd-row-meta">
                {context ? <Badge tone="info">@{context}</Badge> : null}
                <Badge tone="neutral">能量 {ENERGY_LABELS[item.gtd?.energy ?? 'medium']}</Badge>
              </div>
            </div>
            <Button
              variant="ghost"
              size="sm"
              iconLeft={<Icon name="play" size={12} />}
              onClick={() => activateSomedayItem(item)}
            >
              激活为下一步
            </Button>
          </div>
        );
      })}
    </div>
  );
}
