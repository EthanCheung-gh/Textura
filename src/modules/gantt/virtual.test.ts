import { describe, expect, it } from 'vitest';
import { visibleColumns, visibleRows } from './virtual';

describe('visibleRows', () => {
  it('顶部窗口带上下缓冲，并夹在 0 起始处', () => {
    expect(visibleRows(0, 100, 36, 10, 1000)).toEqual({ start: 0, end: 13 });
    expect(visibleRows(-50, 72, 36, 2, 1000)).toEqual({ start: 0, end: 4 });
  });

  it('中部窗口覆盖可视行并保留 buffer', () => {
    const window = visibleRows(360, 100, 36, 10, 1000);
    expect(window).toEqual({ start: 0, end: 23 });
    expect(window.start * 36).toBeLessThanOrEqual(360);
    expect(window.end * 36).toBeGreaterThanOrEqual(360 + 100);
  });

  it('行高不整除时覆盖最后一行', () => {
    const window = visibleRows(10, 100, 36, 0, 1000);
    expect(window).toEqual({ start: 0, end: 4 });
    expect(window.end * 36).toBeGreaterThanOrEqual(10 + 100);
  });

  it('底部窗口不越过总行数', () => {
    expect(visibleRows(3600, 100, 36, 10, 100)).toEqual({ start: 90, end: 100 });
    expect(visibleRows(999999, 100, 36, 10, 100)).toEqual({ start: 100, end: 100 });
  });

  it('空列表与零高度视口', () => {
    expect(visibleRows(0, 100, 36, 10, 0)).toEqual({ start: 0, end: 0 });
    expect(visibleRows(36, 0, 36, 0, 100)).toEqual({ start: 1, end: 1 });
  });

  it('buffer 为 0 时窗口大小不超过可见行数 + 1', () => {
    const window = visibleRows(50, 72, 36, 0, 100);
    expect(window).toEqual({ start: 1, end: 4 });
    expect(window.end - window.start).toBeLessThanOrEqual(Math.ceil(72 / 36) + 1);
  });
});

describe('visibleColumns', () => {
  const uniform = Array.from({ length: 10 }, () => 10);

  it('按列宽累计定位窗口，并保留左右 buffer', () => {
    const window = visibleColumns(25, 30, uniform, 2);
    expect(window).toEqual({ start: 0, end: 8 });
    expect(window.start).toBeLessThanOrEqual(2);
    expect(window.end).toBeGreaterThanOrEqual(6);
    expect(window.start).toBeLessThan(window.end);
  });

  it('滚动边界恰好落在列边界时只包含相交列', () => {
    expect(visibleColumns(20, 20, uniform, 0)).toEqual({ start: 2, end: 4 });
    expect(visibleColumns(0, 10, uniform, 0)).toEqual({ start: 0, end: 1 });
  });

  it('支持非等宽列', () => {
    const widths = [10, 100, 10, 10];
    expect(visibleColumns(20, 50, widths, 0)).toEqual({ start: 1, end: 2 });
    expect(visibleColumns(20, 50, widths, 1)).toEqual({ start: 0, end: 3 });
  });

  it('空列表与滚过末尾', () => {
    expect(visibleColumns(0, 100, [], 2)).toEqual({ start: 0, end: 0 });
    expect(visibleColumns(90, 100, uniform, 2)).toEqual({ start: 7, end: 10 });
  });

  it('窗口大小有界且覆盖可视列', () => {
    const widths = [40, 70, 30, 50, 20, 60, 40];
    const scrollLeft = 50;
    const viewportW = 100;
    const buffer = 2;
    const window = visibleColumns(scrollLeft, viewportW, widths, buffer);
    expect(window.start).toBeLessThan(window.end);

    let firstVisible = -1;
    let lastVisibleExclusive = 0;
    let offset = 0;
    for (let index = 0; index < widths.length; index += 1) {
      const next = offset + widths[index];
      if (firstVisible < 0 && next > scrollLeft) firstVisible = index;
      if (offset < scrollLeft + viewportW) lastVisibleExclusive = index + 1;
      offset = next;
    }
    expect(window.start).toBeLessThanOrEqual(firstVisible);
    expect(window.end).toBeGreaterThanOrEqual(lastVisibleExclusive);
    expect(window.end - window.start).toBeLessThanOrEqual(lastVisibleExclusive - firstVisible + buffer * 2);
  });
});
