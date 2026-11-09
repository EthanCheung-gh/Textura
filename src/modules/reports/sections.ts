/**
 * 报告章节集合的纯编辑逻辑（无 React、无 store、无 Date，可直接单测）。
 *
 * 边界：这里只回答「一份报告的章节该怎么排、怎么增删改」，不生成正文、不写盘、
 * 不读时钟（时间一律由页面层作为参数传进来），也不碰任何 store 字段。
 *
 * ## 为什么需要这一层
 * 早先的编辑器把「章节」等同于「当前模板的 key」：`orderedSections` 按模板重排，
 * 模板外的 key 直接丢掉。一旦允许用户自己加章节，这条口径就站不住了——用户加的节
 * 既不在模板里，也没有模板标题可以兜底，只能靠报告自己记住。
 *
 * ## 契约（页面层与 AI 层都依赖这几条）
 * 1. **存储顺序即展示顺序**：`report.sections` 的数组顺序就是屏幕上的顺序。用户的
 *    上移 / 下移只需换掉数组顺序，读侧不再按模板重排；因此模板节同样可以被移动，
 *    模板只负责「缺节时补什么」，不再决定顺序。
 * 2. **模板缺节仍然补齐**：旧报告（模板改版前生成）缺的节必须出现在编辑器里，且补在
 *    **模板相对位置**（后一个模板节之前 / 前一个模板节之后），而不是一律追加到末尾，
 *    否则补出来的空节会跑到用户已有正文的后面。
 * 3. **模板外的节一律保留**：`custom-*` 是用户自建章节的 key 空间，但历史模板遗留的
 *    key 也照原样留在原位，绝不静默丢数据。
 * 4. **模板节的标题不可改**：模板标题是「口径」来源——`rebuildSection` 按标题重新
 *    汇总、AI 提示词的章节清单也用模板标题。若允许改名，用户改完再点「重新汇总」就会
 *    被模板标题覆盖回去，等于白改一次。自定义节不受此限。
 * 5. **时间参数化**：`addSection` / `renameSection` / `ensureSection` 收 `now`，页面层是唯一
 *    的时钟读取方，这样测试完全确定，也不会在渲染期偷偷产生 `updatedAt` 抖动。
 * 6. **编辑补出来的节先落位再改**：`displaySections` 补出来的模板空节在存储里没有位置，
 *    任何写回前都要先走 `ensureSection` 把它按**展示位置**插进存储，否则追加到末尾会重排
 *    整份列表并让正在输入的输入框失焦。
 * 7. **标题规范化只管写入口**：压空白 + 按长度裁剪只发生在**编辑器写入**这一层
 *    （`addSection` / `renameSection`）。导入 / 加载路径不改写存储里的标题，所以
 *    「标题一定单行且不超过 `MAX_SECTION_TITLE_CHARS`」是**写入口的承诺，不是读入口的
 *    假设**：导出层自己把标题压成一行（不裁剪、不加省略号），AI 提示层另按自己的预算
 *    裁剪。三层各兜一段，谁都不许依赖上游已经规范化过（详见 `MAX_SECTION_TITLE_CHARS`）。
 */
import type { ReportSection } from '../../core/model';
// 只取一个常量，不构成循环：`core/repo` 只依赖 model / selectors / utils，从不 import
// 本目录（`modules/reports`）。上限必须与存储层同源，UI 另写一份 40 早晚会走样。
import { MAX_REPORT_SECTIONS } from '../../core/repo';
import type { ReportTemplate, ReportTemplateSection } from './draft';

/** 用户自建章节的 key 前缀。序号从 1 起，全报告唯一。 */
export const CUSTOM_SECTION_PREFIX = 'custom-';

/**
 * 章节标题的长度上限，与 AI 提示层的 `MAX_HEADER_VALUE_CHARS`（`modules/ai/prompts.ts`，
 * 由本常量派生）同一个预算。
 *
 * 为什么是 120：导出时标题独占 Markdown 的**一整行**（`# …` / `### …`），120 个字已经是
 * 一行标题的极限，再长就既读不下去，也会把编辑器里的节头与导出正文的比例撑坏。
 *
 * ## 这个上限只管到哪儿（重要）
 * 规范化（压空白 → 去首尾 → 按上限裁剪）发生在**编辑器写入**这一层：`addSection` /
 * `renameSection`。它保证「用户在编辑器里敲进去 / 粘进去的标题」永远是同一份口径。
 *
 * 它**不是**全链路的存储不变量，别拿它当读入口的假设：
 * - 导入 / 加载路径不改写标题。`core/repo.migrateWorkspace` 只裁节数、补非法字段，
 *   不会重写 `title`，所以工作区里完全可能存着带换行或超过 120 字的标题；
 * - 导出层（`exportReport.reportMarkdown`）只把标题**压成一行**再拼进 `### ` 行，不裁剪、
 *   不加省略号——导出是用户手里的最终稿，不许静默吞掉他写的字；
 * - AI 提示层（`prompts.ts` 的 `sectionTitleText`）按同一预算再独立裁一次，因为提示词里的
 *   「章节清单」必须是一行定长文本。
 * 一句话：写入口把值做规矩，读出口各自兜住，谁都不依赖别人先做过。
 */
export const MAX_SECTION_TITLE_CHARS = 120;

/**
 * 章节标题的唯一规范化口径：压空白 → 去首尾 → 按上限裁剪。
 *
 * - 连续空白（含换行 `\n`、制表符 `\t`）一律压成**一个空格**。标题最终要占 Markdown 的
 *   标题行，内嵌换行会把一行拆成两行、把后半截顶成新标题，制表符则会让导出与 AI 提示词
 *   里的一行长度完全不可控；
 * - 裁剪带上省略号 `…`，总长**绝不超过** `MAX_SECTION_TITLE_CHARS`：切之前先让出省略号的
 *   那一格；正好切在高位代理上就少切一格，避免留下孤立代理在界面上变成乱码（与提示层
 *   `clipText` 的做法一致）；
 * - 空串 / 全空白规范化后仍是空串，调用方据此走「空操作」，列表里不会出现无名章节。
 *
 * 正常标题（中文、单空格分隔的英文）规范化后**逐字节不变**：这条规则对既有数据是无感的，
 * 只有真的带换行、制表符、连续空白或超长的标题才会被改写。
 *
 * 调用方只有**编辑器写入**两处（`addSection` / `renameSection`）：导入与历史数据不经过
 * 本函数，它们照原样躺在存储里，由导出层 / 提示层各自兜住（见 `MAX_SECTION_TITLE_CHARS`）。
 */
function normalizeSectionTitle(raw: string): string {
  const collapsed = raw.replace(/\s+/g, ' ').trim();
  if (collapsed.length <= MAX_SECTION_TITLE_CHARS) return collapsed;
  let cut = collapsed.slice(0, MAX_SECTION_TITLE_CHARS - 1);
  const lastUnit = cut.charCodeAt(cut.length - 1);
  if (lastUnit >= 0xd800 && lastUnit <= 0xdbff) cut = cut.slice(0, -1);
  return `${cut}…`;
}

/** 无操作时原样返回入参（`readonly` 只是对调用方的承诺，本文件从不就地写入）。 */
function unchanged(sections: readonly ReportSection[]): ReportSection[] {
  return sections as ReportSection[];
}

/** 章节目录很小（模板 6~7 节 + 少量自建节），线性查找比建 Map 更省。 */
function indexOfKey(sections: readonly ReportSection[], key: string): number {
  for (let index = 0; index < sections.length; index += 1) {
    if (sections[index].key === key) return index;
  }
  return -1;
}

/**
 * 是否用户自建章节：只判前缀。
 *
 * 不校验序号格式是刻意的——前缀已经足够把「用户自建」和模板 key（overview / metrics…）
 * 分干净；序号格式一旦变严，手工改过文件或今后换编号方案的数据就会突然「不被承认」，
 * 退化成删不掉也改不了名的幽灵节。
 */
export function isCustomSectionKey(key: string): boolean {
  return key.startsWith(CUSTOM_SECTION_PREFIX);
}

/**
 * 下一个可用的自建 key：取**最小的未占用序号**，只由入参推导。
 *
 * 不用 uuid / 时间戳：key 会进 Markdown 导出、AI 上下文与历史快照，可读可复现的
 * `custom-1`、`custom-2` 才好排查；同时「删掉最后一个再加一个」会复用同一个 key，
 * 序号不至于无限膨胀。
 */
export function nextCustomKey(sections: readonly ReportSection[]): string {
  const used = new Set<string>();
  for (const section of sections) used.add(section.key);
  let ordinal = 1;
  while (used.has(`${CUSTOM_SECTION_PREFIX}${ordinal}`)) ordinal += 1;
  return `${CUSTOM_SECTION_PREFIX}${ordinal}`;
}

/** 自建章节的默认标题：序号与 key 里的 n 一致（`custom-3` → `自定义章节 3`）。 */
export function defaultCustomTitle(ordinal: number): string {
  return `自定义章节 ${ordinal}`;
}

/**
 * 编辑器要展示的章节列表（全应用唯一的排序口径）。
 *
 * - **存储顺序即展示顺序**：先按 `report.sections` 原样铺开，用户的拖动结果因此得以保留；
 * - 同一 key 重复出现时**取第一处**（历史快照里出现过重复追加，展示层不重复画）；
 * - 模板里有、报告里没有的 key 补一个空节：标题用模板标题、`body: ''`、`origin: 'auto'`、
 *   `updatedAt` 取报告自身的更新时间（补出来的节不是用户写过的东西，不该带新时间戳）；
 *   位置是**模板相对位置**：放到最近的后继模板节之前，没有后继就放到最近的前驱模板节
 *   之后，两者都没有才追加到末尾；
 * - 模板外的节（`custom-*` 与历史模板遗留 key）留在原来的槽位上。
 *
 * 纯函数：不改入参；未变动的节按引用复用，便于页面层做 memo 比较。
 * 入参的 `sections` 只读（函数从不就地写入），`ensureSection` 这类只有只读入参的调用方
 * 因此不必先复制一份数组。
 */
export function displaySections(
  template: ReportTemplate,
  report: { sections: readonly ReportSection[]; updatedAt: string },
): ReportSection[] {
  const result: ReportSection[] = [];
  const seen = new Set<string>();
  for (const section of report.sections) {
    if (seen.has(section.key)) continue;
    seen.add(section.key);
    result.push(section);
  }

  const templateSections: ReportTemplateSection[] = template.sections;
  for (let index = 0; index < templateSections.length; index += 1) {
    const entry = templateSections[index];
    if (seen.has(entry.key)) continue;
    seen.add(entry.key);

    // 先找最近的后继模板节（插到它前面），再退而求其次找最近的前驱（插到它后面）。
    let insertAt = -1;
    for (let next = index + 1; next < templateSections.length && insertAt < 0; next += 1) {
      insertAt = indexOfKey(result, templateSections[next].key);
    }
    if (insertAt < 0) {
      for (let prev = index - 1; prev >= 0 && insertAt < 0; prev -= 1) {
        const anchor = indexOfKey(result, templateSections[prev].key);
        if (anchor >= 0) insertAt = anchor + 1;
      }
    }

    const synthesized: ReportSection = {
      key: entry.key,
      title: entry.title,
      body: '',
      origin: 'auto',
      updatedAt: report.updatedAt,
    };
    if (insertAt < 0) result.push(synthesized);
    else result.splice(insertAt, 0, synthesized);
  }

  return result;
}

/**
 * 把「只在展示里存在」的模板空节落成真实的一节，返回整份新数组。
 *
 * ## 为什么需要它
 * `displaySections` 会替旧报告补出模板缺的节，但补出来的节**在存储里没有位置**。用户一旦
 * 在这类空节里打字 / 插入素材 / 清空 / 重新汇总 / 采用 AI 参考，写回就走
 * `mergeSectionBodies`（key 不存在 → 追加到末尾），于是两件事同时发生：
 * 1. 整份章节列表被重排——刚写的那一节从原来的视觉位置跳到最末，其余节全部上移一格；
 * 2. React 按 key 复用节点，`article` 换了位置等于重新挂载，正在输入的 `TextArea`
 *    会丢掉焦点，打字直接中断（防抖期间尤其明显）。
 * 所以写回前先按**它在展示列表里已经占据的位置**插进存储数组：插入前后的展示顺序逐节一致，
 * 用户看不出任何变化，焦点也不会丢。
 *
 * ## 语义
 * - key 已经在存储里 → 返回**同一引用**：调用方原有的「同一引用即空操作」早退继续有效；
 * - key 不是模板节（自建节 `custom-*` 或历史模板遗留 key）→ 同样返回同一引用。本函数只负责
 *   「补齐模板缺节」，绝不为未知 key 造节——那是 `addSection` 的事，key 空间也不同；
 * - 否则按展示位置插入：用 `displaySections` 排出「此刻屏幕上看到的顺序」，找到占位节，
 *   再往后找第一个**已在存储里**的节，插到它在存储数组里的下标之前；全程找不到（占位节是
 *   最后一个可见节）就追加到末尾。
 *
 * 新节：`title` 取模板标题（模板标题是口径来源，见文件头第 4 条）、`body: ''`——接下来那次
 * 编辑会把正文与 origin 一起改写；`origin: 'manual'`：用户正在编辑它，这一节确实被手改过，
 * 不该显示成「自动汇总」。
 */
export function ensureSection(
  sections: readonly ReportSection[],
  template: ReportTemplate,
  key: string,
  now: string,
): ReportSection[] {
  if (indexOfKey(sections, key) >= 0) return unchanged(sections);
  const templateSection = template.sections.find((entry) => entry.key === key);
  if (!templateSection) return unchanged(sections);

  const shown = displaySections(template, { sections, updatedAt: now });
  const shownIndex = indexOfKey(shown, key);
  // 模板节一定出现在展示列表里；真出现意外就当作「无处可插」，不改存储。
  if (shownIndex < 0) return unchanged(sections);

  // 从占位节往后找第一个真实存在于存储的节：插到它在存储里的下标之前，占位节的位置就保住了。
  // 中间那些同为占位节的条目跳过——它们同样没有存储位置，不能当锚点。
  let insertAt = sections.length;
  for (let index = shownIndex + 1; index < shown.length; index += 1) {
    const storageIndex = indexOfKey(sections, shown[index].key);
    if (storageIndex >= 0) {
      insertAt = storageIndex;
      break;
    }
  }

  const materialized: ReportSection = {
    key,
    title: templateSection.title,
    body: '',
    origin: 'manual',
    updatedAt: now,
  };
  const result = [...sections];
  result.splice(insertAt, 0, materialized);
  return result;
}

/**
 * 还能不能再加一个自建章节：以**存储上限**为准，而不是「屏幕上看着还有空位」。
 *
 * 为什么必须停在存储上限：`core/repo` 在加载工作区时会把每份报告的 `sections` 裁到
 * `MAX_REPORT_SECTIONS` 节，并记一条「已修正 N 处非法数据」。若 UI 不先停手，用户加的
 * 第 41 节会照常写盘、看着已经保存，下次加载却被安静裁掉——这是实打实的数据丢失感，
 * 比按钮置灰难受得多。所以到顶就禁用「添加章节」，让用户先删再添加。
 *
 * 只数 `report.sections`（真正落盘的数组）：`displaySections` 补出来的模板空节不参与
 * 计数——它们每次都由模板重新合成，不占存储，不该提前把上限用光。
 */
export function canAddSection(sections: readonly ReportSection[]): boolean {
  return sections.length < MAX_REPORT_SECTIONS;
}

/**
 * 追加一个自建章节，返回整份新数组。
 *
 * 标题留空（或只有空白）时用 `defaultCustomTitle` 兜底，保证列表里永远有可读的名字；
 * 显式传进来的 `title` 与 `renameSection` 走**同一条**规范化规则（压空白 → 去首尾 →
 * 按 `MAX_SECTION_TITLE_CHARS` 裁剪），免得「带标题新建」和「新建后再改名」两条路径给出
 * 不同的标题。默认标题由本文件自己生成，本来就在上限内，不必再走一遍裁剪。
 * `origin` 记 `manual`：它确实是用户建出来的，不是系统汇总的。
 *
 * 本函数**不**做上限检查（纯编辑动作，越界由调用方先问 `canAddSection`）：页面层与
 * 测试都可能在任意长度上重放编辑，拒绝写入反而让「先删后加」的撤销路径变复杂。
 */
export function addSection(
  sections: readonly ReportSection[],
  now: string,
  title?: string,
): ReportSection[] {
  const key = nextCustomKey(sections);
  const ordinal = Number(key.slice(CUSTOM_SECTION_PREFIX.length));
  const next: ReportSection = {
    key,
    title: normalizeSectionTitle(title ?? '') || defaultCustomTitle(ordinal),
    body: '',
    origin: 'manual',
    updatedAt: now,
  };
  return [...sections, next];
}

/**
 * 重命名章节，返回整份新数组。
 *
 * - 只接受**自建章节**：模板节标题是口径来源（见文件头第 4 条），改名会被下次重新汇总
 *   覆盖，索性不许改；
 * - 入参标题先规范化（连续空白压成一个空格、去首尾、超过 `MAX_SECTION_TITLE_CHARS` 时
 *   截断并加 `…`）：编辑器写入是唯一能约束「用户手输 / 粘贴」的边界，理由见
 *   `MAX_SECTION_TITLE_CHARS` 的注释（读出口各自兜，不靠这里保证）；
 * - key 不存在、规范化后为空、**规范化后与存储里的标题相同**一律原样返回（同一引用）：
 *   页面层可用 `next === prev` 直接跳过写盘。最后一条尤其容易被漏掉——用户只是多打了
 *   几个空格（或把换行换回空格）时，标题其实没变，若照样返回新数组，`updatedAt` 会被
 *   顶掉、历史里多一条空快照，界面上还弹一句「已改名为…」，等于把一次空操作演成一次修改；
 * - `updatedAt` 用调用方给的 `now`，本文件不读时钟。
 */
export function renameSection(
  sections: readonly ReportSection[],
  key: string,
  title: string,
  now: string,
): ReportSection[] {
  const normalized = normalizeSectionTitle(title);
  if (!normalized || !isCustomSectionKey(key)) return unchanged(sections);
  const index = indexOfKey(sections, key);
  if (index < 0) return unchanged(sections);
  // 规范化之后与存储值逐字节相同 → 空操作。同一引用是给页面层的信号：不写盘、不留快照、
  // 也不弹提示，于是「只加了个空格」不会伪装成一次真正的改名。
  if (sections[index].title === normalized) return unchanged(sections);
  const result = [...sections];
  result[index] = { ...sections[index], title: normalized, updatedAt: now };
  return result;
}

/**
 * 删除章节，返回整份新数组。
 *
 * 只删自建章节：模板节删掉也会在下次 `displaySections` 里被补回来，删了等于没删，
 * 不如干脆不做，免得用户以为按钮失灵。key 不存在时原样返回（同一引用）。
 */
export function removeSection(
  sections: readonly ReportSection[],
  key: string,
): ReportSection[] {
  if (!isCustomSectionKey(key)) return unchanged(sections);
  if (indexOfKey(sections, key) < 0) return unchanged(sections);
  return sections.filter((section) => section.key !== key);
}

/**
 * 上移（`-1`）/ 下移（`+1`）一节，返回整份新数组。
 *
 * 模板节与自建节一视同仁——展示顺序就是存储顺序，用户想把自己加的节挪到「风险与阻塞」
 * 前面也该允许。到达两端或 key 不存在时返回**新的同序数组**（不是同一引用）：调用方
 * 可以无条件写回，再由内容比较决定要不要落盘。
 */
export function moveSection(
  sections: readonly ReportSection[],
  key: string,
  delta: -1 | 1,
): ReportSection[] {
  const index = indexOfKey(sections, key);
  const target = index + delta;
  if (index < 0 || target < 0 || target >= sections.length) return [...sections];
  const result = [...sections];
  const moved = result.splice(index, 1)[0];
  result.splice(target, 0, moved);
  return result;
}
