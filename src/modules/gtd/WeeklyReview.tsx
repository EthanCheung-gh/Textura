import { useState } from 'react';
import type { ReactNode } from 'react';
import type { Item } from '../../core/model';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/icons';
import { Progress } from '../../ui/Progress';
import {
  NO_CONTEXT,
  contextOf,
  deadlineInfo,
  relativeTimeLabel,
  waitingDays,
} from './gtdLogic';
import type { WeeklyReviewStats } from './gtdLogic';
import type { GtdSectionKey } from './GtdSection';

export interface WeeklyReviewProps {
  stats: WeeklyReviewStats;
  onNavigate: (section: GtdSectionKey) => void;
  onGoToday: () => void;
}

type ReviewCardId =
  | 'inbox'
  | 'completed'
  | 'overdue'
  | 'stuck'
  | 'waiting'
  | 'undated'
  | 'stale';

/** 周回顾：卡片式清单 + 回顾完成度。 */
export function WeeklyReview({ stats, onNavigate, onGoToday }: WeeklyReviewProps) {
  const [reviewed, setReviewed] = useState<Set<ReviewCardId>>(new Set());
  const cardIds: ReviewCardId[] = [
    'inbox',
    'completed',
    'overdue',
    'stuck',
    'waiting',
    'undated',
    ...(stats.staleAreas.length > 0 ? (['stale'] as ReviewCardId[]) : []),
  ];
  const reviewedCount = cardIds.filter((id) => reviewed.has(id)).length;
  const reviewedPercent = Math.round((reviewedCount / cardIds.length) * 100);

  const toggleReviewed = (id: ReviewCardId) => {
    setReviewed((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const markAll = () => {
    setReviewed(reviewedCount === cardIds.length ? new Set() : new Set(cardIds));
  };

  return (
    <div className="gtd-review">
      <div className="gtd-review-overview">
        <div className="gtd-review-overview-text">
          <span className="gtd-review-eyebrow">
            <Icon name="calendar" size={14} />
            本周回顾
          </span>
          <h2>让系统重新可信</h2>
          <p>
            {stats.windowStart} → {stats.today} · 收件箱 {stats.inboxCount} 条 · 停滞项目{' '}
            {stats.stuckProjectCount} 个
          </p>
        </div>
        <div className="gtd-review-overview-progress">
          <div className="gtd-review-progress-label">
            <span>回顾完成度</span>
            <span>
              {reviewedCount} / {cardIds.length}
            </span>
          </div>
          <Progress
            value={reviewedPercent}
            tone={reviewedPercent === 100 ? 'ok' : 'accent'}
            showLabel
            ariaLabel="回顾完成度"
          />
        </div>
        <Button variant="secondary" size="sm" onClick={markAll}>
          {reviewedCount === cardIds.length ? '重置回顾状态' : '全部标记已回顾'}
        </Button>
      </div>

      <div className="gtd-review-grid">
        <ReviewCard
          id="inbox"
          title="收件箱清零"
          kicker="收集之后没有澄清，系统就会失真"
          value={stats.inboxCount}
          unit="条待澄清"
          tone={stats.inboxCount > 0 ? 'danger' : 'ok'}
          reviewed={reviewed.has('inbox')}
          onToggleReview={() => toggleReviewed('inbox')}
          action={
            <Button variant="secondary" size="sm" onClick={() => onNavigate('inbox')}>
              去逐条澄清
            </Button>
          }
        >
          <Progress
            value={stats.inboxProgress}
            tone={stats.inboxProgress === 100 ? 'ok' : 'accent'}
            size="sm"
            showLabel
            ariaLabel="收件箱清零进度"
          />
          <ReviewItems
            items={stats.inbox}
            empty="收件箱已清空。"
            meta={(item) => relativeTimeLabel(item.gtd?.capturedAt ?? item.createdAt)}
            onShowAll={() => onNavigate('inbox')}
          />
        </ReviewCard>

        <ReviewCard
          id="completed"
          title="本周完成"
          kicker="最近 7 天已完成的事项"
          value={stats.completedCount}
          unit="条完成"
          tone={stats.completedCount > 0 ? 'ok' : 'neutral'}
          reviewed={reviewed.has('completed')}
          onToggleReview={() => toggleReviewed('completed')}
          action={
            <Button variant="secondary" size="sm" onClick={onGoToday}>
              在今日回看
            </Button>
          }
        >
          <ReviewItems
            items={stats.completedThisWeek}
            empty="本周还没有完成记录，先挑一件小事做完。"
            meta={(item) => relativeTimeLabel(item.completedAt)}
            onShowAll={onGoToday}
          />
        </ReviewCard>

        <ReviewCard
          id="overdue"
          title="超期承诺"
          kicker="截止日期已过且未完成"
          value={stats.overdueCount}
          unit="条超期"
          tone={stats.overdueCount > 0 ? 'danger' : 'ok'}
          reviewed={reviewed.has('overdue')}
          onToggleReview={() => toggleReviewed('overdue')}
          action={
            <Button variant="secondary" size="sm" onClick={() => onNavigate('next')}>
              处理超期
            </Button>
          }
        >
          <ReviewItems
            items={stats.overdue}
            empty="没有超期事项。"
            meta={(item) => deadlineInfo(item, stats.today).label}
            onShowAll={() => onNavigate('next')}
          />
        </ReviewCard>

        <ReviewCard
          id="stuck"
          title="停滞项目"
          kicker="没有「下一步」子动作的项目"
          value={stats.stuckProjectCount}
          unit="个项目"
          tone={stats.stuckProjectCount > 0 ? 'warn' : 'ok'}
          reviewed={reviewed.has('stuck')}
          onToggleReview={() => toggleReviewed('stuck')}
          action={
            <Button variant="secondary" size="sm" onClick={() => onNavigate('projects')}>
              查看项目
            </Button>
          }
        >
          <ReviewItems
            items={stats.stuckProjects}
            empty="所有项目都有正在推进的下一步。"
            meta={(item) => `项目 · ${item.tags.join(' / ') || '无标签'}`}
            onShowAll={() => onNavigate('projects')}
          />
        </ReviewCard>

        <ReviewCard
          id="waiting"
          title="等待超 7 天"
          kicker="委派出去、需要催办的事项"
          value={stats.waitingOverdueCount}
          unit="条等待"
          tone={stats.waitingOverdueCount > 0 ? 'warn' : 'ok'}
          reviewed={reviewed.has('waiting')}
          onToggleReview={() => toggleReviewed('waiting')}
          action={
            <Button variant="secondary" size="sm" onClick={() => onNavigate('waiting')}>
              去催办
            </Button>
          }
        >
          <ReviewItems
            items={stats.waitingOverdue}
            empty="没有超过 7 天的等待。"
            meta={(item) => `已等待 ${waitingDays(item, stats.today)} 天`}
            onShowAll={() => onNavigate('waiting')}
          />
        </ReviewCard>

        <ReviewCard
          id="undated"
          title="无日期任务"
          kicker="没有截止日期的下一步 / 进行中动作"
          value={stats.undatedCount}
          unit="条未排期"
          tone={stats.undatedCount > 0 ? 'warn' : 'ok'}
          reviewed={reviewed.has('undated')}
          onToggleReview={() => toggleReviewed('undated')}
          action={
            <Button variant="secondary" size="sm" onClick={() => onNavigate('next')}>
              安排日期
            </Button>
          }
        >
          <ReviewItems
            items={stats.undatedTasks}
            empty="所有可执行事项都有日期。"
            meta={(item) => contextOf(item) ?? NO_CONTEXT}
            onShowAll={() => onNavigate('next')}
          />
        </ReviewCard>

        {stats.staleAreas.length > 0 ? (
          <ReviewCard
            id="stale"
            title="长期无动作的领域"
            kicker="14 天内没有更新的开放动作"
            value={stats.staleAreas.length}
            unit="个领域"
            tone="warn"
            reviewed={reviewed.has('stale')}
            onToggleReview={() => toggleReviewed('stale')}
            action={
              <Button variant="secondary" size="sm" onClick={() => onNavigate('next')}>
                查看下一步
              </Button>
            }
          >
            <ul className="gtd-review-list">
              {stats.staleAreas.slice(0, 5).map((entry) => (
                <li key={entry.area.id} className="gtd-review-item">
                  <span className="gtd-area-dot" style={{ background: entry.area.color }} />
                  <span className="gtd-review-item-title">{entry.area.name}</span>
                  <span className="gtd-review-item-meta">
                    {entry.openCount} 条 · 最近 {relativeTimeLabel(entry.lastTouched)}
                  </span>
                </li>
              ))}
            </ul>
          </ReviewCard>
        ) : null}
      </div>
    </div>
  );
}

interface ReviewCardProps {
  id: ReviewCardId;
  title: string;
  kicker: string;
  value: number;
  unit: string;
  tone: 'accent' | 'ok' | 'warn' | 'danger' | 'neutral';
  reviewed: boolean;
  onToggleReview: () => void;
  action: ReactNode;
  children: ReactNode;
}

function ReviewCard({
  title,
  kicker,
  value,
  unit,
  tone,
  reviewed,
  onToggleReview,
  action,
  children,
}: ReviewCardProps) {
  return (
    <section className={`gtd-review-card${reviewed ? ' is-reviewed' : ''}`}>
      <div className="gtd-review-card-head">
        <div className="gtd-review-card-titles">
          <h3>{title}</h3>
          <p>{kicker}</p>
        </div>
        <Button
          variant={reviewed ? 'secondary' : 'ghost'}
          size="sm"
          iconLeft={<Icon name="check" size={13} />}
          aria-pressed={reviewed}
          onClick={onToggleReview}
        >
          {reviewed ? '已回顾' : '标记已回顾'}
        </Button>
      </div>
      <div className="gtd-review-metric" data-tone={tone}>
        <strong>{value}</strong>
        <span>{unit}</span>
      </div>
      <div className="gtd-review-card-body">{children}</div>
      <div className="gtd-review-card-footer">{action}</div>
    </section>
  );
}

interface ReviewItemsProps {
  items: Item[];
  empty: string;
  meta: (item: Item) => string;
  onShowAll: () => void;
}

function ReviewItems({ items, empty, meta, onShowAll }: ReviewItemsProps) {
  if (items.length === 0) {
    return (
      <p className="gtd-review-empty">
        <Badge tone="ok" dot>
          {empty}
        </Badge>
      </p>
    );
  }
  const shown = items.slice(0, 5);
  return (
    <>
      <ul className="gtd-review-list">
        {shown.map((item) => (
          <li key={item.id} className="gtd-review-item">
            <span className="gtd-review-dot" aria-hidden="true" />
            <span className="gtd-review-item-title" title={item.title}>
              {item.title}
            </span>
            <span className="gtd-review-item-meta">{meta(item)}</span>
          </li>
        ))}
      </ul>
      {items.length > 5 ? (
        <button type="button" className="gtd-linkbtn" onClick={onShowAll}>
          查看全部 {items.length} 条
          <Icon name="chevron-right" size={12} />
        </button>
      ) : null}
    </>
  );
}
