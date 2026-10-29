/**
 * 目标编辑视图「渐进式编辑」回归：默认态不得渲染任何输入控件。
 *
 * 用 `react-dom/server` 的 `renderToStaticMarkup` 渲染真实 `ObjectiveEditor`
 *（store 播种演示数据，objectiveId = obj_activation），对最终 markup 做断言 ——
 * 覆盖「编辑视图打开时是否还会挂载 input/select/textarea/contenteditable」，
 * 而不是只测某个子组件的 props。交互（点铅笔 / 单编辑态 / Esc）由无头实测覆盖。
 */
import { createElement } from 'react';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createSeedWorkspace } from '../../core/fixtures';
import { useWorkspace } from '../../core/store';
import { ObjectiveEditor } from './ObjectiveEditor';
import { editTargetKey, isEditingKr, isSameTarget, nextEditTarget } from './editTarget';

const OBJECTIVE_ID = 'obj_activation';
const OBJECTIVE_TITLE = '让新用户在第一周就爱上织理';
const DEMO_NOTES = '本季度聚焦激活与留存，所有 KR 以周为单位复盘。';

let markup = '';

/**
 * SSR 的 server snapshot 来自 zustand 的 `getInitialState()`，而 store 初始态是空工作区
 *（`setState` 不会改写它）。把 react 默认导出上的 `useSyncExternalStore` 临时换成
 * 「只读当前快照」，`renderToStaticMarkup` 才能渲染真实 store 的当前状态。
 * 仅在本测试文件的 SSR 渲染里生效，浏览器路径不受影响。
 */
const originalUseSyncExternalStore = React.useSyncExternalStore;

function useClientSnapshot<T>(_subscribe: unknown, getSnapshot: () => T): T {
  return getSnapshot();
}

function primeStore(): ReturnType<typeof createSeedWorkspace> {
  const workspace = createSeedWorkspace();
  // 编辑视图的数据来源就是这个 store；SSR 下组件内部订阅同样需要 ready 的工作区。
  useWorkspace.setState({ workspace, status: 'ready' });
  return workspace;
}

function renderEditor(): string {
  return renderToStaticMarkup(
    createElement(ObjectiveEditor, { objectiveId: OBJECTIVE_ID, onBack: () => {} }),
  );
}

beforeAll(() => {
  primeStore();
  React.useSyncExternalStore = useClientSnapshot;
  markup = renderEditor();
});

afterAll(() => {
  React.useSyncExternalStore = originalUseSyncExternalStore;
});

describe('目标编辑视图默认只读（渐进式编辑）', () => {
  it('默认 markup 不含 input / select / textarea / contenteditable', () => {
    expect(markup).not.toContain('<input');
    expect(markup).not.toContain('<select');
    expect(markup).not.toContain('<textarea');
    expect(markup).not.toContain('contenteditable');
    expect(markup).not.toContain('okr-metric-input');
  });

  it('每个可编辑字段都留了铅笔入口（aria-label + data-edit-target）', () => {
    for (const label of [
      '编辑目标标题',
      '编辑目标领域',
      '编辑目标状态',
      '编辑目标信心',
      '编辑目标备注',
    ]) {
      expect(markup).toContain(`aria-label="${label}"`);
    }
    for (const key of ['title', 'area', 'status', 'confidence', 'notes', 'add-kr']) {
      expect(markup).toContain(`data-edit-target="${key}"`);
    }
  });

  it('KR 行处于 display 态：文本 + 铅笔，不挂载指标编辑器', () => {
    expect(markup).toContain('okr-kr--display');
    expect(markup).not.toContain('okr-kr--editing');
    expect(markup).not.toContain('okr-kr-title-input');
    expect(markup).not.toContain('okr-mini-input');
    expect(markup).not.toContain('okr-exec-list');
    expect(markup).not.toContain('okr-check');
    // 每条 KR 一支铅笔，label 里带标题；data-edit-target 与 editTargetKey 一致。
    expect(markup).toContain('aria-label="编辑关键结果：NPS 从 42 提升到 60"');
    expect(markup).toContain(`data-edit-target="${editTargetKey({ kind: 'kr', id: 'kr_nps' })}"`);
    expect(markup).toContain(`data-edit-target="${editTargetKey({ kind: 'kr', id: 'kr_wau' })}"`);
  });

  it('新增 KR 默认只是一个按钮', () => {
    expect(markup).toContain('新增关键结果');
    expect(markup).not.toContain('okr-add-kr-input');
  });

  it('目标级字段显示文本 / Badge / 只读刻度，备注直接显示文本', () => {
    expect(markup).toContain(OBJECTIVE_TITLE);
    expect(markup).toContain('产品');
    expect(markup).toContain('进行中');
    expect(markup).toContain('okr-conf--readonly');
    expect(markup).not.toContain('role="radiogroup"');
    expect(markup).toContain(DEMO_NOTES);
  });

  it('KR 行仍展示状态、指标、负责人与执行项摘要（信息不丢）', () => {
    expect(markup).toContain('42 → 60 分');
    expect(markup).toContain('林一');
    expect(markup).toContain('执行项 ');
    expect(markup).toContain('已完成 ');
    // 上移 / 下移 / 删除仍在 display 态的操作区。
    expect(markup).toContain('上移「NPS 从 42 提升到 60」');
    expect(markup).toContain('下移「NPS 从 42 提升到 60」');
    expect(markup).toContain('删除「NPS 从 42 提升到 60」');
  });

  it('备注为空 / 无 Area 时显示占位文案', () => {
    const workspace = createSeedWorkspace();
    useWorkspace.setState({
      workspace: {
        ...workspace,
        items: workspace.items.map((item) =>
          item.id === OBJECTIVE_ID ? { ...item, notes: '', areaId: null } : item,
        ),
      },
      status: 'ready',
    });
    try {
      const empty = renderEditor();
      expect(empty).toContain('添加备注');
      expect(empty).toContain('未归属 Area');
      expect(empty).not.toContain('<textarea');
    } finally {
      primeStore();
    }
  });
});

describe('EditTarget 状态机', () => {
  it('切换目标即替换，任何时刻最多一个', () => {
    expect(nextEditTarget(null, { kind: 'kr', id: 'kr_nps' })).toEqual({ kind: 'kr', id: 'kr_nps' });
    expect(nextEditTarget({ kind: 'kr', id: 'kr_nps' }, { kind: 'kr', id: 'kr_wau' })).toEqual({
      kind: 'kr',
      id: 'kr_wau',
    });
    expect(nextEditTarget({ kind: 'kr', id: 'kr_nps' }, { kind: 'title' })).toEqual({ kind: 'title' });
    expect(nextEditTarget({ kind: 'notes' }, { kind: 'add-kr' })).toEqual({ kind: 'add-kr' });
  });

  it('收起：传 null 或再点同一支铅笔都回到只读', () => {
    expect(nextEditTarget({ kind: 'title' }, null)).toBeNull();
    expect(nextEditTarget({ kind: 'add-kr' }, null)).toBeNull();
    expect(nextEditTarget({ kind: 'kr', id: 'kr_nps' }, { kind: 'kr', id: 'kr_nps' })).toBeNull();
    expect(nextEditTarget({ kind: 'confidence' }, { kind: 'confidence' })).toBeNull();
  });

  it('isSameTarget：KR 按 id 比较，其余按字段名', () => {
    expect(isSameTarget({ kind: 'kr', id: 'a' }, { kind: 'kr', id: 'a' })).toBe(true);
    expect(isSameTarget({ kind: 'kr', id: 'a' }, { kind: 'kr', id: 'b' })).toBe(false);
    expect(isSameTarget({ kind: 'kr', id: 'a' }, { kind: 'title' })).toBe(false);
    expect(isSameTarget(null, null)).toBe(true);
    expect(isSameTarget({ kind: 'title' }, null)).toBe(false);
    expect(isSameTarget({ kind: 'notes' }, { kind: 'notes' })).toBe(true);
  });

  it('editTargetKey 生成 data-edit-target 的稳定键', () => {
    expect(editTargetKey({ kind: 'kr', id: 'kr_nps' })).toBe('kr:kr_nps');
    expect(editTargetKey({ kind: 'add-kr' })).toBe('add-kr');
    expect(editTargetKey({ kind: 'title' })).toBe('title');
    expect(editTargetKey(null)).toBe('');
  });

  it('isEditingKr 只对同 id 的 KR 目标为真（保证只有一行展开）', () => {
    const target = { kind: 'kr', id: 'kr_nps' } as const;
    expect(isEditingKr(target, 'kr_nps')).toBe(true);
    expect(isEditingKr(target, 'kr_wau')).toBe(false);
    expect(isEditingKr({ kind: 'title' }, 'kr_nps')).toBe(false);
    expect(isEditingKr(null, 'kr_nps')).toBe(false);
  });
});
