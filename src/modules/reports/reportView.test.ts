import { describe, expect, it } from 'vitest';
import type { Report, ReportSection } from '../../core/model';
import { templateFor } from './draft';
import {
  appendLine,
  draftFromReport,
  filterReports,
  findReport,
  mergeSectionBodies,
  orderedSections,
  reportsOfKind,
  sortReportsDesc,
  wordCount,
} from './reportView';

function section(overrides: Partial<ReportSection> = {}): ReportSection {
  return {
    key: 'overview',
    title: '本周概览',
    body: '### 本周概览\n- 完成：3 项',
    origin: 'auto',
    updatedAt: '2026-11-01T09:00:00.000Z',
    ...overrides,
  };
}

function makeReport(overrides: Partial<Report> = {}): Report {
  return {
    id: 'r1',
    kind: 'week',
    period: '2026-W44',
    title: '2026 年第 44 周报',
    author: '',
    status: 'draft',
    templateId: 'weekly-external',
    sections: [section()],
    generatedAt: '2026-11-01T09:00:00.000Z',
    finalizedAt: null,
    createdAt: '2026-11-01T09:00:00.000Z',
    updatedAt: '2026-11-01T09:00:00.000Z',
    ...overrides,
  };
}

describe('reportsOfKind', () => {
  it('只留同粒度的报告，缺省字段当空数组', () => {
    const week = makeReport();
    const month = makeReport({ id: 'r2', kind: 'month', period: '2026-11' });
    expect(reportsOfKind([week, month], 'week')).toEqual([week]);
    expect(reportsOfKind([week, month], 'quarter')).toEqual([]);
    expect(reportsOfKind(undefined, 'week')).toEqual([]);
    expect(reportsOfKind(null, 'week')).toEqual([]);
  });
});

describe('findReport', () => {
  it('按 (kind, period) 唯一命中，不同粒度不串期', () => {
    const week = makeReport();
    const month = makeReport({ id: 'r2', kind: 'month', period: '2026-11' });
    expect(findReport([week, month], 'week', '2026-W44')).toBe(week);
    // 同 period 字符串但粒度不同 → 不匹配
    expect(findReport([week], 'month', '2026-W44')).toBeNull();
    expect(findReport([week], 'week', '2026-W45')).toBeNull();
    expect(findReport(undefined, 'week', '2026-W44')).toBeNull();
  });
});

describe('sortReportsDesc', () => {
  it('期次倒序，同键按 updatedAt 倒序，且不改入参', () => {
    const older = makeReport({ id: 'a', period: '2026-W43', updatedAt: '2026-10-30T00:00:00.000Z' });
    const newer = makeReport({ id: 'b', period: '2026-W45', updatedAt: '2026-11-10T00:00:00.000Z' });
    const sameKeyOld = makeReport({ id: 'c', period: '2026-W44', updatedAt: '2026-11-01T00:00:00.000Z' });
    const sameKeyNew = makeReport({ id: 'd', period: '2026-W44', updatedAt: '2026-11-05T00:00:00.000Z' });
    const input = [older, sameKeyOld, newer, sameKeyNew];

    expect(sortReportsDesc(input).map((report) => report.id)).toEqual(['b', 'd', 'c', 'a']);
    expect(input.map((report) => report.id)).toEqual(['a', 'c', 'b', 'd']);
  });

  it('期次键定宽，字典序即时间序（W09 在 W10 之前）', () => {
    const w10 = makeReport({ id: 'w10', period: '2026-W10' });
    const w09 = makeReport({ id: 'w09', period: '2026-W09' });
    expect(sortReportsDesc([w09, w10]).map((report) => report.id)).toEqual(['w10', 'w09']);
  });
});

describe('filterReports', () => {
  const progress = makeReport({
    id: 'p',
    period: '2026-W44',
    title: '对外周报（含风险）',
    sections: [section({ body: '### 本周进展\n- 完成登录改版' })],
  });
  const plain = makeReport({ id: 'q', period: '2026-W45', title: '2026 年第 45 周报' });

  it('匹配期次 / 标题 / 正文', () => {
    expect(filterReports([progress, plain], 'W45').map((report) => report.id)).toEqual(['q']);
    expect(filterReports([progress, plain], '风险').map((report) => report.id)).toEqual(['p']);
    expect(filterReports([progress, plain], '登录改版').map((report) => report.id)).toEqual(['p']);
  });

  it('大小写不敏感，空查询原样返回（同一引用）', () => {
    const lower = makeReport({ id: 'l', period: '2026-w44' });
    expect(filterReports([lower], 'W44').map((report) => report.id)).toEqual(['l']);
    const list = [progress, plain];
    expect(filterReports(list, '   ')).toBe(list);
  });

  it('没有命中时返回空数组', () => {
    expect(filterReports([progress, plain], '不存在的词')).toEqual([]);
  });
});

describe('orderedSections', () => {
  it('按模板顺序取节，缺失的用模板标题兜底成空节', () => {
    const template = templateFor('week');
    const report = makeReport({
      sections: [
        section({ key: 'risks', title: '风险与阻塞', body: '### 风险与阻塞\n- 无' }),
        section({ key: 'overview', title: '本周概览（手改标题）', body: '### 概览\n- 1 项' }),
      ],
    });
    const ordered = orderedSections(template, report);

    expect(ordered.map((entry) => entry.key)).toEqual(template.sections.map((entry) => entry.key));
    // 已存在的节保留自身标题与正文
    expect(ordered[0]).toMatchObject({ key: 'overview', title: '本周概览（手改标题）', body: '### 概览\n- 1 项' });
    // 缺失的节用模板标题兜底，正文为空、origin 回落 auto
    const metrics = ordered.find((entry) => entry.key === 'metrics');
    expect(metrics).toMatchObject({ title: '量化指标', body: '', origin: 'auto' });
    expect(metrics?.updatedAt).toBe(report.updatedAt);
  });

  it('报告里多出来的节不参与渲染（模板外的 key）', () => {
    const template = templateFor('week');
    const report = makeReport({ sections: [section({ key: 'custom' })] });
    expect(orderedSections(template, report).some((entry) => entry.key === 'custom')).toBe(false);
  });
});

describe('wordCount', () => {
  it('只数非空白字符', () => {
    const report = makeReport({
      sections: [
        section({ body: '### 本周概览\n- 完成：3 项' }), // 去空白后 13 个字符
        section({ key: 'metrics', body: '' }),
      ],
    });
    expect(wordCount(report)).toBe(13);
    expect(wordCount({ sections: [] })).toBe(0);
  });
});

describe('draftFromReport', () => {
  it('只取可编辑字段，章节数组与报告同一引用', () => {
    const report = makeReport({ author: '张三' });
    const draft = draftFromReport(report);
    expect(draft).toEqual({
      id: 'r1',
      title: '2026 年第 44 周报',
      author: '张三',
      sections: report.sections,
    });
    expect(draft.sections).toBe(report.sections);
  });
});

describe('appendLine', () => {
  it('空正文直接放行，非空追加到末尾且不留多余空行', () => {
    expect(appendLine('', '- 新条目')).toBe('- 新条目');
    expect(appendLine('  \n', '- 新条目')).toBe('- 新条目');
    expect(appendLine('### 本周进展\n- 旧条目', '- 新条目')).toBe('### 本周进展\n- 旧条目\n- 新条目');
  });
});

describe('mergeSectionBodies', () => {
  const overview = section({ key: 'overview', body: 'old' });
  const risks = section({ key: 'risks', title: '风险与阻塞', body: '### 风险与阻塞\n- 无' });

  it('只替换目标节，返回整份新数组且其余节保持同一引用', () => {
    const sections = [overview, risks];
    const next = mergeSectionBodies(sections, 'risks', '### 风险与阻塞\n- 超期 2 天', {
      origin: 'manual',
      updatedAt: '2026-11-02T10:00:00.000Z',
    });

    expect(next).not.toBe(sections);
    expect(next).toHaveLength(2);
    expect(next[0]).toBe(overview);
    expect(next[1]).toMatchObject({
      key: 'risks',
      title: '风险与阻塞',
      body: '### 风险与阻塞\n- 超期 2 天',
      origin: 'manual',
      updatedAt: '2026-11-02T10:00:00.000Z',
    });
    // 入参不被就地修改
    expect(overview.body).toBe('old');
    expect(risks.body).toBe('### 风险与阻塞\n- 无');
  });

  it('不传 origin / updatedAt 时保留原值', () => {
    const next = mergeSectionBodies([overview], 'overview', 'new body');
    expect(next[0]).toMatchObject({
      body: 'new body',
      origin: 'auto',
      updatedAt: overview.updatedAt,
    });
  });

  it('目标 key 不存在时追加新节，绝不丢输入', () => {
    const next = mergeSectionBodies([overview], 'okr', '### 目标\n- 完成度 40%', {
      origin: 'manual',
      updatedAt: '2026-11-02T10:00:00.000Z',
      title: '目标与关键结果',
    });
    expect(next).toHaveLength(2);
    expect(next[1]).toMatchObject({
      key: 'okr',
      title: '目标与关键结果',
      body: '### 目标\n- 完成度 40%',
      origin: 'manual',
    });
  });

  it('追加时缺省标题用 key 兜底', () => {
    const next = mergeSectionBodies([], 'extra', 'body');
    expect(next[0]).toMatchObject({ key: 'extra', title: 'extra', origin: 'auto' });
  });
});
