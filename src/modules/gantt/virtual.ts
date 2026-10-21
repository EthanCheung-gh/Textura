/**
 * 甘特虚拟化窗口计算（纯函数）。
 *
 * 约定：返回的 `end` 是**排他上界**，可直接用于 `array.slice(start, end)`。
 * 调用方负责把滚动坐标换算成对应容器内的坐标（例如扣掉 52px 表头）。
 */

export interface WindowRange {
  /** 含 */
  start: number;
  /** 不含 */
  end: number;
}

/**
 * 计算行窗口。
 *
 * @param scrollTop  行区域滚动偏移（不含吸顶表头高度）
 * @param viewportH  行区域可视高度
 * @param rowH       固定行高
 * @param buffer     上下各预取的行数
 * @param total      总行数；未知时可省略，返回不封顶窗口
 */
export function visibleRows(
  scrollTop: number,
  viewportH: number,
  rowH: number,
  buffer: number,
  total: number = Number.POSITIVE_INFINITY,
): WindowRange {
  const count = Number.isFinite(total) ? Math.max(0, Math.floor(total)) : Number.POSITIVE_INFINITY;
  if (count === 0) return { start: 0, end: 0 };

  const height = Math.max(1, Number.isFinite(rowH) ? rowH : 1);
  const top = Math.max(0, Number.isFinite(scrollTop) ? scrollTop : 0);
  const view = Math.max(0, Number.isFinite(viewportH) ? viewportH : 0);
  const firstVisible = Math.floor(top / height);
  // 视口底部恰好落在行边界时，下一行不算可见。
  const lastVisibleExclusive = view === 0 ? firstVisible : Math.ceil((top + view) / height);
  const pad = Math.max(0, Math.floor(Number.isFinite(buffer) ? buffer : 0));

  const rawStart = Math.max(0, firstVisible - pad);
  const rawEnd = Math.max(rawStart, lastVisibleExclusive + pad);
  const start = Number.isFinite(count) ? Math.min(count, rawStart) : rawStart;
  const end = Number.isFinite(count) ? Math.min(count, Math.max(start, rawEnd)) : rawEnd;
  return { start, end };
}

/**
 * 计算列窗口（支持非等宽列）。
 *
 * @param scrollLeft 横向滚动偏移
 * @param viewportW  横向可视宽度
 * @param colWidths  每一列的宽度（必须与列的 x 偏移一致）
 * @param buffer     左右各预取列数
 */
export function visibleColumns(
  scrollLeft: number,
  viewportW: number,
  colWidths: readonly number[],
  buffer: number,
): WindowRange {
  const count = colWidths.length;
  if (count === 0) return { start: 0, end: 0 };

  const left = Math.max(0, Number.isFinite(scrollLeft) ? scrollLeft : 0);
  const width = Math.max(0, Number.isFinite(viewportW) ? viewportW : 0);
  const right = left + width;

  let offset = 0;
  let firstVisible = -1;
  let lastVisibleExclusive = 0;
  for (let index = 0; index < count; index += 1) {
    const columnWidth = Math.max(0, Number.isFinite(colWidths[index]) ? colWidths[index] : 0);
    const next = offset + columnWidth;
    if (firstVisible < 0 && next > left) firstVisible = index;
    if (offset < right) lastVisibleExclusive = index + 1;
    offset = next;
  }

  // 滚动到最右侧之外时没有“可见列”，退化为末尾 buffer 列。
  if (firstVisible < 0) firstVisible = count;
  const pad = Math.max(0, Math.floor(Number.isFinite(buffer) ? buffer : 0));
  const start = Math.max(0, Math.min(count, firstVisible - pad));
  const end = Math.max(start, Math.min(count, lastVisibleExclusive + pad));
  return { start, end };
}
