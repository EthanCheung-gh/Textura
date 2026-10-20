/**
 * 初始适配策略（纯函数）。
 *
 * 目标：打开 SOP 时优先保证文字可读，而不是一味把整张图塞进视口。
 * - padding 0.16（可用空间 = 容器 / 1.16）；
 * - zoom 有可读下限 0.7（13px 标题渲染约 9.1px）；
 * - 手动缩放仍可到 0.25，「适应画布」也允许低于下限以看全；
 * - 内容宽/高于视口时不再强行居中，而是从左上角 margin 开始，保证流程起点可见。
 */
import { SOP_NODE_HEIGHT, SOP_NODE_WIDTH } from './layout';

export interface FitBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ViewportTransform {
  x: number;
  y: number;
  zoom: number;
}

export interface ReadableFitOptions {
  containerWidth: number;
  containerHeight: number;
  bounds: FitBounds;
  /** 0.16 对应上下左右各留约 8% 的余量 */
  padding?: number;
  /** 初始 fit 的可读下限 */
  minZoom?: number;
  maxZoom?: number;
  /** 内容放不下时左上角保留的像素边距 */
  margin?: number;
}

export interface ReadableFitResult {
  viewport: ViewportTransform;
  zoom: number;
  /** 是否因为可读下限而放弃「一屏看全」 */
  clamped: boolean;
  fitsWidth: boolean;
  fitsHeight: boolean;
}

export const INITIAL_FIT_PADDING = 0.16;
export const READABLE_MIN_ZOOM = 0.7;
export const MAX_FIT_ZOOM = 1;
export const MIN_ZOOM = 0.25;
export const FIT_MARGIN = 16;

/** 由节点坐标与估算尺寸计算内容包围盒；空输入返回 null。 */
export function boundsOfPositions(
  positions: Readonly<Record<string, { x: number; y: number }>>,
  nodeWidth: number = SOP_NODE_WIDTH,
  nodeHeight: number = SOP_NODE_HEIGHT,
): FitBounds | null {
  const entries = Object.values(positions);
  if (entries.length === 0) return null;

  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const position of entries) {
    if (!Number.isFinite(position.x) || !Number.isFinite(position.y)) continue;
    minX = Math.min(minX, position.x);
    minY = Math.min(minY, position.y);
    maxX = Math.max(maxX, position.x + nodeWidth);
    maxY = Math.max(maxY, position.y + nodeHeight);
  }
  if (!Number.isFinite(minX) || !Number.isFinite(minY)) return null;

  return { x: minX, y: minY, width: Math.max(maxX - minX, 1), height: Math.max(maxY - minY, 1) };
}

/**
 * 计算初始 viewport。
 *
 * - 先按 React Flow 的 padding 语义（可用空间 = 容器 / (1 + padding)）求原始 zoom；
 * - 原始 zoom 低于可读下限时取 minZoom（宁可可滚动，也不缩小到不可读）；
 * - 某一方向放得下就居中，放不下则从 margin 锚定，避免把流程起点藏到视口外。
 */
export function computeReadableViewport({
  containerWidth,
  containerHeight,
  bounds,
  padding = INITIAL_FIT_PADDING,
  minZoom = READABLE_MIN_ZOOM,
  maxZoom = MAX_FIT_ZOOM,
  margin = FIT_MARGIN,
}: ReadableFitOptions): ReadableFitResult {
  const width = Math.max(containerWidth, 1);
  const height = Math.max(containerHeight, 1);
  const contentWidth = Math.max(bounds.width, 1);
  const contentHeight = Math.max(bounds.height, 1);

  const rawZoom = Math.min(
    width / (contentWidth * (1 + Math.max(padding, 0))),
    height / (contentHeight * (1 + Math.max(padding, 0))),
    maxZoom,
  );
  const floor = Math.min(minZoom, maxZoom);
  const clamped = rawZoom < floor;
  const zoom = Math.max(Math.min(rawZoom, maxZoom), floor);

  const scaledWidth = contentWidth * zoom;
  const scaledHeight = contentHeight * zoom;
  const fitsWidth = scaledWidth <= width;
  const fitsHeight = scaledHeight <= height;

  const x = fitsWidth
    ? (width - scaledWidth) / 2 - bounds.x * zoom
    : margin - bounds.x * zoom;
  const y = fitsHeight
    ? (height - scaledHeight) / 2 - bounds.y * zoom
    : margin - bounds.y * zoom;

  return {
    viewport: { x, y, zoom },
    zoom,
    clamped,
    fitsWidth,
    fitsHeight,
  };
}

/** 演示/编辑用的紧凑纵向预览间距：在 7 步规模下可让内容竖向铺满画布。 */
export const PREVIEW_LAYOUT = {
  rankdir: 'TB' as const,
  nodesep: 44,
  ranksep: 60,
  margin: 0,
};

/** 节点实际高度略高于 56（含检查项进度条），包围盒估算时留一点余量。 */
export const FIT_NODE_HEIGHT = SOP_NODE_HEIGHT + 4;

/**
 * 保存的布局是否「过于横向」：宽高比 >= 2 时，初始视图改用纵向预览布局，
 * 否则沿用用户坐标。
 */
export function isWideLayout(bounds: FitBounds | null): boolean {
  if (!bounds) return false;
  return bounds.width >= bounds.height * 2;
}
