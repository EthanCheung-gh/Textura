import { describe, expect, it } from 'vitest';
import { canvasPatchesToUpdateItems, positionsToPatch } from './positions';
import type { CanvasPatchUpdate } from './positions';

describe('positionsToPatch', () => {
  it('把 React Flow 节点位置整理成取整后的 canvas 补丁', () => {
    expect(
      positionsToPatch([
        { id: 'step_a', position: { x: 40.4, y: 159.6 } },
        { id: 'step_b', position: { x: 280, y: 160 } },
      ]),
    ).toEqual([
      { id: 'step_a', canvas: { x: 40, y: 160 } },
      { id: 'step_b', canvas: { x: 280, y: 160 } },
    ]);
  });

  it('与现有坐标一致的节点不产生补丁（避免无意义的 history/自动保存）', () => {
    const current = {
      step_a: { x: 40, y: 160 },
      step_b: { x: 280, y: 160 },
    };
    expect(
      positionsToPatch(
        [
          { id: 'step_a', position: { x: 40, y: 160 } },
          { id: 'step_b', position: { x: 300, y: 160 } },
        ],
        current,
      ),
    ).toEqual([{ id: 'step_b', canvas: { x: 300, y: 160 } }]);
  });

  it('空输入返回空数组', () => {
    expect(positionsToPatch([])).toEqual([]);
  });
});

describe('canvasPatchesToUpdateItems', () => {
  it('把 N 个节点位置整理成 N 条 updateItems 载荷，调用方只触发一次批量写', () => {
    const patches = positionsToPatch(
      [
        { id: 'step_start', position: { x: 0, y: 0 } },
        { id: 'step_a', position: { x: 0, y: 120 } },
        { id: 'step_b', position: { x: 0, y: 240 } },
      ],
      undefined,
    );
    const payload = canvasPatchesToUpdateItems(patches);

    expect(payload).toHaveLength(3);
    expect(payload[2]).toEqual({
      id: 'step_b',
      patch: { sop: { canvas: { x: 0, y: 240 } } },
    });

    // 模拟调用方：整批只调用一次 updateItems（=> 单条历史 + 单次防抖保存）
    const calls: CanvasPatchUpdate[][] = [];
    const updateItems = (batch: CanvasPatchUpdate[]) => calls.push(batch);
    updateItems(canvasPatchesToUpdateItems(patches));

    expect(calls).toHaveLength(1);
    expect(calls[0]).toHaveLength(3);
  });

  it('空补丁不产生任何写入', () => {
    const updateItems = (batch: CanvasPatchUpdate[]) => batch;
    expect(updateItems(canvasPatchesToUpdateItems([]))).toEqual([]);
  });
});
