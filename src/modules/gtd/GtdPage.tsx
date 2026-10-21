import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Item } from '../../core/model';
import { inboxItems, itemsOfKind, nextActions, somedayItems, waitingItems } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/icons';
import type { IconName } from '../../ui/icons';
import { Segmented } from '../../ui/Segmented';
import type { SegmentedOption } from '../../ui/Segmented';
import { ClarifyDialog } from './ClarifyDialog';
import { GtdSection } from './GtdSection';
import type { GtdSectionKey } from './GtdSection';
import { InboxList } from './InboxList';
import { NextActions } from './NextActions';
import { ProjectPanel } from './ProjectPanel';
import { SomedayList } from './SomedayList';
import { WaitingList } from './WaitingList';
import { WeeklyReview } from './WeeklyReview';
import { currentDateKey, weeklyReview } from './gtdLogic';
import './gtd.css';

type GtdView = 'flow' | 'review';

interface FlowCard {
  key: GtdSectionKey;
  label: string;
  value: number;
  hint: string;
  icon: IconName;
  tone: 'accent' | 'ok' | 'info' | 'neutral';
}

const VIEW_OPTIONS: SegmentedOption<GtdView>[] = [
  { value: 'flow', label: '流程台', icon: <Icon name="workflow" size={14} /> },
  { value: 'review', label: '周回顾', icon: <Icon name="calendar" size={14} /> },
];

/** GTD 五步法在桌面端的落地：收集 → 澄清 → 组织 → 回顾 → 执行。 */
export function GtdPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const setUi = useWorkspace((state) => state.setUi);
  const undo = useWorkspace((state) => state.undo);
  const redo = useWorkspace((state) => state.redo);
  const canUndo = useWorkspace((state) => state.canUndo);
  const canRedo = useWorkspace((state) => state.canRedo);
  const notify = useWorkspace((state) => state.notify);

  const [view, setView] = useState<GtdView>('flow');
  const [clarifyId, setClarifyId] = useState<string | null>(null);
  const [highlight, setHighlight] = useState<GtdSectionKey | null>(null);
  const [pendingFocus, setPendingFocus] = useState<GtdSectionKey | null>(null);
  const sectionRefs = useRef<Partial<Record<GtdSectionKey, HTMLDivElement | null>>>({});

  const today = currentDateKey();
  const inbox = useMemo(() => inboxItems(workspace), [workspace]);
  const next = useMemo(() => nextActions(workspace), [workspace]);
  const waiting = useMemo(() => waitingItems(workspace), [workspace]);
  const someday = useMemo(() => somedayItems(workspace), [workspace]);
  const projects = useMemo(() => itemsOfKind(workspace, 'project'), [workspace]);
  const stats = useMemo(() => weeklyReview(workspace, today), [workspace, today]);
  const clarifyItem: Item | null = clarifyId
    ? workspace.items.find((item) => item.id === clarifyId) ?? null
    : null;

  const focusSection = useCallback((key: GtdSectionKey) => {
    setView('flow');
    setPendingFocus(key);
    setHighlight(key);
  }, []);

  useEffect(() => {
    if (!pendingFocus) return;
    const element = sectionRefs.current[pendingFocus];
    element?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    const timer = window.setTimeout(() => {
      setPendingFocus(null);
      setHighlight(null);
    }, 1800);
    return () => window.clearTimeout(timer);
  }, [pendingFocus, view]);

  // Ctrl/Cmd+Z 撤销删除等写操作；Shift 组合为重做。输入框内交还给原生编辑。
  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      const tag = target?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target?.isContentEditable) return;
      if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== 'z') return;
      event.preventDefault();
      if (event.shiftKey) {
        if (!canRedo()) return;
        redo();
        notify('已重做', 'info');
      } else {
        if (!canUndo()) return;
        undo();
        notify('已撤销上一步', 'info');
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [undo, redo, canUndo, canRedo, notify]);

  const cards: FlowCard[] = [
    { key: 'inbox', label: '收件箱待澄清', value: inbox.length, hint: '收集 → 澄清', icon: 'inbox', tone: 'accent' },
    { key: 'next', label: '下一步', value: next.length, hint: '组织 → 执行', icon: 'play', tone: 'ok' },
    { key: 'waiting', label: '等待中', value: waiting.length, hint: '委派与跟进', icon: 'clock', tone: 'info' },
    { key: 'someday', label: '某天 / 搁置', value: someday.length, hint: '暂时不做', icon: 'flag', tone: 'neutral' },
  ];

  const keyboardHint = (
    <span className="gtd-kbd-hint">
      <kbd>↑</kbd>
      <kbd>↓</kbd> 选择 <kbd>x</kbd> 完成 <kbd>Enter</kbd> 打开澄清
    </span>
  );

  const inboxHint = (
    <>
      <span
        className="gtd-section-note"
        title="收件箱条目来自「快速收集」，澄清后才能进入下一步。"
      >
        来自快速收集 · 澄清后进入下一步
      </span>
      {keyboardHint}
    </>
  );

  return (
    <div className="page gtd-page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>GTD · 织理</h1>
          <p>收集、澄清、组织、回顾、执行 —— 让每件事都有归处。</p>
        </div>
        <div className="page-actions">
          <Segmented
            options={VIEW_OPTIONS}
            value={view}
            onChange={setView}
            size="sm"
            ariaLabel="GTD 视图切换"
          />
          <Button
            variant="primary"
            size="md"
            iconLeft={<Icon name="plus" size={14} />}
            title="收集到收件箱 · 收集后需澄清（快捷键 ⌘/Ctrl+N）"
            aria-label="收集到收件箱 · 收集后需澄清（快捷键 ⌘/Ctrl+N）"
            onClick={() => setUi({ quickCaptureOpen: true })}
          >
            快速收集
          </Button>
        </div>
      </div>

      {view === 'flow' ? (
        <>
          <nav className="gtd-flowbar" aria-label="GTD 流程概览">
            {cards.map((card) => (
              <button
                key={card.key}
                type="button"
                className={`gtd-flow-card gtd-flow-card--${card.tone}`}
                onClick={() => focusSection(card.key)}
                aria-label={`${card.label} ${card.value} 条，点击聚焦分区`}
              >
                <span className="gtd-flow-card-top">
                  <Icon name={card.icon} size={14} />
                  {card.label}
                </span>
                <span className="gtd-flow-card-value">{card.value}</span>
                <span className="gtd-flow-card-hint">{card.hint}</span>
              </button>
            ))}
          </nav>

          <div className="gtd-layout">
            <div className="gtd-column">
              <GtdSection
                id="inbox"
                title="收件箱"
                icon="inbox"
                count={inbox.length}
                hint={inboxHint}
                highlighted={highlight === 'inbox'}
                onRef={(element) => {
                  sectionRefs.current.inbox = element;
                }}
              >
                <InboxList
                  items={inbox}
                  onClarify={(item) => setClarifyId(item.id)}
                  onFocusNext={() => focusSection('next')}
                />
              </GtdSection>

              <GtdSection
                id="next"
                title="下一步"
                icon="play"
                count={next.length}
                hint={keyboardHint}
                highlighted={highlight === 'next'}
                onRef={(element) => {
                  sectionRefs.current.next = element;
                }}
              >
                <NextActions items={next} today={today} onClarify={(item) => setClarifyId(item.id)} />
              </GtdSection>
            </div>

            <div className="gtd-column gtd-column--side">
              <GtdSection
                id="waiting"
                title="等待中"
                icon="clock"
                count={waiting.length}
                highlighted={highlight === 'waiting'}
                onRef={(element) => {
                  sectionRefs.current.waiting = element;
                }}
              >
                <WaitingList items={waiting} today={today} />
              </GtdSection>

              <GtdSection
                id="someday"
                title="某天 / 搁置"
                icon="flag"
                count={someday.length}
                highlighted={highlight === 'someday'}
                onRef={(element) => {
                  sectionRefs.current.someday = element;
                }}
              >
                <SomedayList items={someday} />
              </GtdSection>

              <GtdSection
                id="projects"
                title="项目健康度"
                icon="folder"
                count={projects.length}
                highlighted={highlight === 'projects'}
                onRef={(element) => {
                  sectionRefs.current.projects = element;
                }}
              >
                <ProjectPanel workspace={workspace} onFocusNext={() => focusSection('next')} />
              </GtdSection>
            </div>
          </div>
        </>
      ) : (
        <WeeklyReview stats={stats} onNavigate={focusSection} onGoToday={() => setUi({ route: 'dashboard' })} />
      )}

      <ClarifyDialog
        key={clarifyItem?.id ?? 'closed'}
        item={clarifyItem}
        onClose={() => setClarifyId(null)}
      />
    </div>
  );
}
