import { memo, useEffect, useState } from 'react';
import clsx from 'clsx';
import type { Item, ItemStatus } from '../../core/model';
import { STATUS_LABELS } from '../../core/model';
import { rollupProgress } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { Select, TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { IconButton } from '../../ui/IconButton';
import { Progress } from '../../ui/Progress';
import { ConfidenceScale } from './ConfidenceScale';
import { EditPencil } from './EditPencil';
import { ExecutionItemList } from './ExecutionItemList';
import { LinkItemsDialog } from './LinkItemsDialog';
import { MetricEditor } from './MetricEditor';
import { editTargetKey } from './editTarget';
import { executionItemsOf, isKrBehind } from './okrMath';
import type { OkrDensity } from './okrMath';
import {
  formatMetric,
  formatNumber,
  progressTone,
  statusTone,
  unitSuffix,
} from './okrDisplay';

const KR_STATUS_OPTIONS = (['next', 'active', 'waiting', 'scheduled', 'done', 'dropped'] as ItemStatus[]).map(
  (status) => ({ value: status, label: STATUS_LABELS[status] }),
);

interface KrRowProps {
  objective: Item;
  kr: Item;
  index: number;
  count: number;
  elapsedPercent: number;
  density: OkrDensity;
  onDelete?: (kr: Item) => void;
  /**
   * 列表卡片只读：只渲染展示内容（标题/状态/指标/负责人/信心/进度/执行项摘要），
   * 不挂载任何输入控件、行内操作按钮与关联弹窗。编辑视图保持 `false`。
   */
  readOnly?: boolean;
  /**
   * 编辑视图里的单编辑态：同一目标下由父组件保证最多一行为 true。
   * `false` 时只渲染文本 + 铅笔（display 态），`true` 时渲染完整编辑器。
   */
  editing?: boolean;
  /** display 态点铅笔：父组件把唯一编辑目标切到本行。 */
  onStartEdit?: () => void;
  /** 编辑器内的「完成」/ Esc：父组件收起编辑目标。 */
  onDone?: () => void;
}

/**
 * 单条 KR，三态：
 *
 * - `readOnly`：列表卡片，纯文本 + 只读信心，无操作按钮。
 * - `!readOnly && !editing`：编辑视图的 display 态，文本 + 铅笔 / 上下移 / 删除，
 *   不挂载 MetricEditor、TextInput、Select、ExecutionItemList 与关联按钮。
 * - `editing`：完整编辑器 + 「完成」，同一时刻只有一行处于该态。
 *
 * props 只含 item（引用稳定）与原始值 / 稳定回调：修改 A 条 KR 时其余行可被
 * React.memo 跳过。执行项通过自己的订阅获取（内容不变时返回同一数组引用）。
 */
export const KrRow = memo(function KrRow({
  objective,
  kr,
  index,
  count,
  elapsedPercent,
  density,
  onDelete,
  readOnly = false,
  editing = false,
  onStartEdit,
  onDone,
}: KrRowProps) {
  const updateItem = useWorkspace((state) => state.updateItem);
  const moveItem = useWorkspace((state) => state.moveItem);
  const setStatus = useWorkspace((state) => state.setStatus);
  const executionItems = useWorkspace((state) => executionItemsOf(state.workspace, kr.id));
  // 只订阅本行的进度数字：其他 KR 的写入不会让本行重渲染。
  const progress = useWorkspace((state) => rollupProgress(state.workspace, kr.id));

  const [linkOpen, setLinkOpen] = useState(false);
  const [ownerDraft, setOwnerDraft] = useState(kr.okr?.krOwner ?? '');
  const [titleDraft, setTitleDraft] = useState(kr.title);

  useEffect(() => {
    setOwnerDraft(kr.okr?.krOwner ?? '');
  }, [kr.id, kr.okr?.krOwner, editing]);

  // 进入 / 离开编辑态时用 store 里的最新值重置草稿（取消过的输入不残留）。
  useEffect(() => {
    setTitleDraft(kr.title);
  }, [kr.id, kr.title, editing]);

  const metric = kr.okr?.metric;
  const behind = isKrBehind(progress, elapsedPercent);
  const noGrip = !metric && executionItems.length === 0;
  const confidence = kr.okr?.confidence ?? 5;

  const commitOwner = () => {
    const next = ownerDraft.trim();
    if (next === (kr.okr?.krOwner ?? '')) return;
    updateItem(kr.id, { okr: { krOwner: next } });
  };

  const commitTitle = () => {
    const next = titleDraft.trim();
    if (next && next !== kr.title) updateItem(kr.id, { title: next });
    else setTitleDraft(kr.title);
  };

  const delta = Math.round(elapsedPercent - progress);
  const paceHint = behind
    ? `落后时间进度 ${delta} 个点`
    : delta < 0
      ? `领先时间进度 ${Math.abs(delta)} 个点`
      : `与时间进度相差 ${delta} 个点`;

  const doneCount = executionItems.filter((entry) => entry.item.status === 'done').length;

  const statusBadge = <Badge tone={statusTone(kr.status)}>{STATUS_LABELS[kr.status]}</Badge>;
  const behindBadge = behind ? (
    <Badge
      tone="danger"
      dot
      className="okr-behind-badge"
      title={`进度 ${progress}% · 季度时间 ${elapsedPercent}%`}
    >
      落后
    </Badge>
  ) : null;
  const noGripBadge = noGrip ? (
    <Badge tone="warn" dot title="没有指标，也没有关联执行项">
      缺少抓手
    </Badge>
  ) : null;

  const progressBlock = (
    <div className="okr-kr-progress">
      <Progress
        value={progress}
        tone={progressTone(progress, behind)}
        size="sm"
        ariaLabel={`${kr.title} 进度`}
      />
      <span className="okr-kr-pct mono">{progress}%</span>
    </div>
  );

  const moveUp = (
    <IconButton
      label={`上移「${kr.title}」`}
      size="sm"
      disabled={index <= 0}
      onClick={() => moveItem(kr.id, objective.id, index - 1)}
    >
      <Icon name="chevron-left" size={14} className="okr-rotate-up" />
    </IconButton>
  );
  const moveDown = (
    <IconButton
      label={`下移「${kr.title}」`}
      size="sm"
      disabled={index >= count - 1}
      onClick={() => moveItem(kr.id, objective.id, index + 1)}
    >
      <Icon name="chevron-right" size={14} className="okr-rotate-down" />
    </IconButton>
  );
  const deleteButton = (
    <IconButton
      label={`删除「${kr.title}」`}
      size="sm"
      variant="danger"
      onClick={() => onDelete?.(kr)}
    >
      <Icon name="trash" size={14} />
    </IconButton>
  );

  if (readOnly) {
    return (
      <li className={clsx('okr-kr', `okr-kr--${density}`, 'okr-kr--readonly')}>
        <div className="okr-kr-main">
          <span className="okr-kr-index mono" aria-hidden="true">
            {String(index + 1).padStart(2, '0')}
          </span>

          <div className="okr-kr-heading">
            <span className={clsx('okr-kr-title', 'okr-kr-title--readonly')}>{kr.title}</span>
            <span className="okr-kr-badges">
              {behindBadge}
              {noGripBadge}
              {statusBadge}
              <span className="okr-kr-inline-metric mono">
                {metric ? formatMetric(metric) : '无指标'}
              </span>
              <span className="okr-kr-owner">{kr.okr?.krOwner || '未指派'}</span>
            </span>
          </div>

          {progressBlock}

          <ConfidenceScale value={confidence} readOnly ariaLabel={`${kr.title} 信心指数`} />
        </div>

        <div className="okr-kr-detail okr-kr-detail--readonly">
          <span className={clsx('okr-kr-pace', behind && 'is-behind')}>{paceHint}</span>
          <span className="okr-kr-exec-line">
            执行项 {executionItems.length} · 已完成 {doneCount}
          </span>
        </div>
      </li>
    );
  }

  /* ---------- display 态：文本 + 铅笔，不挂载任何输入控件 ---------- */
  if (!editing) {
    return (
      <li className={clsx('okr-kr', `okr-kr--${density}`, 'okr-kr--display')}>
        <div className="okr-kr-main">
          <span className="okr-kr-index mono" aria-hidden="true">
            {String(index + 1).padStart(2, '0')}
          </span>

          <div className="okr-kr-heading">
            <span className={clsx('okr-kr-title', 'okr-kr-title--readonly')}>{kr.title}</span>
            <span className="okr-kr-badges">
              {behindBadge}
              {noGripBadge}
              {statusBadge}
              <span className="okr-kr-inline-metric mono">
                {metric ? formatMetric(metric) : '无指标'}
              </span>
              <span className="okr-kr-owner">{kr.okr?.krOwner || '未指派'}</span>
            </span>
          </div>

          {progressBlock}

          <ConfidenceScale value={confidence} readOnly ariaLabel={`${kr.title} 信心指数`} />

          <div className="okr-kr-actions">
            <EditPencil
              target={editTargetKey({ kind: 'kr', id: kr.id })}
              label={`编辑关键结果：${kr.title}`}
              onClick={() => onStartEdit?.()}
            />
            {moveUp}
            {moveDown}
            {deleteButton}
          </div>
        </div>

        <div className="okr-kr-detail okr-kr-detail--readonly">
          <span className={clsx('okr-kr-pace', behind && 'is-behind')}>{paceHint}</span>
          <span className="okr-kr-exec-line">
            执行项 {executionItems.length} · 已完成 {doneCount}
          </span>
        </div>
      </li>
    );
  }

  /* ---------- editing 态：完整编辑器 ---------- */
  return (
    <li className={clsx('okr-kr', `okr-kr--${density}`, 'okr-kr--editing')}>
      <div className="okr-kr-main">
        <span className="okr-kr-index mono" aria-hidden="true">
          {String(index + 1).padStart(2, '0')}
        </span>

        <div className="okr-kr-heading">
          <TextInput
            autoFocus
            className="okr-kr-title-input"
            value={titleDraft}
            aria-label={`关键结果标题：${kr.title}`}
            onChange={(event) => setTitleDraft(event.target.value)}
            onBlur={commitTitle}
            onKeyDown={(event) => {
              if (event.nativeEvent.isComposing) return;
              if (event.key === 'Enter') {
                event.preventDefault();
                event.currentTarget.blur();
              } else if (event.key === 'Escape') {
                event.preventDefault();
                event.stopPropagation();
                setTitleDraft(kr.title);
                onDone?.();
              }
            }}
          />
          <span className="okr-kr-badges">
            {behindBadge}
            {noGripBadge}
            {density === 'compact' ? (
              <>
                {statusBadge}
                <span className="okr-kr-inline-metric mono">
                  {metric
                    ? `${formatNumber(metric.current)} / ${formatNumber(metric.target)}${unitSuffix(metric.unit)}`
                    : '无指标'}
                </span>
                <span className="okr-kr-owner">{kr.okr?.krOwner || '未指派'}</span>
              </>
            ) : null}
          </span>
        </div>

        {progressBlock}

        <ConfidenceScale
          value={confidence}
          ariaLabel={`${kr.title} 信心指数`}
          onChange={(next) => updateItem(kr.id, { okr: { confidence: next } })}
        />

        <div className="okr-kr-actions">
          {moveUp}
          {moveDown}
          {deleteButton}
          <Button size="sm" variant="ghost" iconLeft={<Icon name="check" size={13} />} onClick={() => onDone?.()}>
            完成
          </Button>
        </div>
      </div>

      {density === 'detailed' ? (
        <div className="okr-kr-detail">
          <MetricEditor kr={kr} onEscape={() => onDone?.()} />
          <div className="okr-kr-meta">
            <label className="okr-mini-field">
              <span>负责人</span>
              <TextInput
                className="okr-mini-input"
                value={ownerDraft}
                placeholder="未指派"
                aria-label={`${kr.title} 负责人`}
                onChange={(event) => setOwnerDraft(event.target.value)}
                onBlur={commitOwner}
                onKeyDown={(event) => {
                  if (event.nativeEvent.isComposing) return;
                  if (event.key === 'Enter') {
                    event.currentTarget.blur();
                  } else if (event.key === 'Escape') {
                    event.preventDefault();
                    event.stopPropagation();
                    setOwnerDraft(kr.okr?.krOwner ?? '');
                    onDone?.();
                  }
                }}
              />
            </label>
            <label className="okr-mini-field">
              <span>状态</span>
              <Select
                className="okr-mini-input"
                options={KR_STATUS_OPTIONS}
                value={kr.status}
                aria-label={`${kr.title} 状态`}
                onChange={(event) => setStatus(kr.id, event.target.value as ItemStatus)}
              />
            </label>
            <Button
              size="sm"
              variant="secondary"
              iconLeft={<Icon name="link" size={14} />}
              onClick={() => setLinkOpen(true)}
            >
              关联执行项{executionItems.length > 0 ? ` (${executionItems.length})` : ''}
            </Button>
            <span className={clsx('okr-kr-pace', behind && 'is-behind')}>
              {paceHint}
              {metric ? ` · 指标 ${formatMetric(metric)}` : ''}
              {executionItems.length === 0 ? ' · 尚未关联执行项' : ''}
            </span>
          </div>
          <ExecutionItemList krTitle={kr.title} items={executionItems} />
        </div>
      ) : null}

      {/* 只在需要时挂载：避免 100 条 KR 各带一个弹窗订阅 store。 */}
      {linkOpen ? <LinkItemsDialog open kr={kr} onClose={() => setLinkOpen(false)} /> : null}
    </li>
  );
});
