/**
 * 命令面板的纯匹配 / 排序 / 最近使用逻辑（无 React 依赖）。
 *
 * 打分优先级：标题完整匹配 > 标题前缀 > 标题包含 > 标签 > 路径（祖先标题）。
 */
import { KIND_LABELS } from '../../core/model';
import type { ItemKind } from '../../core/model';

export interface PaletteCommandCandidate {
  id: string;
  label: string;
  hint?: string;
  keywords?: string[];
}

export interface PaletteItemCandidate {
  id: string;
  title: string;
  kind: ItemKind;
  tags: string[];
  /** 根 → 自身的标题路径（itemPathTitles） */
  pathTitles: string[];
}

export interface PaletteAreaCandidate {
  id: string;
  name: string;
}

export type RecentRefType = 'command' | 'item' | 'area';

export interface RecentRef {
  type: RecentRefType;
  id: string;
}

export interface RecentRow {
  ref: RecentRef;
  label: string;
  hint: string;
}

export interface MatchHit {
  score: number;
  field: 'title' | 'tag' | 'path';
}

export interface RankedItem {
  candidate: PaletteItemCandidate;
  hit: MatchHit;
}

export interface PaletteResults {
  recent: RecentRow[];
  commands: PaletteCommandCandidate[];
  items: RankedItem[];
  areas: PaletteAreaCandidate[];
}

export interface PaletteSources {
  commands: PaletteCommandCandidate[];
  items: PaletteItemCandidate[];
  areas: PaletteAreaCandidate[];
  recent: RecentRef[];
}

export const RECENT_LIMIT = 6;
export const PALETTE_RECENT_KEY = 'textura.palette.recent';

function normalize(value: string): string {
  return value.trim().toLowerCase();
}

/** 条目匹配：标题 > 标签 > 祖先路径。无命中返回 null。 */
export function scoreItem(query: string, candidate: PaletteItemCandidate): MatchHit | null {
  const keyword = normalize(query);
  if (!keyword) return null;

  const title = candidate.title.toLowerCase();
  if (title === keyword) return { score: 1000, field: 'title' };
  if (title.startsWith(keyword)) {
    return { score: 900 - Math.min(title.length - keyword.length, 50), field: 'title' };
  }
  const titleIndex = title.indexOf(keyword);
  if (titleIndex >= 0) {
    return { score: 700 - Math.min(titleIndex, 100), field: 'title' };
  }

  for (const tag of candidate.tags) {
    const lower = tag.toLowerCase();
    if (lower === keyword) return { score: 500, field: 'tag' };
    if (lower.includes(keyword)) return { score: 450, field: 'tag' };
  }

  const path = candidate.pathTitles.slice(0, -1).join(' / ').toLowerCase();
  if (path.includes(keyword)) return { score: 300, field: 'path' };

  return null;
}

/** 条目排序：分数降序，同分按标题；最多返回 limit 条。 */
export function rankItems(
  query: string,
  candidates: PaletteItemCandidate[],
  limit = 8,
): RankedItem[] {
  const ranked: RankedItem[] = [];
  for (const candidate of candidates) {
    const hit = scoreItem(query, candidate);
    if (hit) ranked.push({ candidate, hit });
  }
  ranked.sort(
    (a, b) =>
      b.hit.score - a.hit.score ||
      a.candidate.title.localeCompare(b.candidate.title, 'zh-Hans-CN'),
  );
  return ranked.slice(0, limit);
}

/** 命令匹配：标题前缀 > 标题包含 > 关键词。无命中返回 null。 */
export function scoreCommand(query: string, command: PaletteCommandCandidate): number | null {
  const keyword = normalize(query);
  if (!keyword) return null;
  const label = command.label.toLowerCase();
  if (label === keyword) return 900;
  if (label.startsWith(keyword)) return 800 - Math.min(label.length - keyword.length, 40);
  if (label.includes(keyword)) return 600;
  for (const item of command.keywords ?? []) {
    const lower = item.toLowerCase();
    if (lower === keyword) return 450;
    if (lower.includes(keyword)) return 400;
  }
  return null;
}

/** 领域匹配：名称前缀 > 名称包含。 */
export function scoreArea(query: string, area: PaletteAreaCandidate): number | null {
  const keyword = normalize(query);
  if (!keyword) return null;
  const name = area.name.toLowerCase();
  if (name === keyword) return 800;
  if (name.startsWith(keyword)) return 700;
  if (name.includes(keyword)) return 500;
  return null;
}

/** 把最近使用的引用解析成可渲染行；失效引用自动跳过，最多 6 条。 */
export function resolveRecentRefs(
  recent: RecentRef[],
  sources: Pick<PaletteSources, 'commands' | 'items' | 'areas'>,
): RecentRow[] {
  const rows: RecentRow[] = [];
  const seen = new Set<string>();
  for (const ref of recent) {
    const key = `${ref.type}:${ref.id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    if (ref.type === 'command') {
      const command = sources.commands.find((entry) => entry.id === ref.id);
      if (command) rows.push({ ref, label: command.label, hint: '命令' });
    } else if (ref.type === 'item') {
      const item = sources.items.find((entry) => entry.id === ref.id);
      if (item) rows.push({ ref, label: item.title, hint: `条目 · ${KIND_LABELS[item.kind]}` });
    } else {
      const area = sources.areas.find((entry) => entry.id === ref.id);
      if (area) rows.push({ ref, label: area.name, hint: '领域' });
    }
    if (rows.length >= RECENT_LIMIT) break;
  }
  return rows;
}

/**
 * 面板结果：
 * - 空查询 → 只给「最近使用」+ 全部命令（方便直接浏览），不返回条目/领域
 * - 有关键词 → 命令 / 条目 / 领域三组匹配结果
 */
export function buildPaletteResults(query: string, sources: PaletteSources): PaletteResults {
  const keyword = query.trim();
  if (!keyword) {
    return {
      recent: resolveRecentRefs(sources.recent, sources),
      commands: sources.commands,
      items: [],
      areas: [],
    };
  }

  const commands = sources.commands
    .map((command) => ({ command, score: scoreCommand(keyword, command) }))
    .filter((entry): entry is { command: PaletteCommandCandidate; score: number } => entry.score !== null)
    .sort((a, b) => b.score - a.score)
    .map((entry) => entry.command);

  const areas = sources.areas
    .map((area) => ({ area, score: scoreArea(keyword, area) }))
    .filter((entry): entry is { area: PaletteAreaCandidate; score: number } => entry.score !== null)
    .sort((a, b) => b.score - a.score)
    .map((entry) => entry.area);

  return {
    recent: [],
    commands,
    items: rankItems(keyword, sources.items),
    areas,
  };
}

export interface HighlightSegment {
  text: string;
  match: boolean;
}

/** 简单子串高亮：只切出第一处命中。 */
export function highlightSegments(text: string, query: string): HighlightSegment[] {
  const keyword = query.trim();
  if (!keyword) return [{ text, match: false }];
  const index = text.toLowerCase().indexOf(keyword.toLowerCase());
  if (index < 0) return [{ text, match: false }];
  const segments: HighlightSegment[] = [];
  const before = text.slice(0, index);
  if (before) segments.push({ text: before, match: false });
  segments.push({ text: text.slice(index, index + keyword.length), match: true });
  const after = text.slice(index + keyword.length);
  if (after) segments.push({ text: after, match: false });
  return segments;
}

/** 最近使用写入顺序：去重后前插，最多 6 条。 */
export function pushRecentRef(ref: RecentRef, current: RecentRef[]): RecentRef[] {
  const key = `${ref.type}:${ref.id}`;
  return [ref, ...current.filter((entry) => `${entry.type}:${entry.id}` !== key)].slice(
    0,
    RECENT_LIMIT,
  );
}

function isRecentRef(value: unknown): value is RecentRef {
  if (!value || typeof value !== 'object') return false;
  const entry = value as Partial<RecentRef>;
  return (
    (entry.type === 'command' || entry.type === 'item' || entry.type === 'area') &&
    typeof entry.id === 'string' &&
    entry.id.length > 0
  );
}

/** 读取 localStorage 中的最近使用；不可用时返回空数组。 */
export function readRecentRefs(): RecentRef[] {
  if (typeof localStorage === 'undefined') return [];
  try {
    const raw = localStorage.getItem(PALETTE_RECENT_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(isRecentRef).slice(0, RECENT_LIMIT);
  } catch {
    return [];
  }
}

/** 持久化最近使用；隐私模式下静默失败。 */
export function writeRecentRefs(refs: RecentRef[]): void {
  if (typeof localStorage === 'undefined') return;
  try {
    localStorage.setItem(PALETTE_RECENT_KEY, JSON.stringify(refs.slice(0, RECENT_LIMIT)));
  } catch {
    // 忽略写入失败（隐私模式 / 配额不足）
  }
}
