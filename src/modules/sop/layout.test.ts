import { describe, expect, it } from 'vitest';
import {
  SOP_NODE_HEIGHT,
  SOP_NODE_WIDTH,
  canvasPositionsToPatch,
  layoutPositions,
} from './layout';

type Position = { x: number; y: number };

function overlaps(a: Position, b: Position): boolean {
  return (
    a.x < b.x + SOP_NODE_WIDTH &&
    b.x < a.x + SOP_NODE_WIDTH &&
    a.y < b.y + SOP_NODE_HEIGHT &&
    b.y < a.y + SOP_NODE_HEIGHT
  );
}

function assertNoOverlap(positions: Record<string, Position>) {
  const entries = Object.entries(positions);
  for (let i = 0; i < entries.length; i += 1) {
    for (let j = i + 1; j < entries.length; j += 1) {
      expect(overlaps(entries[i][1], entries[j][1]), `${entries[i][0]} 与 ${entries[j][0]} 重叠`).toBe(
        false,
      );
    }
  }
}

describe('layoutPositions', () => {
  it('按层级向下递增 y，同层节点共享 y 且水平不重叠', () => {
    const positions = layoutPositions(
      [{ id: 'root' }, { id: 'a' }, { id: 'b' }, { id: 'end' }],
      [
        { from: 'root', to: 'a' },
        { from: 'root', to: 'b' },
        { from: 'a', to: 'end' },
        { from: 'b', to: 'end' },
      ],
    );

    expect(Object.keys(positions).sort()).toEqual(['a', 'b', 'end', 'root']);
    expect(positions.a.y).toBe(positions.b.y);
    expect(positions.root.y).toBeLessThan(positions.a.y);
    expect(positions.a.y).toBeLessThan(positions.end.y);
    expect(Math.abs(positions.a.x - positions.b.x)).toBeGreaterThanOrEqual(SOP_NODE_WIDTH);
    assertNoOverlap(positions);
  });

  it('长链的 y 单调递增，层间距不小于 ranksep', () => {
    const ids = ['n0', 'n1', 'n2', 'n3'];
    const edges = ids.slice(1).map((id, index) => ({ from: ids[index], to: id }));
    const positions = layoutPositions(
      ids.map((id) => ({ id })),
      edges,
      { nodesep: 60, ranksep: 90 },
    );

    for (let i = 1; i < ids.length; i += 1) {
      const gap = positions[ids[i]].y - positions[ids[i - 1]].y;
      expect(gap).toBeGreaterThanOrEqual(SOP_NODE_HEIGHT + 60);
    }
    assertNoOverlap(positions);
  });

  it('忽略重复边、自环与未知节点，支持 LR 方向', () => {
    const positions = layoutPositions(
      [{ id: 'a' }, { id: 'b' }],
      [
        { from: 'a', to: 'b' },
        { from: 'a', to: 'b' },
        { from: 'a', to: 'a' },
        { from: 'ghost', to: 'b' },
      ],
      { rankdir: 'LR' },
    );

    expect(positions.a.x).toBeLessThan(positions.b.x);
    expect(positions.a.y).toBe(positions.b.y);
    expect(positions.ghost).toBeUndefined();
  });

  it('空画布返回空坐标表', () => {
    expect(layoutPositions([], [])).toEqual({});
  });
});

describe('canvasPositionsToPatch', () => {
  it('取整、去重并只保留发生变化的位置', () => {
    const patches = canvasPositionsToPatch(
      [
        { id: 'a', x: 10.4, y: 20.6 },
        { id: 'a', x: 11.2, y: 21.8 },
        { id: 'b', x: 100, y: 200 },
        { id: 'c', x: 300, y: 400 },
      ],
      {
        b: { x: 100, y: 200 },
        c: { x: 0, y: 0 },
      },
    );

    expect(patches).toEqual([
      { id: 'a', x: 11, y: 22 },
      { id: 'c', x: 300, y: 400 },
    ]);
  });
});
