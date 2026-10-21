import { describe, expect, it } from 'vitest';
import type { Item } from '../../core/model';
import { buildCanvasNodes } from './perf';

const areaColors = { area_a: '#C0663A' };

function makeStep(index: number, patch: Partial<Item> = {}): Item {
  const base: Item = {
    id: `step_${index}`,
    kind: 'step',
    title: `步骤 ${index}`,
    notes: '',
    parentId: 'sop_x',
    order: index,
    status: 'next',
    tags: [],
    areaId: 'area_a',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    completedAt: null,
    sop: {
      nodeType: index === 0 ? 'start' : 'action',
      canvas: { x: index * 10, y: index * 5 },
      checklist:
        index === 2 ? [{ id: 'chk', text: '检查项', done: false }] : [],
    },
  };
  return { ...base, ...patch };
}

function build(steps: Item[], selectedId: string | null, previous?: ReturnType<typeof buildCanvasNodes>) {
  return buildCanvasNodes({
    steps,
    areaColors,
    positions: {},
    selectedId,
    run: null,
    previous,
  });
}

describe('buildCanvasNodes 结构稳定性', () => {
  it('选中态变化时，未选中节点保持同一对象引用', () => {
    const steps = [makeStep(0), makeStep(1), makeStep(2)];
    const first = build(steps, null);
    const second = build(steps, 'step_1', first);

    expect(second).toHaveLength(3);
    expect(second[0]).toBe(first[0]);
    expect(second[2]).toBe(first[2]);
    expect(second[1]).not.toBe(first[1]);
    expect(second[1].selected).toBe(true);
    // 只改选中态时复用 data，避免节点内部 memo 失效
    expect(second[1].data).toBe(first[1].data);
  });

  it('运行高亮变化只重建状态变化的节点', () => {
    const steps = [makeStep(0), makeStep(1), makeStep(2)];
    const first = build(steps, null);
    const second = buildCanvasNodes({
      steps,
      areaColors,
      positions: {},
      selectedId: null,
      run: { currentId: 'step_1', visited: ['step_0', 'step_1'], failed: [] },
      previous: first,
    });

    expect(second[0].data.state).toBe('visited');
    expect(second[1].data.state).toBe('current');
    expect(second[2]).toBe(first[2]);
  });

  it('只移动一个节点时其它节点引用不变', () => {
    const steps = [makeStep(0), makeStep(1), makeStep(2)];
    const first = build(steps, null);
    const second = buildCanvasNodes({
      steps,
      areaColors,
      positions: { step_0: { x: 0, y: 0 }, step_1: { x: 10, y: 5 }, step_2: { x: 999, y: 999 } },
      selectedId: null,
      run: null,
      previous: first,
    });

    expect(second[0]).toBe(first[0]);
    expect(second[1]).toBe(first[1]);
    expect(second[2]).not.toBe(first[2]);
    expect(second[2].position).toEqual({ x: 999, y: 999 });
  });

  it('300 节点构建 < 30ms，且切换选中只改变 1 个对象', () => {
    const steps = Array.from({ length: 300 }, (_, index) => makeStep(index));
    const started = performance.now();
    const first = build(steps, null);
    const elapsed = performance.now() - started;

    expect(first).toHaveLength(300);
    expect(elapsed).toBeLessThan(30);

    const second = build(steps, 'step_150', first);
    let changed = 0;
    for (let index = 0; index < first.length; index += 1) {
      if (second[index] !== first[index]) changed += 1;
    }
    expect(changed).toBe(1);
  });
});
