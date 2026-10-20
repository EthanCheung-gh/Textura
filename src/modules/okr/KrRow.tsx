import { useEffect, useState } from 'react';
import clsx from 'clsx';
import type { Item, ItemStatus, Workspace } from '../../core/model';
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
import { EditableTitle } from './EditableTitle';
import { ExecutionItemList } from './ExecutionItemList';
import { LinkItemsDialog } from './LinkItemsDialog';
import { MetricEditor } from './MetricEditor';
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
  workspace: Workspace;
  objective: Item;
  kr: Item;
  index: number;
  count: number;
  elapsedPercent: number;
  density: OkrDensity;
  onDelete: (kr: Item) => void;
}

export function KrRow({
  workspace,
  objective,
  kr,
  index,
  count,
  elapsedPercent,
  density,
  onDelete,
}: KrRowProps) {
  const updateItem = useWorkspace((state) => state.updateItem);
  const moveItem = useWorkspace((state) => state.moveItem);
  const setStatus = useWorkspace((state) => state.setStatus);

  const [linkOpen, setLinkOpen] = useState(false);
  const [ownerDraft, setOwnerDraft] = useState(kr.okr?.krOwner ?? '');

  useEffect(() => {
    setOwnerDraft(kr.okr?.krOwner ?? '');
  }, [kr.id, kr.okr?.krOwner]);

  const metric = kr.okr?.metric;
  const progress = rollupProgress(workspace, kr.id);
  const behind = isKrBehind(progress, elapsedPercent);
  const executionItems = executionItemsOf(workspace, kr.id);
  const noGrip = !metric && executionItems.length === 0;
  const confidence = kr.okr?.confidence ?? 5;

  const commitOwner = () => {
    const next = ownerDraft.trim();
    if (next === (kr.okr?.krOwner ?? '')) return;
    updateItem(kr.id, { okr: { krOwner: next } });
  };

  const delta = Math.round(elapsedPercent - progress);
  const paceHint = behind
    ? `落后时间进度 ${delta} 个点`
    : delta < 0
      ? `领先时间进度 ${Math.abs(delta)} 个点`
      : `与时间进度相差 ${delta} 个点`;

  return (
    <li className={clsx('okr-kr', `okr-kr--${density}`)}>
      <div className="okr-kr-main">
        <span className="okr-kr-index mono" aria-hidden="true">
          {String(index + 1).padStart(2, '0')}
        </span>

        <div className="okr-kr-heading">
          <EditableTitle
            value={kr.title}
            ariaLabel={`编辑关键结果标题：${kr.title}`}
            className="okr-kr-title"
            onCommit={(next) => updateItem(kr.id, { title: next })}
          />
          <span className="okr-kr-badges">
            {behind ? (
              <Badge
                tone="danger"
                dot
                className="okr-behind-badge"
                title={`进度 ${progress}% · 季度时间 ${elapsedPercent}%`}
              >
                落后
              </Badge>
            ) : null}
            {noGrip ? (
              <Badge tone="warn" dot title="没有指标，也没有关联执行项">
                缺少抓手
              </Badge>
            ) : null}
            {density === 'compact' ? (
              <>
                <Badge tone={statusTone(kr.status)}>{STATUS_LABELS[kr.status]}</Badge>
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

        <div className="okr-kr-progress">
          <Progress
            value={progress}
            tone={progressTone(progress, behind)}
            size="sm"
            ariaLabel={`${kr.title} 进度`}
          />
          <span className="okr-kr-pct mono">{progress}%</span>
        </div>

        <ConfidenceScale
          value={confidence}
          ariaLabel={`${kr.title} 信心指数`}
          onChange={(next) => updateItem(kr.id, { okr: { confidence: next } })}
        />

        <div className="okr-kr-actions">
          <IconButton
            label={`上移「${kr.title}」`}
            size="sm"
            disabled={index <= 0}
            onClick={() => moveItem(kr.id, objective.id, index - 1)}
          >
            <Icon name="chevron-left" size={14} className="okr-rotate-up" />
          </IconButton>
          <IconButton
            label={`下移「${kr.title}」`}
            size="sm"
            disabled={index >= count - 1}
            onClick={() => moveItem(kr.id, objective.id, index + 1)}
          >
            <Icon name="chevron-right" size={14} className="okr-rotate-down" />
          </IconButton>
          <IconButton label={`关联「${kr.title}」的执行项`} size="sm" onClick={() => setLinkOpen(true)}>
            <Icon name="link" size={14} />
          </IconButton>
          <IconButton
            label={`删除「${kr.title}」`}
            size="sm"
            variant="danger"
            onClick={() => onDelete(kr)}
          >
            <Icon name="trash" size={14} />
          </IconButton>
        </div>
      </div>

      {density === 'detailed' ? (
        <div className="okr-kr-detail">
          <MetricEditor kr={kr} />
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
                  if (event.key === 'Enter') event.currentTarget.blur();
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
          {executionItems.length > 0 ? (
            <ExecutionItemList krTitle={kr.title} items={executionItems} />
          ) : null}
        </div>
      ) : null}

      <LinkItemsDialog
        open={linkOpen}
        kr={kr}
        workspace={workspace}
        onClose={() => setLinkOpen(false)}
      />
    </li>
  );
}
