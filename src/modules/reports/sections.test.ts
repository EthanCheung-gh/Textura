/**
 * 自定义周报章节的纯逻辑回归。
 *
 * 断言口径按模块契约来写（见 `sections.ts` 文件头）：
 * 存储顺序即展示顺序、模板缺节按相对位置补、模板外的节保留、模板节标题不可改。
 */
import { describe, expect, it } from 'vitest';
import { WORKSPACE_VERSION } from '../../core/model';
import type { ReportSection } from '../../core/model';
import { MAX_REPORT_SECTIONS, migrateWorkspace } from '../../core/repo';
import { templateFor } from './draft';
import {
  CUSTOM_SECTION_PREFIX,
  MAX_SECTION_TITLE_CHARS,
  addSection,
  canAddSection,
  defaultCustomTitle,
  displaySections,
  ensureSection,
  isCustomSectionKey,
  moveSection,
  nextCustomKey,
  removeSection,
  renameSection,
} from './sections';

const NOW = '2026-11-02T10:00:00.000Z';
const LATER = '2026-11-03T10:00:00.000Z';

function section(key: string, overrides: Partial<ReportSection> = {}): ReportSection {
  return {
    key,
    title: key,
    body: `### ${key}`,
    origin: 'auto',
    updatedAt: '2026-11-01T09:00:00.000Z',
    ...overrides,
  };
}

const keysOf = (sections: readonly ReportSection[]) => sections.map((entry) => entry.key);

/* ------------------------------------------------------------------ */
/* key 空间                                                            */
/* ------------------------------------------------------------------ */

describe('isCustomSectionKey / defaultCustomTitle', () => {
  it('只按前缀判定，模板 key 与大小写变体都不算自建节', () => {
    expect(isCustomSectionKey('custom-1')).toBe(true);
    expect(isCustomSectionKey('custom-12')).toBe(true);
    expect(isCustomSectionKey(`${CUSTOM_SECTION_PREFIX}`)).toBe(true);
    expect(isCustomSectionKey('overview')).toBe(false);
    expect(isCustomSectionKey('custom')).toBe(false);
    expect(isCustomSectionKey('Custom-1')).toBe(false);
    expect(isCustomSectionKey('')).toBe(false);
  });

  it('默认标题带序号，且与 key 里的 n 一致', () => {
    expect(defaultCustomTitle(1)).toBe('自定义章节 1');
    expect(defaultCustomTitle(12)).toBe('自定义章节 12');
  });
});

describe('nextCustomKey', () => {
  const cases: { name: string; input: string[]; expected: string }[] = [
    { name: '空报告 → custom-1', input: [], expected: 'custom-1' },
    { name: '只有模板节 → custom-1', input: ['overview', 'progress'], expected: 'custom-1' },
    { name: 'custom-1 已占用 → custom-2', input: ['overview', 'custom-1'], expected: 'custom-2' },
    { name: '中间有空洞 → 取最小空位', input: ['custom-1', 'custom-3', 'custom-4'], expected: 'custom-2' },
    { name: '连续占用 → 顺延', input: ['custom-1', 'custom-2', 'custom-3'], expected: 'custom-4' },
    { name: '形似前缀但不是序号 → custom-1', input: ['custom-x', 'custom-'], expected: 'custom-1' },
  ];

  it.each(cases)('$name', ({ input, expected }) => {
    expect(nextCustomKey(input.map((key) => section(key)))).toBe(expected);
  });

  it('只由入参推导：同一输入两次调用结果相同，且不改入参', () => {
    const sections = [section('custom-2')];
    expect(nextCustomKey(sections)).toBe('custom-1');
    expect(nextCustomKey(sections)).toBe('custom-1');
    expect(keysOf(sections)).toEqual(['custom-2']);
  });
});

/* ------------------------------------------------------------------ */
/* 增 / 改 / 删                                                        */
/* ------------------------------------------------------------------ */

describe('addSection', () => {
  it('追加到末尾，默认标题按 key 序号生成', () => {
    const input = [section('overview')];
    const next = addSection(input, NOW);

    expect(next).not.toBe(input);
    expect(keysOf(input)).toEqual(['overview']);
    expect(next).toHaveLength(2);
    expect(next[1]).toEqual({
      key: 'custom-1',
      title: '自定义章节 1',
      body: '',
      origin: 'manual',
      updatedAt: NOW,
    });
    expect(next[0]).toBe(input[0]);
  });

  it('显式标题去空白后使用；标题全空白回落默认标题', () => {
    const withTitle = addSection([], NOW, '  复盘与改进  ');
    expect(withTitle[0]).toMatchObject({ key: 'custom-1', title: '复盘与改进' });

    const blank = addSection([], NOW, '   ');
    expect(blank[0]).toMatchObject({ key: 'custom-1', title: defaultCustomTitle(1) });
  });

  it('已有自建节时序号顺延（默认标题跟着走）', () => {
    const next = addSection([section('overview'), section('custom-1')], LATER);
    expect(next[2]).toMatchObject({ key: 'custom-2', title: '自定义章节 2', updatedAt: LATER });
  });
});

/* ------------------------------------------------------------------ */
/* canAddSection：UI 必须停在「存储上限」而不是眼睛看到的位置          */
/* ------------------------------------------------------------------ */

describe('canAddSection', () => {
  /** 造 n 节存好的报告：key 用自建前缀，条数才是这里唯一关心的量。 */
  function stored(count: number): ReportSection[] {
    return Array.from({ length: count }, (_, index) =>
      section(`${CUSTOM_SECTION_PREFIX}${index + 1}`, { origin: 'manual' }),
    );
  }

  /** 最小工作区外壳：只放一份报告，用来验证加载期裁剪的门槛。 */
  function workspaceWith(sections: ReportSection[]) {
    return {
      version: WORKSPACE_VERSION,
      items: [],
      edges: [],
      areas: [],
      runs: [],
      reports: [{ id: 'r1', kind: 'week', period: '2026-W44', sections }],
      updatedAt: NOW,
    };
  }

  /** 把章节喂给加载期，取回真正落盘的那份数组（报告缺失时退回空数组，别让断言炸在解构上）。 */
  function loadedSections(sections: ReportSection[]): ReportSection[] {
    // `Workspace.reports` 类型上可选（旧文件可能没有这个键），归一化后一定有值，故 `?? []`。
    return migrateWorkspace(workspaceWith(sections)).reports?.[0]?.sections ?? [];
  }

  it('上限与存储层同源：导出的常量就是加载期裁剪的门槛', () => {
    // 多一节喂给加载期，能留下来几节，就说明存储层的硬上限是几——与常量必须一致。
    expect(loadedSections(stored(MAX_REPORT_SECTIONS + 1))).toHaveLength(MAX_REPORT_SECTIONS);
  });

  it('39 节还能加：加完正好 40 节，随即封顶', () => {
    const before = stored(MAX_REPORT_SECTIONS - 1);
    expect(canAddSection(before)).toBe(true);

    const after = addSection(before, NOW);
    expect(after).toHaveLength(MAX_REPORT_SECTIONS);
    expect(canAddSection(after)).toBe(false);
  });

  it('40 节封顶：再落盘的一节会被加载期裁掉，所以这里必须返回 false', () => {
    const full = stored(MAX_REPORT_SECTIONS);
    expect(canAddSection(full)).toBe(false);

    // 反证：`addSection` 本身不拦（纯编辑），越限的那一节根本活不过下一次加载。
    const overflowed = addSection(full, NOW);
    expect(overflowed).toHaveLength(MAX_REPORT_SECTIONS + 1);
    expect(loadedSections(overflowed)).toHaveLength(MAX_REPORT_SECTIONS);
  });

  it('41 节这类越限旧数据一律判定为不能再加', () => {
    expect(canAddSection(stored(MAX_REPORT_SECTIONS + 1))).toBe(false);
  });

  it('补出来的模板空节不计数：展示列表更长也照样能加', () => {
    const half = stored(MAX_REPORT_SECTIONS - 1); // 模板节一节都没存，展示时会全补齐
    const shown = displaySections(templateFor('week'), { sections: half, updatedAt: NOW });
    expect(shown.length).toBeGreaterThan(MAX_REPORT_SECTIONS);
    expect(canAddSection(half)).toBe(true);
  });

  it('空报告的边界：0 节可以加，且不改入参', () => {
    const empty: ReportSection[] = [];
    expect(canAddSection(empty)).toBe(true);
    expect(empty).toEqual([]);
  });
});

describe('renameSection', () => {
  const custom = section('custom-1', { title: '自定义章节 1', origin: 'manual' });
  const overview = section('overview');

  it('自建节：标题去空白后生效，只改目标节，时间戳取入参', () => {
    const input = [overview, custom];
    const next = renameSection(input, 'custom-1', '  复盘与改进  ', NOW);

    expect(next).not.toBe(input);
    expect(next[1]).toEqual({
      key: 'custom-1',
      title: '复盘与改进',
      body: custom.body,
      origin: 'manual',
      updatedAt: NOW,
    });
    expect(next[0]).toBe(overview);
    expect(custom.title).toBe('自定义章节 1');
  });

  it('模板节不可改名（同一引用返回）', () => {
    const input = [overview];
    expect(renameSection(input, 'overview', '新名字', NOW)).toBe(input);
    // 超长标题也一样：模板标题是口径来源，不是「可以顺手裁一下」的对象。
    expect(renameSection(input, 'overview', '长'.repeat(MAX_SECTION_TITLE_CHARS + 1), NOW)).toBe(
      input,
    );
  });

  it('空标题 / 全空白 / 未知 key 一律原样返回', () => {
    const input = [overview, custom];
    expect(renameSection(input, 'custom-1', '', NOW)).toBe(input);
    expect(renameSection(input, 'custom-1', '   ', NOW)).toBe(input);
    expect(renameSection(input, 'custom-9', '新名字', NOW)).toBe(input);
    expect(renameSection(input, 'nope', '新名字', NOW)).toBe(input);
  });

  it('规范化后与存储标题相同 → 同一引用空操作（纯空白编辑不算改名）', () => {
    const input = [overview, custom];
    const before = { ...custom };

    // 存储里就是「自定义章节 1」：只多打了空白 / 换行 / 制表符，标题其实没变。
    for (const sameTitle of [
      '自定义章节 1 ',
      ' 自定义章节 1',
      '  自定义章节   1  ',
      '自定义章节\n1',
      '自定义章节\t1\r\n',
    ]) {
      expect(renameSection(input, 'custom-1', sameTitle, LATER)).toBe(input);
    }

    // 空操作必须连时间戳一起保住：否则页面层照样会写盘、留一条空快照并弹「已改名」。
    expect(input[1]).toEqual(before);
    expect(input[1].updatedAt).toBe(custom.updatedAt);
  });
});

/* ------------------------------------------------------------------ */
/* 标题规范化的数据层边界：压空白 + 按 MAX_SECTION_TITLE_CHARS 裁剪    */
/* ------------------------------------------------------------------ */

describe('标题规范化（renameSection / addSection 同一条规则）', () => {
  const custom = section('custom-1', { title: '自定义章节 1', origin: 'manual' });
  const renamed = (title: string) => renameSection([custom], 'custom-1', title, NOW)[0].title;

  it('刚好到上限：原样保留，不加省略号', () => {
    const exact = '长'.repeat(MAX_SECTION_TITLE_CHARS);
    expect(renamed(exact)).toBe(exact);
    expect(renamed(exact)).toHaveLength(MAX_SECTION_TITLE_CHARS);
  });

  it('超过上限：裁到上限长度并以省略号收尾，内容不越界', () => {
    const tooLong = '长'.repeat(MAX_SECTION_TITLE_CHARS + 1);
    const title = renamed(tooLong);

    expect(title).toHaveLength(MAX_SECTION_TITLE_CHARS);
    expect(title.endsWith('…')).toBe(true);
    expect(title).toBe(`${'长'.repeat(MAX_SECTION_TITLE_CHARS - 1)}…`);
    // 裁剪只动标题：正文 / origin / 时间戳仍按原样写回。
    const next = renameSection([custom], 'custom-1', tooLong, NOW);
    expect(next[0]).toMatchObject({
      key: 'custom-1',
      body: custom.body,
      origin: 'manual',
      updatedAt: NOW,
    });
  });

  it('换行 / 制表符 / 连续空格一律压成一个空格', () => {
    const title = renamed('  复盘\n\t与     改进 \r\n 收尾 ');
    expect(title).toBe('复盘 与 改进 收尾');
    // 标题要占 Markdown 标题行的一整行，任何换行 / 制表符都不能漏出去。
    expect(title).not.toMatch(/[\n\r\t]/);
  });

  it('先压空白再算长度：上限数的是规范化后的标题，不是粘贴原文', () => {
    // 原文 171 个码元，但规范化后只有 6 个字：不该被裁剪。
    expect(renamed(`复盘${' '.repeat(160)}与改进`)).toBe('复盘 与改进');
    // 正常字之间只夹空格时，裁掉的是字（保留省略号），总长正好等于上限。
    const padded = `${'长'.repeat(MAX_SECTION_TITLE_CHARS)}${'   '}尾`;
    expect(renamed(padded)).toBe(`${'长'.repeat(MAX_SECTION_TITLE_CHARS - 1)}…`);
  });

  it('全空白（含换行 / 制表符）仍是同一引用空操作', () => {
    const input = [custom];
    expect(renameSection(input, 'custom-1', ' \n\t\r\n ', NOW)).toBe(input);
  });

  it('addSection 的显式标题走同一条规则：压空白 + 裁剪', () => {
    const messy = addSection([], NOW, '  复盘\n\t与     改进  ');
    expect(messy[0].title).toBe('复盘 与 改进');

    const long = addSection([], NOW, '长'.repeat(MAX_SECTION_TITLE_CHARS + 30));
    expect(long[0].title).toHaveLength(MAX_SECTION_TITLE_CHARS);
    expect(long[0].title).toBe(`${'长'.repeat(MAX_SECTION_TITLE_CHARS - 1)}…`);
  });

  it('正常中文标题逐字节不变（既有数据无感）', () => {
    expect(renamed('复盘与改进')).toBe('复盘与改进');
    expect(renamed('Weekly Review')).toBe('Weekly Review');
    expect(addSection([], NOW, '复盘与改进')[0].title).toBe('复盘与改进');
    expect(addSection([], NOW, 'Weekly Review')[0].title).toBe('Weekly Review');
  });
});

describe('removeSection', () => {
  it('自建节可删，其余节保持同一引用', () => {
    const overview = section('overview');
    const custom = section('custom-1');
    const next = removeSection([overview, custom, section('custom-2')], 'custom-1');

    expect(keysOf(next)).toEqual(['overview', 'custom-2']);
    expect(next[0]).toBe(overview);
  });

  it('模板节不可删（删了也会被 displaySections 补回来）', () => {
    const input = [section('overview'), section('custom-1')];
    expect(removeSection(input, 'overview')).toBe(input);
  });

  it('未知 key 原样返回', () => {
    const input = [section('custom-1')];
    expect(removeSection(input, 'custom-9')).toBe(input);
  });
});

describe('moveSection', () => {
  const input = () => [section('a'), section('b'), section('c')];

  it('上移 / 下移交换位置，返回新数组且不改入参', () => {
    const sections = input();
    expect(keysOf(moveSection(sections, 'b', -1))).toEqual(['b', 'a', 'c']);
    expect(keysOf(moveSection(sections, 'b', 1))).toEqual(['a', 'c', 'b']);
    expect(keysOf(sections)).toEqual(['a', 'b', 'c']);
  });

  it('模板节同样可移动（展示顺序即存储顺序）', () => {
    const sections = [section('overview'), section('risks')];
    expect(keysOf(moveSection(sections, 'risks', -1))).toEqual(['risks', 'overview']);
  });

  it('两端与未知 key 都是空操作，但仍返回新数组', () => {
    const sections = input();
    for (const noop of [
      moveSection(sections, 'a', -1),
      moveSection(sections, 'c', 1),
      moveSection(sections, 'nope', 1),
    ]) {
      expect(noop).not.toBe(sections);
      expect(keysOf(noop)).toEqual(['a', 'b', 'c']);
    }
    const empty: ReportSection[] = [];
    expect(moveSection(empty, 'a', -1)).toEqual([]);
    expect(moveSection(empty, 'a', -1)).not.toBe(empty);
  });
});

/* ------------------------------------------------------------------ */
/* displaySections：顺序、去重、补空节                                 */
/* ------------------------------------------------------------------ */

describe('displaySections', () => {
  const template = templateFor('week'); // overview / progress / metrics / risks / next / support
  const templateKeys = template.sections.map((entry) => entry.key);

  it('存储顺序即展示顺序：与模板顺序不同也照样照办', () => {
    const report = { sections: [section('risks'), section('overview')], updatedAt: NOW };
    const shown = displaySections(template, report);
    expect(keysOf(shown)).toEqual(['progress', 'metrics', 'risks', 'next', 'support', 'overview']);
  });

  it('模板全缺时按模板顺序补齐空节，时间戳取报告自身', () => {
    const shown = displaySections(template, { sections: [], updatedAt: NOW });
    expect(keysOf(shown)).toEqual(templateKeys);
    for (const entry of shown) {
      expect(entry).toEqual({
        key: entry.key,
        title: template.sections.find((tpl) => tpl.key === entry.key)?.title,
        body: '',
        origin: 'auto',
        updatedAt: NOW,
      });
    }
  });

  it('重复 key 取第一处', () => {
    const first = section('overview', { body: '第一处' });
    const shown = displaySections(template, {
      sections: [first, section('overview', { body: '第二处' })],
      updatedAt: NOW,
    });
    expect(shown.filter((entry) => entry.key === 'overview')).toHaveLength(1);
    expect(shown[0]).toBe(first);
  });

  it('缺失节插到头部（无前驱模板节时放到最近的后继之前）', () => {
    const shown = displaySections(template, {
      sections: [section('progress'), section('metrics'), section('risks'), section('next'), section('support')],
      updatedAt: NOW,
    });
    expect(keysOf(shown)).toEqual(templateKeys);
  });

  it('缺失节插到中间（夹在前后两个模板节之间）', () => {
    const shown = displaySections(template, {
      sections: [section('overview'), section('risks'), section('next'), section('support')],
      updatedAt: NOW,
    });
    expect(keysOf(shown)).toEqual(templateKeys);
  });

  it('缺失节追加到尾部（只有前驱模板节可用）', () => {
    const shown = displaySections(template, {
      sections: [section('overview'), section('progress'), section('metrics'), section('risks'), section('next')],
      updatedAt: NOW,
    });
    expect(keysOf(shown)).toEqual(templateKeys);
  });

  it('自建节与补齐的空节交错时，自建节留在原槽位', () => {
    const custom = section('custom-1', { title: '自定义章节 1', origin: 'manual' });
    const shown = displaySections(template, {
      sections: [section('risks'), custom, section('overview')],
      updatedAt: NOW,
    });
    expect(keysOf(shown)).toEqual([
      'progress',
      'metrics',
      'risks',
      'next',
      'support',
      'custom-1',
      'overview',
    ]);
    expect(shown[5]).toBe(custom);
  });

  it('不改入参：报告章节数组与内部对象都保持原样', () => {
    const stored = [section('risks'), section('custom-1'), section('risks', { body: '重复项' })];
    const snapshot = stored.map((entry) => ({ ...entry }));
    const report = { sections: stored, updatedAt: NOW };

    displaySections(template, report);

    expect(keysOf(stored)).toEqual(['risks', 'custom-1', 'risks']);
    expect(stored.map((entry) => ({ ...entry }))).toEqual(snapshot);
  });

  it('模板为空时只按存储顺序去重返回', () => {
    const stored = [section('overview'), section('custom-1'), section('overview')];
    expect(keysOf(displaySections({ id: 'x', kind: 'week', sections: [] }, { sections: stored, updatedAt: NOW })))
      .toEqual(['overview', 'custom-1']);
  });
});

/* ------------------------------------------------------------------ */
/* ensureSection：补出来的模板空节要先落位再写正文                     */
/* ------------------------------------------------------------------ */

describe('ensureSection', () => {
  const template = templateFor('week'); // overview / progress / metrics / risks / next / support
  const templateKeys = template.sections.map((entry) => entry.key);
  const shownKeys = (stored: readonly ReportSection[]) =>
    keysOf(displaySections(template, { sections: stored, updatedAt: NOW }));

  it('补在头部：插到存储首节之前，展示顺序仍是模板顺序', () => {
    const input = [section('progress'), section('metrics'), section('risks'), section('next'), section('support')];
    const next = ensureSection(input, template, 'overview', NOW);

    expect(next).not.toBe(input);
    expect(keysOf(next)).toEqual(['overview', 'progress', 'metrics', 'risks', 'next', 'support']);
    expect(next[0]).toEqual({
      key: 'overview',
      title: '本周概览',
      body: '',
      origin: 'manual',
      updatedAt: NOW,
    });
  });

  it('补在中间：插到最近的后继存储节之前，而不是紧跟模板前驱', () => {
    // progress 的模板前驱 overview 存了，但它在展示里排在 risks 前面，所以插在 risks 之前。
    const input = [section('overview'), section('risks'), section('next'), section('support')];
    const next = ensureSection(input, template, 'progress', NOW);

    expect(keysOf(next)).toEqual(['overview', 'progress', 'risks', 'next', 'support']);
    expect(next[1]).toMatchObject({ key: 'progress', title: '本周进展', body: '' });
  });

  it('补在中间：同样跳过后继里其它尚未落位的占位节', () => {
    // 只存了 overview + support：metrics 在展示里夹在 risks 之前，占位节都不能当锚点。
    const input = [section('overview'), section('support')];
    const next = ensureSection(input, template, 'metrics', NOW);
    expect(keysOf(next)).toEqual(['overview', 'metrics', 'support']);
  });

  it('补在尾部：没有任何后继存储节时追加到末尾', () => {
    const input = [
      section('overview'),
      section('progress'),
      section('metrics'),
      section('risks'),
      section('next'),
    ];
    const next = ensureSection(input, template, 'support', NOW);
    expect(keysOf(next)).toEqual(templateKeys);
    expect(next[5]).toMatchObject({ key: 'support', title: '需要的支持' });
  });

  it('已存在的 key 返回同一引用（调用方的早退判等继续有效）', () => {
    const input = [section('overview'), section('progress')];
    expect(ensureSection(input, template, 'overview', NOW)).toBe(input);
  });

  it('非模板 key（自建节 / 历史遗留）返回同一引用，绝不造节', () => {
    const input = [section('overview')];
    expect(ensureSection(input, template, 'custom-1', NOW)).toBe(input);
    expect(ensureSection(input, template, 'retro', NOW)).toBe(input);
    expect(ensureSection([], template, 'custom-1', NOW)).toEqual([]);
  });

  it('幂等：落位之后再调一次是同一引用', () => {
    const once = ensureSection([section('risks')], template, 'overview', NOW);
    expect(ensureSection(once, template, 'overview', NOW)).toBe(once);
  });

  it('不改入参：数组与内部对象都保持原样，未变动的节按引用复用', () => {
    const overview = section('overview');
    const input = [overview, section('support')];
    const snapshot = input.map((entry) => ({ ...entry }));

    const next = ensureSection(input, template, 'metrics', NOW);

    expect(keysOf(input)).toEqual(['overview', 'support']);
    expect(input.map((entry) => ({ ...entry }))).toEqual(snapshot);
    expect(next[0]).toBe(overview);
    expect(next[2]).toBe(input[1]);
  });

  it('落位前后展示顺序逐节一致（这正是「不重排、不丢焦点」的判据）', () => {
    const shapes: ReportSection[][] = [
      [],
      [section('risks')],
      [section('overview'), section('risks'), section('next'), section('support')],
      [section('overview'), section('progress'), section('metrics'), section('risks'), section('next')],
      [section('custom-1'), section('risks'), section('overview')],
    ];
    for (const stored of shapes) {
      const before = shownKeys(stored);
      for (const key of templateKeys) {
        const ensured = ensureSection(stored, template, key, NOW);
        expect(shownKeys(stored)).toEqual(before);
        expect(shownKeys(ensured)).toEqual(before);
      }
    }
  });
});
