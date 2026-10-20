import { describe, expect, it } from 'vitest';
import {
  FIT_MARGIN,
  READABLE_MIN_ZOOM,
  boundsOfPositions,
  computeReadableViewport,
  isWideLayout,
} from './fit';

const wideBounds = { x: 40, y: 160, width: 1160, height: 224 };
const verticalBounds = { x: 0, y: 0, width: 444, height: 664 };

describe('computeReadableViewport', () => {
  it('横向内容：低于可读下限时取 0.7，并从左侧 margin 锚定起点', () => {
    const result = computeReadableViewport({
      containerWidth: 526,
      containerHeight: 647,
      bounds: wideBounds,
    });

    expect(result.zoom).toBeCloseTo(READABLE_MIN_ZOOM, 5);
    expect(result.clamped).toBe(true);
    expect(result.fitsWidth).toBe(false);
    // 流程起点仍在视口内（不会被居中裁掉）
    expect(result.viewport.x + wideBounds.x * result.zoom).toBeCloseTo(FIT_MARGIN, 5);
    expect(result.viewport.zoom).toBeGreaterThanOrEqual(0.65);
  });

  it('纵向内容：1440 画布下高于下限、完整可见且水平居中', () => {
    const result = computeReadableViewport({
      containerWidth: 526,
      containerHeight: 647,
      bounds: verticalBounds,
    });

    const expected = 647 / (1.16 * verticalBounds.height);
    expect(result.zoom).toBeCloseTo(expected, 4);
    expect(result.zoom).toBeGreaterThan(READABLE_MIN_ZOOM);
    expect(result.zoom).toBeLessThanOrEqual(1);
    expect(result.fitsWidth).toBe(true);
    expect(result.fitsHeight).toBe(true);
    // 水平居中
    const center = result.viewport.x + (verticalBounds.x + verticalBounds.width / 2) * result.zoom;
    expect(center).toBeCloseTo(526 / 2, 4);
    // 竖向铺满 70% 以上
    expect((verticalBounds.height * result.zoom) / 647).toBeGreaterThan(0.7);
  });

  it('1024 画布：可读下限生效但内容仍完整可见，不溢出', () => {
    const result = computeReadableViewport({
      containerWidth: 478,
      containerHeight: 467,
      bounds: verticalBounds,
    });

    expect(result.zoom).toBeCloseTo(READABLE_MIN_ZOOM, 5);
    expect(verticalBounds.width * result.zoom).toBeLessThanOrEqual(478);
    expect(verticalBounds.height * result.zoom).toBeLessThanOrEqual(467);
    expect(result.fitsWidth).toBe(true);
    expect(result.fitsHeight).toBe(true);
    // 标题 13px × 0.7 ≈ 9.1px，满足可读要求
    expect(13 * result.zoom).toBeGreaterThanOrEqual(9);
  });

  it('小图不会被放大超过 maxZoom', () => {
    const result = computeReadableViewport({
      containerWidth: 800,
      containerHeight: 600,
      bounds: { x: 0, y: 0, width: 120, height: 80 },
      maxZoom: 1,
    });
    expect(result.zoom).toBe(1);
    expect(result.clamped).toBe(false);
  });

  it('放不下时不会返回负的可见尺寸，degenerate bounds 也可计算', () => {
    const result = computeReadableViewport({
      containerWidth: 0,
      containerHeight: 0,
      bounds: { x: 0, y: 0, width: 0, height: 0 },
    });
    expect(Number.isFinite(result.viewport.x)).toBe(true);
    expect(Number.isFinite(result.viewport.y)).toBe(true);
    expect(result.zoom).toBeGreaterThan(0);
  });
});

describe('boundsOfPositions', () => {
  it('按节点尺寸计算包围盒', () => {
    const bounds = boundsOfPositions(
      {
        a: { x: 40, y: 160 },
        b: { x: 280, y: 320 },
      },
      200,
      60,
    );
    expect(bounds).toEqual({ x: 40, y: 160, width: 440, height: 220 });
  });

  it('空输入返回 null', () => {
    expect(boundsOfPositions({})).toBeNull();
  });
});

describe('isWideLayout', () => {
  it('宽高比 >= 2 视为横向布局', () => {
    expect(isWideLayout({ x: 0, y: 0, width: 1160, height: 224 })).toBe(true);
    expect(isWideLayout({ x: 0, y: 0, width: 444, height: 664 })).toBe(false);
    expect(isWideLayout(null)).toBe(false);
  });
});
