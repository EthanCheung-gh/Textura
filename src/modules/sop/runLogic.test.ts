import { describe, expect, it } from 'vitest';
import {
  advance,
  elapsedMinutes,
  nextCandidates,
  startStepId,
  summarizeResults,
} from './runLogic';
import type { FlowEdgeLike } from './runLogic';

const edges: FlowEdgeLike[] = [
  { id: 'e1', from: 'start', to: 'collect', label: '' },
  { id: 'e2', from: 'collect', to: 'decision', label: '' },
  { id: 'e3', from: 'decision', to: 'check', label: '是' },
  { id: 'e4', from: 'decision', to: 'remind', label: '否' },
  { id: 'e5', from: 'remind', to: 'collect', label: '补充' },
  { id: 'e6', from: 'check', to: 'end', label: '通过' },
];

describe('nextCandidates', () => {
  it('只返回该步骤的出边，并保留原始顺序', () => {
    expect(nextCandidates('decision', edges).map((edge) => edge.id)).toEqual(['e3', 'e4']);
    expect(nextCandidates('end', edges)).toEqual([]);
  });
});

describe('startStepId', () => {
  it('优先取 start 节点', () => {
    expect(
      startStepId(
        [
          { id: 'collect', nodeType: 'action' },
          { id: 'start', nodeType: 'start' },
        ],
        edges,
      ),
    ).toBe('start');
  });

  it('没有 start 时取入度为 0 的节点', () => {
    expect(
      startStepId(
        [
          { id: 'collect', nodeType: 'action' },
          { id: 'remind', nodeType: 'action' },
        ],
        edges,
      ),
    ).toBe('collect');
  });

  it('空图返回 null', () => {
    expect(startStepId([], [])).toBeNull();
  });
});

describe('advance', () => {
  it('单出边：直接前进到目标', () => {
    expect(advance({ stepId: 'start', edges, result: 'pass' })).toEqual({
      status: 'next',
      stepId: 'collect',
      viaEdgeId: 'e1',
    });
  });

  it('多出边且未选择：返回带 label 的分支选项', () => {
    const outcome = advance({ stepId: 'decision', edges, result: 'pass' });
    expect(outcome).toEqual({
      status: 'branch',
      options: [
        { edgeId: 'e3', to: 'check', label: '是' },
        { edgeId: 'e4', to: 'remind', label: '否' },
      ],
    });
  });

  it('多出边且已选择：按选择前进', () => {
    expect(advance({ stepId: 'decision', edges, result: 'fail', choice: 'e4' })).toEqual({
      status: 'next',
      stepId: 'remind',
      viaEdgeId: 'e4',
    });
  });

  it('无效选择仍回到分支选择', () => {
    const outcome = advance({ stepId: 'decision', edges, result: 'pass', choice: 'nope' });
    expect(outcome.status).toBe('branch');
  });

  it('无出边：流程结束', () => {
    expect(advance({ stepId: 'end', edges, result: 'pass' })).toEqual({ status: 'end' });
  });

  it('跳过同样沿流程前进', () => {
    expect(advance({ stepId: 'collect', edges, result: 'skip' })).toEqual({
      status: 'next',
      stepId: 'decision',
      viaEdgeId: 'e2',
    });
  });

  it('已访问的分支排在后面，但不丢选项', () => {
    const outcome = advance({
      stepId: 'decision',
      edges,
      result: 'fail',
      visited: ['check'],
    });
    expect(outcome.status).toBe('branch');
    if (outcome.status !== 'branch') return;
    expect(outcome.options.map((option) => option.edgeId)).toEqual(['e4', 'e3']);
    expect(outcome.options).toHaveLength(2);
  });
});

describe('summarizeResults', () => {
  it('统计通过 / 未通过 / 跳过', () => {
    expect(summarizeResults(['pass', 'pass', 'fail', 'skip'])).toEqual({
      pass: 2,
      fail: 1,
      skip: 1,
      total: 4,
    });
    expect(summarizeResults([])).toEqual({ pass: 0, fail: 0, skip: 0, total: 0 });
  });
});

describe('elapsedMinutes', () => {
  it('四舍五入到分钟，非法时间返回 0', () => {
    expect(elapsedMinutes('2026-01-01T00:00:00.000Z', '2026-01-01T00:02:20.000Z')).toBe(2);
    expect(elapsedMinutes('bad', '2026-01-01T00:02:20.000Z')).toBe(0);
    expect(elapsedMinutes('2026-01-01T00:05:00.000Z', '2026-01-01T00:00:00.000Z')).toBe(0);
  });
});
