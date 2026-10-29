import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import clsx from 'clsx';
import { useWorkspace } from '../../core/store';
import { objectivesOfPeriod, okrPeriods } from '../../core/selectors';
import { currentQuarter } from '../../core/utils';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Field, Select, TextArea, TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { Modal } from '../../ui/Modal';
import { Progress } from '../../ui/Progress';
import { Segmented } from '../../ui/Segmented';
import { filterObjectives, nextQuarter, quarterLabel, summarize } from './okrMath';
import type { OkrDensity, OkrView } from './okrMath';
import { ObjectiveCard } from './ObjectiveCard';
import { ObjectiveEditor } from './ObjectiveEditor';
import { OkrTable } from './OkrTable';
import { OkrAlignment } from './OkrAlignment';
import { QuarterDialog } from './QuarterDialog';
import './okr.css';

const VIEW_OPTIONS: { value: OkrView; label: string; title: string }[] = [
  { value: 'cards', label: '卡片', title: '卡片布局：编辑目标与 KR' },
  { value: 'table', label: '表格', title: '表格：季度复盘，行可展开' },
  { value: 'alignment', label: '对齐', title: '目标 → KR → 执行项大纲' },
];

const DENSITY_OPTIONS: { value: OkrDensity; label: string; title: string }[] = [
  { value: 'compact', label: '紧凑', title: '隐藏指标编辑器与执行项明细' },
  { value: 'detailed', label: '详细', title: '显示指标、负责人与执行项' },
];

export function OkrPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const period = useWorkspace((state) => state.ui.okrPeriod);
  const search = useWorkspace((state) => state.ui.search);
  const setUi = useWorkspace((state) => state.setUi);
  const createItem = useWorkspace((state) => state.createItem);
  const select = useWorkspace((state) => state.select);
  const notify = useWorkspace((state) => state.notify);

  const [view, setView] = useState<OkrView>('cards');
  const [density, setDensity] = useState<OkrDensity>('detailed');
  const [newQuarterOpen, setNewQuarterOpen] = useState(false);
  const [objectiveOpen, setObjectiveOpen] = useState(false);
  const [objectiveTitle, setObjectiveTitle] = useState('');
  const [objectiveNotes, setObjectiveNotes] = useState('');
  const [objectiveAreaId, setObjectiveAreaId] = useState('');
  const [titleError, setTitleError] = useState('');
  // 独立页面式编辑视图：null = 列表态。
  const [editingId, setEditingId] = useState<string | null>(null);
  const restoreFocusId = useRef<string | null>(null);

  const openEditor = useCallback(
    (id: string) => {
      setEditingId(id);
      select(id);
    },
    [select],
  );

  const closeEditor = useCallback((id: string | null) => {
    restoreFocusId.current = id;
    setEditingId(null);
  }, []);

  // 返回列表后把焦点还给对应卡片的编辑按钮（目标已删除时没有可聚焦元素，跳过）。
  useEffect(() => {
    if (editingId !== null) return;
    const id = restoreFocusId.current;
    if (!id) return;
    restoreFocusId.current = null;
    const frame = requestAnimationFrame(() => {
      const target = document.querySelector(`[data-edit-objective="${id}"]`);
      if (target instanceof HTMLElement) target.focus();
    });
    return () => cancelAnimationFrame(frame);
  }, [editingId]);

  const summary = useMemo(() => summarize(workspace, period), [workspace, period]);
  const filtered = useMemo(
    () => filterObjectives(workspace, period, search),
    [workspace, period, search],
  );

  const existingPeriods = okrPeriods(workspace);
  const periodOptions = existingPeriods.includes(period)
    ? existingPeriods
    : [period, ...existingPeriods].sort((a, b) => b.localeCompare(a));

  const areaOptions = [
    { value: '', label: '未归属 Area' },
    ...workspace.areas.map((area) => ({ value: area.id, label: area.name })),
  ];

  const openNewObjective = () => {
    setObjectiveTitle('');
    setObjectiveNotes('');
    setObjectiveAreaId('');
    setTitleError('');
    setObjectiveOpen(true);
  };

  const submitObjective = () => {
    const title = objectiveTitle.trim();
    if (!title) {
      setTitleError('先写下一句定性的季度目标');
      return;
    }
    const created = createItem({
      kind: 'objective',
      title,
      notes: objectiveNotes.trim(),
      status: 'active',
      areaId: objectiveAreaId || null,
      okr: { period, confidence: 5 },
    });
    select(created.id);
    setObjectiveOpen(false);
    notify('季度目标已创建', 'success');
  };

  const hasQuery = search.trim().length > 0;

  return (
    <div className="page okr-page">
      <div className="page-header">
        <div className="page-header-titles">
          <h1>OKR</h1>
          <p>
            用可量化的关键结果推进 {quarterLabel(period)} · 时间已过 {summary.elapsedPercent}%
          </p>
        </div>
        <div className="page-actions okr-header-actions">
          {editingId === null ? (
            <>
              {view === 'cards' ? (
                <Segmented<OkrDensity>
                  options={DENSITY_OPTIONS}
                  value={density}
                  onChange={setDensity}
                  size="sm"
                  ariaLabel="切换卡片密度"
                />
              ) : null}
              <Segmented<OkrView>
                options={VIEW_OPTIONS}
                value={view}
                onChange={setView}
                size="sm"
                ariaLabel="切换 OKR 视图"
              />
              <Button
                variant="primary"
                iconLeft={<Icon name="plus" size={14} />}
                onClick={openNewObjective}
              >
                新建目标
              </Button>
            </>
          ) : null}
        </div>
      </div>

      {editingId !== null ? (
        <ObjectiveEditor
          key={editingId}
          objectiveId={editingId}
          onBack={() => closeEditor(editingId)}
        />
      ) : (
        <>
          <section className="okr-periodbar" aria-label="季度切换">
            <div className="okr-periods" role="group" aria-label="选择季度">
              {periodOptions.map((option) => {
                const active = option === period;
                const count = objectivesOfPeriod(workspace, option).length;
                const isCurrent = option === currentQuarter();
                return (
                  <button
                    key={option}
                    type="button"
                    className={clsx('okr-period-chip', active && 'is-active')}
                    aria-pressed={active}
                    onClick={() => setUi({ okrPeriod: option })}
                  >
                    <span>{quarterLabel(option)}</span>
                    <span className="okr-period-count" aria-label={`${count} 个目标`}>
                      {count}
                    </span>
                    {isCurrent ? <span className="okr-period-now">本季</span> : null}
                  </button>
                );
              })}
            </div>
            <Button
              variant="ghost"
              size="sm"
              iconLeft={<Icon name="plus" size={13} />}
              onClick={() => setNewQuarterOpen(true)}
            >
              新建季度
            </Button>
          </section>

          <section className="okr-health" aria-label="季度健康度">
            <div className="okr-health-stats">
              <div className="okr-stat">
                <span className="okr-stat-value mono">{summary.objectives}</span>
                <span className="okr-stat-label">目标</span>
              </div>
              <div className="okr-stat">
                <span className="okr-stat-value mono">{summary.keyResults}</span>
                <span className="okr-stat-label">关键结果</span>
              </div>
              <div className="okr-stat">
                <span className="okr-stat-value mono">{summary.averageProgress}%</span>
                <span className="okr-stat-label">平均进度</span>
              </div>
              <div className="okr-stat" data-tone={summary.behind > 0 ? 'danger' : 'ok'}>
                <span className="okr-stat-value mono">{summary.behind}</span>
                <span className="okr-stat-label">落后 KR</span>
              </div>
            </div>
            <div className="okr-health-side">
              <div className="okr-conf-summary">
                <span className="okr-conf-summary-label">信心分布</span>
                <Badge tone="danger" dot>
                  低 1–3 · {summary.confidence.low}
                </Badge>
                <Badge tone="warn" dot>
                  中 4–6 · {summary.confidence.mid}
                </Badge>
                <Badge tone="ok" dot>
                  高 7–10 · {summary.confidence.high}
                </Badge>
              </div>
              <div className="okr-time">
                <span className="okr-time-label">季度时间进度</span>
                <Progress
                  value={summary.elapsedPercent}
                  size="sm"
                  tone="info"
                  ariaLabel="季度时间进度"
                />
                <span className="mono">{summary.elapsedPercent}%</span>
              </div>
            </div>
          </section>

          {hasQuery ? (
            <div className="okr-filter-note">
              <Icon name="search" size={14} />
              <span>
                筛选「{search.trim()}」· {filtered.length} 个目标
              </span>
              <Button variant="ghost" size="sm" onClick={() => setUi({ search: '' })}>
                清除筛选
              </Button>
            </div>
          ) : null}

          {filtered.length === 0 ? (
            hasQuery ? (
              <div className="okr-empty">
                <EmptyState
                  icon={<Icon name="search" size={20} />}
                  title="没有匹配的目标或 KR"
                  description={`「${search.trim()}」没有命中 ${quarterLabel(period)} 的目标、关键结果、负责人或 Area。`}
                  action={
                    <Button variant="secondary" onClick={() => setUi({ search: '' })}>
                      清除筛选
                    </Button>
                  }
                />
              </div>
            ) : (
              <div className="okr-empty">
                <EmptyState
                  icon={<Icon name="target" size={20} />}
                  title="本季度还没有目标"
                  description="先写一个定性的目标（O），再用 2–4 个可量化的关键结果（KR）定义「做到了」。例如：目标「让新用户第一周就爱上织理」，KR「NPS 从 42 提升到 60」。"
                  action={
                    <Button
                      variant="primary"
                      iconLeft={<Icon name="plus" size={14} />}
                      onClick={openNewObjective}
                    >
                      新建本季度目标
                    </Button>
                  }
                />
                <div className="okr-empty-tips">
                  <div>
                    <strong>目标（O）</strong>
                    <span>一句定性描述，方向明确、鼓舞人心，不堆数字。</span>
                  </div>
                  <div>
                    <strong>关键结果（KR）</strong>
                    <span>可量化、可验证，带起点与目标值，2–4 个即可。</span>
                  </div>
                  <div>
                    <strong>执行项</strong>
                    <span>把甘特 / GTD 里的项目与行动关联到 KR，形成抓手。</span>
                  </div>
                </div>
              </div>
            )
          ) : view === 'table' ? (
            <OkrTable
              workspace={workspace}
              entries={filtered}
              elapsedPercent={summary.elapsedPercent}
              resetKey={`${period}|${search}`}
            />
          ) : view === 'alignment' ? (
            <OkrAlignment
              workspace={workspace}
              entries={filtered}
              elapsedPercent={summary.elapsedPercent}
              period={period}
            />
          ) : (
            <div className="okr-objectives">
              {filtered.map(({ objective, keyResults }) => (
                <ObjectiveCard
                  key={objective.id}
                  workspace={workspace}
                  objective={objective}
                  keyResults={keyResults}
                  elapsedPercent={summary.elapsedPercent}
                  density={density}
                  onEdit={openEditor}
                />
              ))}
            </div>
          )}
        </>
      )}

      <QuarterDialog
        open={newQuarterOpen}
        title="新建季度"
        description="选择要切换到的季度周期。新建季度后可以立即创建目标。"
        confirmLabel="切换到该季度"
        initialPeriod={nextQuarter(period || currentQuarter())}
        onConfirm={(next) => {
          setNewQuarterOpen(false);
          setUi({ okrPeriod: next });
          notify(`已切换到 ${quarterLabel(next)}`, 'info');
        }}
        onClose={() => setNewQuarterOpen(false)}
      />

      <Modal
        open={objectiveOpen}
        onClose={() => setObjectiveOpen(false)}
        title="新建季度目标"
        description={`周期 ${quarterLabel(period)} · 先写定性目标，随后补充可量化的 KR`}
        width={560}
        footer={
          <>
            <Button variant="ghost" onClick={() => setObjectiveOpen(false)}>
              取消
            </Button>
            <Button variant="primary" onClick={submitObjective}>
              创建目标
            </Button>
          </>
        }
      >
        <div className="okr-objective-form">
          <Field
            label="目标（定性描述）"
            required
            error={titleError || undefined}
            htmlFor="okr-new-objective-title"
          >
            <TextInput
              id="okr-new-objective-title"
              value={objectiveTitle}
              placeholder="例如：让新用户在第一周就爱上织理"
              onChange={(event) => {
                setObjectiveTitle(event.target.value);
                if (titleError) setTitleError('');
              }}
              onKeyDown={(event) => {
                if (event.nativeEvent.isComposing) return;
                if (event.key === 'Enter') {
                  event.preventDefault();
                  submitObjective();
                }
              }}
            />
          </Field>
          <Field label="归属 Area" hint="决定目标在侧栏 Area 下的归属。">
            <Select
              options={areaOptions}
              value={objectiveAreaId}
              aria-label="选择目标归属 Area"
              onChange={(event) => setObjectiveAreaId(event.target.value)}
            />
          </Field>
          <Field label="备注（可选）">
            <TextArea
              rows={2}
              value={objectiveNotes}
              placeholder="为什么这是本季度最重要的事？"
              onChange={(event) => setObjectiveNotes(event.target.value)}
            />
          </Field>
        </div>
      </Modal>
    </div>
  );
}
