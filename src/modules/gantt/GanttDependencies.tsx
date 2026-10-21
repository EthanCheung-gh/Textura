import { memo, useState } from 'react';
import type { Edge } from '../../core/model';

export interface DepRect {
  x1: number;
  x2: number;
  cy: number;
}

export interface GanttDependenciesProps {
  edges: Edge[];
  rects: Map<string, DepRect>;
  titles: Map<string, string>;
  selectedId: string | null;
  width: number;
  height: number;
}

/**
 * `depends` 边：`from` 依赖 `to`（to 是前置）。
 * 常规情况从前置终点右侧出发、折线进入依赖方起点左侧；当中间行有任务条挡住
 * 竖直通道时，改走行间空隙（gutter），避免直角线穿过任务条。
 */
function dependencyPath(
  dependent: DepRect,
  prerequisite: DepRect,
  blockers: DepRect[],
  width: number,
): string {
  const sameRowTolerance = 2;
  const betweenRows = (rect: DepRect): boolean => {
    const low = Math.min(dependent.cy, prerequisite.cy);
    const high = Math.max(dependent.cy, prerequisite.cy);
    return rect.cy > low + sameRowTolerance && rect.cy < high - sameRowTolerance;
  };
  const intermediate = blockers.filter(
    (rect) => rect !== dependent && rect !== prerequisite && betweenRows(rect),
  );
  const blocked = (x: number): boolean =>
    intermediate.some((rect) => x >= rect.x1 - 2 && x <= rect.x2 + 2);

  const gap = dependent.x1 - prerequisite.x2;
  const startX = prerequisite.x2;
  const startY = prerequisite.cy;
  const endX = dependent.x1;
  const endY = dependent.cy;

  if (gap >= 8) {
    const candidates = [
      startX + gap / 2,
      startX + 6,
      endX - 6,
    ];
    const channel = candidates.find((x) => x > startX && x < endX && !blocked(x));
    if (channel !== undefined) {
      return `M ${startX} ${startY} L ${channel} ${startY} L ${channel} ${endY} L ${endX} ${endY}`;
    }
  } else if (gap >= 0 && !blocked(startX)) {
    // 前置结束与依赖开始相邻：直接竖向连接。
    return `M ${startX} ${startY} L ${Math.max(startX, endX)} ${endY}`;
  }

  // 绕行：先进入前置行下方的空隙，横移到空闲通道，再沿依赖行的上侧空隙接入左边缘。
  const direction = endY >= startY ? 1 : -1;
  const gutterStart = startY + direction * 18;
  const gutterEnd = endY - direction * 18;
  const candidates = [endX - 8, endX - 16, startX + 8, startX + 16, endX - 28];
  for (const rect of intermediate) {
    candidates.push(rect.x1 - 10, rect.x2 + 10);
  }
  const channel =
    candidates.find((x) => x > 2 && x < width - 2 && !blocked(x)) ?? Math.max(4, endX - 8);

  return [
    `M ${startX} ${startY}`,
    `L ${startX} ${gutterStart}`,
    `L ${channel} ${gutterStart}`,
    `L ${channel} ${gutterEnd}`,
    `L ${endX} ${gutterEnd}`,
    `L ${endX} ${endY}`,
  ].join(' ');
}

export const GanttDependencies = memo(function GanttDependencies({
  edges,
  rects,
  titles,
  selectedId,
  width,
  height,
}: GanttDependenciesProps) {
  const [hovered, setHovered] = useState<string | null>(null);

  const visibleEdges = edges.filter((edge) => rects.has(edge.from) && rects.has(edge.to));
  if (visibleEdges.length === 0) return null;
  const allRects = [...rects.values()];

  return (
    <svg
      className="gantt-deps"
      width={width}
      height={height}
      viewBox={`0 0 ${Math.max(1, width)} ${Math.max(1, height)}`}
      aria-hidden="true"
    >
      <defs>
        <marker
          id="gantt-arrow-idle"
          viewBox="0 0 7 7"
          markerWidth="7"
          markerHeight="7"
          refX="6"
          refY="3.5"
          orient="auto"
        >
          <path d="M0 0 L7 3.5 L0 7 z" fill="var(--text-faint)" />
        </marker>
        <marker
          id="gantt-arrow-hot"
          viewBox="0 0 7 7"
          markerWidth="7"
          markerHeight="7"
          refX="6"
          refY="3.5"
          orient="auto"
        >
          <path d="M0 0 L7 3.5 L0 7 z" fill="var(--accent)" />
        </marker>
      </defs>

      {visibleEdges.map((edge) => {
        const dependent = rects.get(edge.from);
        const prerequisite = rects.get(edge.to);
        if (!dependent || !prerequisite) return null;
        const hot = hovered === edge.id || (selectedId !== null && (edge.from === selectedId || edge.to === selectedId));
        const label = `${titles.get(edge.from) ?? edge.from} 依赖 ${titles.get(edge.to) ?? edge.to}`;

        return (
          <g key={edge.id}>
            <path
              className={hot ? 'gantt-dep-path is-hot' : 'gantt-dep-path'}
              d={dependencyPath(dependent, prerequisite, allRects, width)}
              markerEnd={`url(#gantt-arrow-${hot ? 'hot' : 'idle'})`}
              onPointerEnter={() => setHovered(edge.id)}
              onPointerLeave={() => setHovered((current) => (current === edge.id ? null : current))}
            >
              <title>{label}</title>
            </path>
            {hot ? (
              <circle className="gantt-dep-joint" cx={prerequisite.x2} cy={prerequisite.cy} r={2.2} />
            ) : null}
          </g>
        );
      })}
    </svg>
  );
});
