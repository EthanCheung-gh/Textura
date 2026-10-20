import { describe, expect, it } from 'vitest';
import type { PaletteItemCandidate } from './fuzzy';
import {
  buildPaletteResults,
  highlightSegments,
  pushRecentRef,
  rankItems,
  scoreItem,
} from './fuzzy';

const items: PaletteItemCandidate[] = [
  {
    id: 'i1',
    title: '写 onboarding 欢迎邮件',
    kind: 'action',
    tags: ['文案'],
    pathTitles: ['新用户 onboarding SOP', '写 onboarding 欢迎邮件'],
  },
  {
    id: 'i2',
    title: '更新定价页文案',
    kind: 'action',
    tags: ['官网'],
    pathTitles: ['官网改版', '更新定价页文案'],
  },
  {
    id: 'i3',
    title: '需求梳理与竞品盘点',
    kind: 'action',
    tags: ['research'],
    pathTitles: ['官网改版', '需求梳理与竞品盘点'],
  },
];

const orderCandidates: PaletteItemCandidate[] = [
  { id: 'prefix', title: '复盘周报', kind: 'action', tags: [], pathTitles: ['复盘周报'] },
  { id: 'contains', title: '本周复盘会议', kind: 'action', tags: [], pathTitles: ['本周复盘会议'] },
  { id: 'tag', title: '整理资料', kind: 'action', tags: ['复盘'], pathTitles: ['整理资料'] },
  { id: 'path', title: '写总结', kind: 'action', tags: [], pathTitles: ['复盘周期', '写总结'] },
];

const commands = [
  { id: 'new-sop', label: '新建 SOP', keywords: ['流程'] },
  { id: 'new-objective', label: '新建目标', keywords: ['okr'] },
  { id: 'export', label: '导出工作区', keywords: ['json', '备份'] },
];

const areas = [
  { id: 'a1', name: '产品' },
  { id: 'a2', name: '运营' },
];

describe('scoreItem / rankItems', () => {
  it('ranks title prefix above contains, tags and ancestor paths', () => {
    const ranked = rankItems('复盘', orderCandidates);
    expect(ranked.map((entry) => entry.candidate.id)).toEqual(['prefix', 'contains', 'tag', 'path']);
    expect(ranked[0].hit).toMatchObject({ field: 'title' });
    expect(ranked[2].hit).toMatchObject({ field: 'tag' });
    expect(ranked[3].hit).toMatchObject({ field: 'path' });
  });

  it('prefers title matches over tags', () => {
    const ranked = rankItems('文案', items);
    expect(ranked.map((entry) => entry.candidate.id)).toEqual(['i2', 'i1']);
    expect(scoreItem('文案', items[0])).toEqual({ score: 500, field: 'tag' });
    expect(scoreItem('定价', items[1])?.field).toBe('title');
    expect(scoreItem('官网改版', items[1])?.field).toBe('path');
    expect(scoreItem('官网改版', items[2])?.field).toBe('path');
  });

  it('returns nothing when the keyword is absent', () => {
    expect(scoreItem('不存在的关键词', items[0])).toBeNull();
    expect(rankItems('不存在的关键词', items)).toEqual([]);
  });

  it('caps item results at the requested limit', () => {
    expect(rankItems('文', items)).toHaveLength(2);
    expect(rankItems('文', items, 1)).toHaveLength(1);
  });
});

describe('buildPaletteResults', () => {
  it('returns recent entries for an empty query instead of item matches', () => {
    const results = buildPaletteResults('  ', {
      commands,
      items,
      areas,
      recent: [
        { type: 'item', id: 'i2' },
        { type: 'command', id: 'new-sop' },
        { type: 'item', id: 'missing' },
        { type: 'area', id: 'a1' },
      ],
    });
    expect(results.recent.map((row) => row.label)).toEqual(['更新定价页文案', '新建 SOP', '产品']);
    expect(results.recent[0].hint).toBe('条目 · 行动');
    expect(results.items).toEqual([]);
    expect(results.areas).toEqual([]);
    expect(results.commands).toHaveLength(commands.length);
  });

  it('matches commands, items and areas for a real query', () => {
    const results = buildPaletteResults('新建', { commands, items, areas, recent: [] });
    expect(results.commands.map((entry) => entry.id).sort()).toEqual(['new-objective', 'new-sop']);
    expect(results.recent).toEqual([]);

    const areaQuery = buildPaletteResults('运营', { commands, items, areas, recent: [] });
    expect(areaQuery.areas.map((entry) => entry.id)).toEqual(['a2']);
  });

  it('matches command keywords', () => {
    const results = buildPaletteResults('json', { commands, items, areas, recent: [] });
    expect(results.commands.map((entry) => entry.id)).toEqual(['export']);
  });
});

describe('highlightSegments', () => {
  it('splits the first substring hit', () => {
    expect(highlightSegments('更新定价页文案', '定价')).toEqual([
      { text: '更新', match: false },
      { text: '定价', match: true },
      { text: '页文案', match: false },
    ]);
  });

  it('returns a single non-match segment when nothing matches', () => {
    expect(highlightSegments('写周报', '')).toEqual([{ text: '写周报', match: false }]);
    expect(highlightSegments('写周报', '定价')).toEqual([{ text: '写周报', match: false }]);
  });
});

describe('pushRecentRef', () => {
  it('dedupes, prepends and caps the list at six entries', () => {
    const initial = Array.from({ length: 6 }, (_, index) => ({
      type: 'item' as const,
      id: `i${index}`,
    }));
    const next = pushRecentRef({ type: 'item', id: 'i3' }, initial);
    expect(next[0]).toEqual({ type: 'item', id: 'i3' });
    expect(next).toHaveLength(6);
    expect(next.filter((entry) => entry.id === 'i3')).toHaveLength(1);
  });
});
