import { useEffect, useRef, useState } from 'react';
import type { FormEvent } from 'react';
import { KIND_LABELS } from '../../core/model';
import type { Item } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { Button } from '../../ui/Button';
import { Field, Select, TextArea, TextInput } from '../../ui/Field';
import { Icon } from '../../ui/icons';
import { Modal } from '../../ui/Modal';
import {
  ESTIMATE_OPTIONS,
  PRESET_CONTEXTS,
  appendTimestampedNote,
  buildClarifyNewItem,
  buildClarifyPatch,
  clarifyTargetStatus,
  createClarifyForm,
  desiredKind,
  isArchiveType,
  relativeTimeLabel,
  validateClarifyForm,
} from './gtdLogic';
import type { ClarifyErrors, ClarifyFormState, ClarifyType } from './gtdLogic';

export interface ClarifyDialogProps {
  item: Item | null;
  onClose: () => void;
}

const TYPE_OPTIONS = [
  { value: 'next', label: '下一步行动' },
  { value: 'project', label: '项目（升级）' },
  { value: 'reference', label: '参考资料' },
  { value: 'note', label: '笔记' },
];

const ENERGY_OPTIONS = [
  { value: 'low', label: '低能量' },
  { value: 'medium', label: '中能量' },
  { value: 'high', label: '高能量' },
];

const CONTEXT_OPTIONS = [
  { value: '', label: '未设置场景' },
  ...PRESET_CONTEXTS.map((context) => ({ value: context, label: `@${context}` })),
  { value: '__custom__', label: '自定义场景…' },
];

/** 澄清弹窗：收件箱条目 → 可执行 / 项目 / 参考资料 / 笔记。 */
export function ClarifyDialog({ item, onClose }: ClarifyDialogProps) {
  const createItem = useWorkspace((state) => state.createItem);
  const updateItem = useWorkspace((state) => state.updateItem);
  const setStatus = useWorkspace((state) => state.setStatus);
  const notify = useWorkspace((state) => state.notify);
  const areas = useWorkspace((state) => state.workspace.areas);

  const [form, setForm] = useState<ClarifyFormState | null>(() =>
    item ? createClarifyForm(item) : null,
  );
  const [errors, setErrors] = useState<ClarifyErrors>({});
  const titleRef = useRef<HTMLInputElement>(null);
  const itemId = item?.id ?? null;

  useEffect(() => {
    setForm(item ? createClarifyForm(item) : null);
    setErrors({});
    // 只在切换到另一条条目时重置，避免打字过程中的 store 更新覆盖表单。
  }, [itemId]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!item || !form) return null;

  const archive = isArchiveType(form.type);
  const areaOptions = [
    { value: '', label: '无领域' },
    ...areas.map((area) => ({ value: area.id, label: area.name })),
  ];
  const estimateOptions = [
    { value: '', label: '未估时' },
    ...ESTIMATE_OPTIONS.map((minutes) => ({ value: String(minutes), label: `${minutes} 分钟` })),
  ];

  const patchForm = (patch: Partial<ClarifyFormState>) => {
    setForm((current) => (current ? { ...current, ...patch } : current));
  };

  const changeType = (type: ClarifyType) => {
    const nextArchive = isArchiveType(type);
    patchForm({
      type,
      delegated: nextArchive ? false : form.delegated,
      someday: nextArchive ? false : form.someday,
    });
    setErrors({});
  };

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const nextErrors = validateClarifyForm(form);
    setErrors(nextErrors);
    if (Object.keys(nextErrors).length > 0) return;

    const targetStatus = clarifyTargetStatus(form);
    const patch = buildClarifyPatch(form);
    const desired = desiredKind(form.type);

    try {
      if (archive) {
        const label = form.type === 'reference' ? '参考资料' : '笔记';
        updateItem(item.id, {
          ...patch,
          notes: appendTimestampedNote(patch.notes, `澄清：归档为${label}。`),
        });
        setStatus(item.id, targetStatus);
        notify(`已归档为${label}「${patch.title}」`, 'success');
      } else if (desired === 'action' && item.kind !== 'action' && item.kind !== 'project') {
        const created = createItem(buildClarifyNewItem(form, item, targetStatus));
        updateItem(item.id, {
          notes: appendTimestampedNote(item.notes, `澄清：已转为下一步行动（${created.id}）`),
          gtd: { clarified: true },
        });
        setStatus(item.id, 'done');
        notify(`已转为下一步「${created.title}」`, 'success');
      } else if (desired === 'project' && item.kind !== 'project') {
        const created = createItem(buildClarifyNewItem(form, item, targetStatus));
        updateItem(item.id, {
          notes: appendTimestampedNote(item.notes, `澄清：已升级为项目（${created.id}）`),
          gtd: { clarified: true },
        });
        setStatus(item.id, 'done');
        notify(`已升级为项目「${created.title}」`, 'success');
      } else {
        updateItem(item.id, patch);
        setStatus(item.id, targetStatus);
        notify(`已澄清「${patch.title}」`, 'success');
      }
      onClose();
    } catch (error) {
      notify(error instanceof Error ? error.message : String(error), 'error');
    }
  };

  const upgradeHint =
    form.type === 'project' && item.kind !== 'project'
      ? '提交后会新建项目，并把当前条目归档为来源记录。'
      : form.type === 'next' && item.kind !== 'action' && item.kind !== 'project'
        ? '当前条目不是行动类型；提交后会新建下一步行动，并把原条目归档。'
        : archive
          ? '参考资料 / 笔记会归档，不再出现在收件箱。'
          : null;

  return (
    <Modal
      open
      onClose={onClose}
      title="澄清这一条"
      description={`${KIND_LABELS[item.kind]} · 收集于 ${relativeTimeLabel(
        item.gtd?.capturedAt ?? item.createdAt,
      )}`}
      width={660}
      initialFocusRef={titleRef}
      footer={
        <>
          <Button variant="ghost" size="sm" onClick={onClose}>
            取消
          </Button>
          <Button variant="primary" size="sm" type="submit" form="gtd-clarify-form">
            完成澄清
          </Button>
        </>
      }
    >
      <form id="gtd-clarify-form" className="gtd-form" onSubmit={submit}>
        <div className="gtd-form-grid">
          <Field label="类型" htmlFor="gtd-clarify-type">
            <Select
              id="gtd-clarify-type"
              value={form.type}
              options={TYPE_OPTIONS}
              onChange={(event) => changeType(event.target.value as ClarifyType)}
            />
          </Field>
          <Field label="能量" htmlFor="gtd-clarify-energy">
            <Select
              id="gtd-clarify-energy"
              value={form.energy}
              options={ENERGY_OPTIONS}
              onChange={(event) =>
                patchForm({ energy: event.target.value as ClarifyFormState['energy'] })
              }
            />
          </Field>

          <Field
            label="标题"
            htmlFor="gtd-clarify-title"
            required
            error={errors.title}
            className="gtd-form-span"
          >
            <TextInput
              ref={titleRef}
              id="gtd-clarify-title"
              value={form.title}
              placeholder="用一个动词开头的具体行动"
              onChange={(event) => patchForm({ title: event.target.value })}
            />
          </Field>

          <Field label="备注" htmlFor="gtd-clarify-notes" className="gtd-form-span">
            <TextArea
              id="gtd-clarify-notes"
              rows={2}
              placeholder="成功的标准、链接、下一步线索…"
              value={form.notes}
              onChange={(event) => patchForm({ notes: event.target.value })}
            />
          </Field>

          <Field label="场景 context" htmlFor="gtd-clarify-context">
            <Select
              id="gtd-clarify-context"
              value={form.context}
              options={CONTEXT_OPTIONS}
              onChange={(event) => patchForm({ context: event.target.value })}
            />
          </Field>
          <Field label="预计时长（仅判断 2 分钟）" htmlFor="gtd-clarify-estimate">
            <Select
              id="gtd-clarify-estimate"
              value={form.estimateMin === null ? '' : String(form.estimateMin)}
              options={estimateOptions}
              onChange={(event) =>
                patchForm({ estimateMin: event.target.value ? Number(event.target.value) : null })
              }
            />
          </Field>
          {form.context === '__custom__' ? (
            <Field label="自定义场景" htmlFor="gtd-clarify-custom-context" className="gtd-form-span">
              <TextInput
                id="gtd-clarify-custom-context"
                value={form.customContext}
                placeholder="例如：通勤、飞机上"
                onChange={(event) => patchForm({ customContext: event.target.value })}
              />
            </Field>
          ) : null}

          <Field label="截止日期" htmlFor="gtd-clarify-due">
            <TextInput
              id="gtd-clarify-due"
              type="date"
              value={form.dueDate}
              onChange={(event) => patchForm({ dueDate: event.target.value })}
            />
          </Field>
          <Field label="领域" htmlFor="gtd-clarify-area">
            <Select
              id="gtd-clarify-area"
              value={form.areaId}
              options={areaOptions}
              onChange={(event) => patchForm({ areaId: event.target.value })}
            />
          </Field>

          <Field label="标签" htmlFor="gtd-clarify-tags" className="gtd-form-span">
            <TextInput
              id="gtd-clarify-tags"
              value={form.tags}
              placeholder="空格或逗号分隔，例如：官网 品牌"
              onChange={(event) => patchForm({ tags: event.target.value })}
            />
          </Field>

          <div className="gtd-form-checks gtd-form-span">
            <label className="gtd-checkline">
              <input
                type="checkbox"
                checked={form.delegated}
                disabled={archive}
                onChange={(event) =>
                  patchForm({ delegated: event.target.checked, someday: event.target.checked ? false : form.someday })
                }
              />
              <span>委派给他人，进入等待</span>
            </label>
            <label className="gtd-checkline">
              <input
                type="checkbox"
                checked={form.someday}
                disabled={archive}
                onChange={(event) =>
                  patchForm({ someday: event.target.checked, delegated: event.target.checked ? false : form.delegated })
                }
              />
              <span>某天 / 搁置</span>
            </label>
            <label className="gtd-checkline">
              <input
                type="checkbox"
                checked={form.twoMinuteCandidate || form.estimateMin === 2}
                disabled={archive}
                onChange={(event) => patchForm({ twoMinuteCandidate: event.target.checked })}
              />
              <span>属于 2 分钟规则（提示先做）</span>
            </label>
          </div>

          {form.delegated ? (
            <Field
              label="等待对象"
              htmlFor="gtd-clarify-waiting"
              required
              error={errors.waitingFor}
              className="gtd-form-span"
            >
              <TextInput
                id="gtd-clarify-waiting"
                value={form.waitingFor}
                placeholder="例如：法务 · 张律师"
                onChange={(event) => patchForm({ waitingFor: event.target.value })}
              />
            </Field>
          ) : null}

          {errors.status ? (
            <p className="field-error gtd-form-span" role="alert">
              {errors.status}
            </p>
          ) : null}
        </div>

        {upgradeHint ? (
          <p className="gtd-clarify-callout">
            <Icon name="link" size={14} />
            {upgradeHint}
          </p>
        ) : null}
        {form.twoMinuteCandidate && !archive ? (
          <p className="gtd-clarify-callout gtd-clarify-callout--warn">
            <Icon name="clock" size={14} />
            2 分钟内能完成的事，建议直接做完，不必留在系统里。
          </p>
        ) : null}
      </form>
    </Modal>
  );
}
