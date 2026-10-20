/**
 * SOP 画布：@xyflow/react 12 + 自定义节点 + 流程工具栏。
 *
 * 坐标只在「拖动结束 / 自动布局」时通过一次 updateItems 批量写回 store；
 * 拖动过程中只更新本地草稿，避免自动保存风暴与逐节点 undo 历史。
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Background,
  BackgroundVariant,
  MarkerType,
  Panel,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
} from '@xyflow/react';
import type {
  DefaultEdgeOptions,
  Edge as FlowEdge,
  NodeChange,
  NodeTypes,
  OnNodeDrag,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import clsx from 'clsx';
import type { Area, Edge, Item, SopNodeType } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { uid } from '../../core/utils';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { IconButton } from '../../ui/IconButton';
import { Icon } from '../../ui/icons';
import { SOP_NODE_WIDTH, layoutPositions } from './layout';
import {
  FIT_MARGIN,
  FIT_NODE_HEIGHT,
  INITIAL_FIT_PADDING,
  MAX_FIT_ZOOM,
  MIN_ZOOM,
  PREVIEW_LAYOUT,
  READABLE_MIN_ZOOM,
  boundsOfPositions,
  computeReadableViewport,
  isWideLayout,
} from './fit';
import { canvasPatchesToUpdateItems, positionsToPatch } from './positions';
import type { CanvasPatch } from './positions';
import type { FitBounds } from './fit';
import { NODE_TYPE_LABELS, SopNodeView } from './SopNode';
import type { SopFlowNode, SopNodeState } from './SopNode';
import type { RunSession, SopSelection } from './types';

const nodeTypes = { sop: SopNodeView } as NodeTypes;

const defaultEdgeOptions: DefaultEdgeOptions = {
  type: 'smoothstep',
  markerEnd: { type: MarkerType.ArrowClosed, width: 16, height: 16, color: 'var(--text-faint)' },
};

const NEW_NODE_TITLES: Record<SopNodeType, string> = {
  start: '开始',
  action: '新行动',
  decision: '条件判断？',
  check: '新检查项',
  end: '结束',
  note: '便签',
};

export interface SopCanvasProps {
  sop: Item;
  nodes: Item[];
  edges: Edge[];
  areas: Area[];
  selection: SopSelection;
  onSelect: (selection: SopSelection) => void;
  run: RunSession | null;
  onToggleRun: () => void;
  onDeleteSelection: () => void;
}

function SopCanvasInner({
  sop,
  nodes,
  edges,
  areas,
  selection,
  onSelect,
  run,
  onToggleRun,
  onDeleteSelection,
}: SopCanvasProps) {
  const createItem = useWorkspace((state) => state.createItem);
  const updateItems = useWorkspace((state) => state.updateItems);
  const createEdge = useWorkspace((state) => state.createEdge);
  const undo = useWorkspace((state) => state.undo);
  const redo = useWorkspace((state) => state.redo);
  const canUndo = useWorkspace((state) => state.canUndo());
  const canRedo = useWorkspace((state) => state.canRedo());
  const notify = useWorkspace((state) => state.notify);

  const { screenToFlowPosition, fitView, getViewport, setViewport, setCenter, zoomIn, zoomOut } =
    useReactFlow();
  const wrapperRef = useRef<HTMLDivElement>(null);
  const displayBoundsRef = useRef<FitBounds | null>(null);
  const timeoutsRef = useRef<number[]>([]);
  const rafRef = useRef<number | null>(null);
  const [drafts, setDrafts] = useState<Record<string, { x: number; y: number }>>({});
  // 纵向预览只在「未编辑布局」时生效；一旦用户拖动/自动布局/撤销，就回落到已保存坐标。
  const [previewDisabled, setPreviewDisabled] = useState(false);

  const running = run !== null;
  const selectedNodeId = selection?.kind === 'node' ? selection.id : null;

  /** 记录组件内所有延迟任务，卸载时统一清理，避免对已卸载实例调用 setViewport。 */
  const schedule = useCallback((fn: () => void, ms: number): void => {
    const id = window.setTimeout(() => {
      timeoutsRef.current = timeoutsRef.current.filter((entry) => entry !== id);
      fn();
    }, ms);
    timeoutsRef.current.push(id);
  }, []);

  useEffect(
    () => () => {
      for (const id of timeoutsRef.current) window.clearTimeout(id);
      timeoutsRef.current = [];
      if (rafRef.current !== null) window.cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    },
    [],
  );

  useEffect(() => {
    setDrafts({});
    setPreviewDisabled(false);
  }, [sop.id]);

  const areaColors = useMemo(() => {
    const map: Record<string, string> = {};
    for (const area of areas) map[area.id] = area.color;
    return map;
  }, [areas]);

  const currentCanvas = useMemo(() => {
    const map: Record<string, { x: number; y: number }> = {};
    for (const item of nodes) map[item.id] = item.sop?.canvas ?? { x: 0, y: 0 };
    return map;
  }, [nodes]);

  const savedBounds = useMemo(
    () => boundsOfPositions(currentCanvas, SOP_NODE_WIDTH, FIT_NODE_HEIGHT),
    [currentCanvas],
  );

  const graphKey = useMemo(
    () =>
      `${nodes.map((item) => item.id).sort().join('|')}##${edges
        .map((edge) => `${edge.from}>${edge.to}`)
        .sort()
        .join('|')}`,
    [edges, nodes],
  );

  /**
   * 首次打开且保存的坐标过于横向时，用紧凑的 dagre 纵向布局做「初始预览」。
   * 只影响显示，不写 store；用户一旦拖动/自动布局/撤销，即回到已保存坐标。
   */
  const previewPositions = useMemo(() => {
    if (previewDisabled || nodes.length < 4 || !isWideLayout(savedBounds)) return null;
    return layoutPositions(
      nodes.map((item) => ({ id: item.id })),
      edges.map((edge) => ({ from: edge.from, to: edge.to })),
      PREVIEW_LAYOUT,
    );
  }, [edges, graphKey, nodes, previewDisabled, savedBounds]);

  const displayPositions = useMemo(
    () => (previewPositions ? { ...currentCanvas, ...previewPositions } : currentCanvas),
    [currentCanvas, previewPositions],
  );

  useEffect(() => {
    displayBoundsRef.current = boundsOfPositions(displayPositions, SOP_NODE_WIDTH, FIT_NODE_HEIGHT);
  }, [displayPositions]);

  // 宽度变化（右栏收起 / 窗口缩放）重新适配；高度变化（运行条出现）保持缩放，
  // 仅把内容竖向居中/顶部对齐，避免底部节点被裁掉。
  useEffect(() => {
    const element = wrapperRef.current;
    if (!element) return;
    const initial = element.getBoundingClientRect();
    let lastWidth = initial.width;
    let lastHeight = initial.height;
    let timer: number | null = null;

    const observer = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect ?? element.getBoundingClientRect();
      const width = rect.width;
      const height = rect.height;
      const widthChanged = Math.abs(width - lastWidth) >= 24;
      const heightChanged = Math.abs(height - lastHeight) >= 24;
      if (!widthChanged && !heightChanged) return;
      lastWidth = width;
      lastHeight = height;
      if (timer) window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        if (widthChanged) {
          void fitView({ padding: INITIAL_FIT_PADDING, maxZoom: MAX_FIT_ZOOM, duration: 200 });
          return;
        }
        const bounds = displayBoundsRef.current;
        if (!bounds) return;
        const viewport = getViewport();
        const scaledWidth = bounds.width * viewport.zoom;
        const scaledHeight = bounds.height * viewport.zoom;
        if (scaledHeight > height + 16) {
          // 放不下时从顶部开始，保证流程起点可见。
          void setViewport(
            { x: viewport.x, y: FIT_MARGIN - bounds.y * viewport.zoom, zoom: viewport.zoom },
            { duration: 160 },
          );
          return;
        }
        const x =
          scaledWidth <= width
            ? (width - scaledWidth) / 2 - bounds.x * viewport.zoom
            : viewport.x;
        const y = (height - scaledHeight) / 2 - bounds.y * viewport.zoom;
        void setViewport({ x, y, zoom: viewport.zoom }, { duration: 160 });
      }, 160);
    });
    observer.observe(element);
    return () => {
      observer.disconnect();
      if (timer) window.clearTimeout(timer);
    };
  }, [fitView, getViewport, setViewport]);

  // 运行模式下确保当前步骤在可视区内（仅在超出视口时居中，不打断整体视野）。
  const runCurrentId = run?.currentId ?? null;
  useEffect(() => {
    if (!runCurrentId) return;
    const element = wrapperRef.current;
    const position = displayPositions[runCurrentId];
    if (!element || !position) return;
    const rect = element.getBoundingClientRect();
    const viewport = getViewport();
    const nodeLeft = rect.left + viewport.x + position.x * viewport.zoom;
    const nodeTop = rect.top + viewport.y + position.y * viewport.zoom;
    const nodeWidth = SOP_NODE_WIDTH * viewport.zoom;
    const nodeHeight = FIT_NODE_HEIGHT * viewport.zoom;
    const margin = 24;
    const outside =
      nodeLeft < rect.left + margin ||
      nodeLeft + nodeWidth > rect.right - margin ||
      nodeTop < rect.top + margin ||
      nodeTop + nodeHeight > rect.bottom - margin;
    if (!outside) return;
    const timer = window.setTimeout(() => {
      void setCenter(
        position.x + SOP_NODE_WIDTH / 2,
        position.y + FIT_NODE_HEIGHT / 2,
        { zoom: viewport.zoom, duration: 240 },
      );
    }, 260);
    return () => window.clearTimeout(timer);
  }, [displayPositions, getViewport, runCurrentId, setCenter]);

  const fitInitialView = useCallback((): boolean => {
    const element = wrapperRef.current;
    if (!element) return false;
    const rect = element.getBoundingClientRect();
    if (rect.width < 40 || rect.height < 40) return false;
    const bounds = boundsOfPositions(displayPositions, SOP_NODE_WIDTH, FIT_NODE_HEIGHT);
    if (!bounds) return false;
    const { viewport } = computeReadableViewport({
      containerWidth: rect.width,
      containerHeight: rect.height,
      bounds,
      padding: INITIAL_FIT_PADDING,
      minZoom: READABLE_MIN_ZOOM,
      maxZoom: MAX_FIT_ZOOM,
    });
    void setViewport(viewport, { duration: 0 });
    return true;
  }, [displayPositions, setViewport]);

  const handleInit = useCallback(() => {
    if (rafRef.current !== null) window.cancelAnimationFrame(rafRef.current);
    let attempts = 0;
    const attempt = () => {
      rafRef.current = null;
      attempts += 1;
      if (!fitInitialView() && attempts < 12) schedule(attempt, 60);
    };
    rafRef.current = window.requestAnimationFrame(attempt);
  }, [fitInitialView, schedule]);

  const flowNodes = useMemo<SopFlowNode[]>(
    () =>
      nodes.map((item) => {
        const checklist = item.sop?.checklist ?? [];
        const canvas = item.sop?.canvas ?? { x: 0, y: 0 };
        let state: SopNodeState = 'idle';
        if (run) {
          if (run.currentId === item.id) state = 'current';
          else if (run.failed.includes(item.id)) state = 'failed';
          else if (run.visited.includes(item.id)) state = 'visited';
        }
        return {
          id: item.id,
          type: 'sop',
          position: drafts[item.id] ?? displayPositions[item.id] ?? canvas,
          selected: selectedNodeId === item.id,
          data: {
            title: item.title,
            nodeType: item.sop?.nodeType ?? 'action',
            owner: item.sop?.owner ?? '',
            durationMin: item.sop?.durationMin ?? null,
            checklistDone: checklist.filter((entry) => entry.done).length,
            checklistTotal: checklist.length,
            areaColor: item.areaId ? (areaColors[item.areaId] ?? null) : null,
            state,
          },
        };
      }),
    [areaColors, displayPositions, drafts, nodes, run, selectedNodeId],
  );

  const flowEdges = useMemo<FlowEdge[]>(() => {
    // 根据节点相对位置选择连接 handle：横向相邻走左右 handle，其余走上/下。
    // handle 不写入 Edge 模型（契约里没有该字段），每次渲染按当前位置推导。
    const positionById = new Map(flowNodes.map((node) => [node.id, node.position]));
    const handlesFor = (fromId: string, toId: string): { sourceHandle?: string; targetHandle?: string } => {
      const from = positionById.get(fromId);
      const to = positionById.get(toId);
      if (!from || !to) return {};
      const dx = to.x - from.x;
      const dy = to.y - from.y;
      // 回到上方的连线从右侧绕出，避免竖直穿过中间节点。
      if (dy < -20) return { sourceHandle: 'right' };
      // 横向相邻的连线走左右 handle，其余走上/下。
      if (dx > 0 && Math.abs(dx) >= Math.abs(dy) * 1.2) {
        return { sourceHandle: 'right', targetHandle: 'left' };
      }
      return {};
    };

    return edges.map((edge) => {
      const selected = selection?.kind === 'edge' && selection.id === edge.id;
      const active = run !== null && run.currentId === edge.from;
      return {
        id: edge.id,
        source: edge.from,
        target: edge.to,
        type: 'smoothstep',
        label: edge.label || undefined,
        selected,
        className: clsx('sop-edge', selected && 'is-selected', active && 'is-active'),
        ...handlesFor(edge.from, edge.to),
        markerEnd: { type: MarkerType.ArrowClosed, width: 16, height: 16, color: 'var(--text-faint)' },
      };
    });
  }, [edges, flowNodes, selection, run]);

  /** 一次手势 / 一次命令的所有坐标变化合并成一次 updateItems（单条历史、单次保存）。 */
  const writeCanvasPatches = useCallback(
    (patches: readonly CanvasPatch[]): number => {
      if (patches.length === 0) return 0;
      updateItems(canvasPatchesToUpdateItems(patches));
      return patches.length;
    },
    [updateItems],
  );

  const commitPositions = useCallback(
    (positions: Readonly<Record<string, { x: number; y: number }>>) => {
      const moved = Object.entries(positions).map(([id, position]) => ({ id, position }));
      const patches = positionsToPatch(moved, currentCanvas);
      writeCanvasPatches(patches);
      setDrafts({});
      return patches.length;
    },
    [currentCanvas, writeCanvasPatches],
  );

  /** 把当前纵向预览一次性落盘，保证拖动后其它节点不会跳回旧坐标。 */
  const materializePreview = useCallback((): boolean => {
    if (!previewPositions) return false;
    commitPositions(previewPositions);
    setPreviewDisabled(true);
    return true;
  }, [commitPositions, previewPositions]);

  const applyPositions = useCallback(
    (moved: readonly { id: string; position: { x: number; y: number } }[]) => {
      const patches = positionsToPatch(moved, currentCanvas);
      writeCanvasPatches(patches);
      if (patches.length > 0) {
        const touched = new Set(patches.map((patch) => patch.id));
        setDrafts((previous) => {
          const next = { ...previous };
          for (const id of touched) delete next[id];
          return next;
        });
      }
    },
    [currentCanvas, writeCanvasPatches],
  );

  const handleNodesChange = useCallback((changes: NodeChange[]) => {
    const moves = changes.filter((change) => change.type === 'position' && change.position);
    if (moves.length === 0) return;
    setDrafts((previous) => {
      const next = { ...previous };
      for (const change of moves) {
        if (change.type === 'position' && change.position) next[change.id] = change.position;
      }
      return next;
    });
  }, []);

  const handleNodeDragStop: OnNodeDrag<SopFlowNode> = useCallback(
    (_event, _node, dragged) => {
      if (previewPositions) {
        const merged: Record<string, { x: number; y: number }> = { ...previewPositions };
        for (const node of dragged) {
          merged[node.id] = { x: node.position.x, y: node.position.y };
        }
        commitPositions(merged);
        setPreviewDisabled(true);
        return;
      }
      applyPositions(dragged.map((node) => ({ id: node.id, position: node.position })));
    },
    [applyPositions, commitPositions, previewPositions],
  );

  const handleConnect = useCallback(
    (connection: { source: string | null; target: string | null }) => {
      if (!connection.source || !connection.target) return;
      if (connection.source === connection.target) return;
      createEdge({ from: connection.source, to: connection.target, type: 'flow', label: '' });
    },
    [createEdge],
  );

  const viewportCenter = useCallback(() => {
    const rect = wrapperRef.current?.getBoundingClientRect();
    if (!rect) return { x: 0, y: 0 };
    return screenToFlowPosition({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 });
  }, [screenToFlowPosition]);

  const addNode = useCallback(
    (nodeType: SopNodeType) => {
      if (running) return;
      const center = viewportCenter();
      // 新建节点会写坐标，先把纵向预览落盘，避免新旧布局混杂。
      materializePreview();
      const item = createItem({
        kind: 'step',
        title: NEW_NODE_TITLES[nodeType],
        parentId: sop.id,
        areaId: sop.areaId,
        status: 'next',
        sop: {
          nodeType,
          canvas: {
            x: Math.round(center.x - SOP_NODE_WIDTH / 2),
            y: Math.round(center.y - 30),
          },
          checklist:
            nodeType === 'check' ? [{ id: uid('chk'), text: '检查项', done: false }] : [],
        },
      });
      if (selectedNodeId) {
        createEdge({ from: selectedNodeId, to: item.id, type: 'flow', label: '' });
      }
      onSelect({ kind: 'node', id: item.id });
    },
    [
      createEdge,
      createItem,
      materializePreview,
      onSelect,
      running,
      selectedNodeId,
      sop.areaId,
      sop.id,
      viewportCenter,
    ],
  );

  const handleAutoLayout = useCallback(() => {
    if (nodes.length === 0) return;
    setPreviewDisabled(true);
    const positions = layoutPositions(
      nodes.map((item) => ({ id: item.id })),
      edges.map((edge) => ({ from: edge.from, to: edge.to })),
      { rankdir: 'TB', nodesep: 60, ranksep: 90, margin: 40 },
    );
    applyPositions(
      Object.entries(positions).map(([id, position]) => ({
        id,
        position,
      })),
    );
    schedule(() => {
      void fitView({ padding: INITIAL_FIT_PADDING, maxZoom: MAX_FIT_ZOOM, duration: 280 });
    }, 80);
  }, [applyPositions, edges, fitView, nodes, schedule]);

  const handleUndo = useCallback(() => {
    setPreviewDisabled(true);
    setDrafts({});
    undo();
    schedule(() => {
      void fitView({ padding: INITIAL_FIT_PADDING, maxZoom: MAX_FIT_ZOOM, duration: 200 });
    }, 80);
  }, [fitView, schedule, undo]);

  const handleRedo = useCallback(() => {
    setPreviewDisabled(true);
    setDrafts({});
    redo();
    schedule(() => {
      void fitView({ padding: INITIAL_FIT_PADDING, maxZoom: MAX_FIT_ZOOM, duration: 200 });
    }, 80);
  }, [fitView, redo, schedule]);

  // Cmd/Ctrl+Z 在本组件处理：撤销/重做后需要同步适配画布视口。
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== 'z') return;
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest('input, textarea, select, [contenteditable="true"]')) return;
      if (target?.closest('[role="dialog"]') || document.querySelector('[role="dialog"]')) return;
      event.preventDefault();
      if (event.shiftKey) handleRedo();
      else handleUndo();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleRedo, handleUndo]);

  const handleDelete = useCallback(() => {
    if (!selection) {
      notify('先选中一个节点或连线', 'info');
      return;
    }
    onDeleteSelection();
  }, [notify, onDeleteSelection, selection]);

  return (
    <section className="sop-canvas" aria-label="SOP 画布">
      <div className="sop-toolbar" role="toolbar" aria-label="画布工具栏">
        <div className="sop-toolbar-group">
          {(['action', 'decision', 'check', 'end'] as SopNodeType[]).map((nodeType) => (
            <Button
              key={nodeType}
              size="sm"
              variant="ghost"
              title={`新建 ${NODE_TYPE_LABELS[nodeType]} 节点（${nodeType}）`}
              iconLeft={<Icon name="plus" size={13} />}
              disabled={running}
              onClick={() => addNode(nodeType)}
            >
              {NODE_TYPE_LABELS[nodeType]}
            </Button>
          ))}
        </div>
        <div className="sop-toolbar-group">
          <Button
            size="sm"
            variant={running ? 'primary' : 'secondary'}
            iconLeft={<Icon name={running ? 'close' : 'play'} size={13} />}
            title={running ? '退出运行模式' : '进入运行模式，从开始节点逐步执行'}
            onClick={onToggleRun}
          >
            {running ? '退出运行' : '运行'}
          </Button>
          <Button
            size="sm"
            variant="ghost"
            iconLeft={<Icon name="workflow" size={13} />}
            disabled={running || nodes.length === 0}
            title="按 dagre 分层自动布局（TB）"
            onClick={handleAutoLayout}
          >
            自动布局
          </Button>
        </div>
        <div className="sop-toolbar-group sop-toolbar-group--icons">
          <IconButton
            label="适应画布（必要时可缩小到 25% 以看全）"
            size="sm"
            onClick={() =>
              void fitView({
                padding: INITIAL_FIT_PADDING,
                maxZoom: MAX_FIT_ZOOM,
                duration: 260,
              })
            }
          >
            <Icon name="target" size={15} />
          </IconButton>
          <IconButton label="放大" size="sm" onClick={() => void zoomIn({ duration: 150 })}>
            <Icon name="zoom-in" size={15} />
          </IconButton>
          <IconButton label="缩小" size="sm" onClick={() => void zoomOut({ duration: 150 })}>
            <Icon name="zoom-out" size={15} />
          </IconButton>
          <IconButton label="撤销" size="sm" disabled={!canUndo} onClick={handleUndo}>
            <Icon name="chevron-left" size={15} />
          </IconButton>
          <IconButton label="重做" size="sm" disabled={!canRedo} onClick={handleRedo}>
            <Icon name="chevron-right" size={15} />
          </IconButton>
          <IconButton
            label="删除选中的节点或连线"
            size="sm"
            variant="danger"
            disabled={!selection}
            onClick={handleDelete}
          >
            <Icon name="trash" size={15} />
          </IconButton>
        </div>
      </div>

      <div className="sop-canvas-flow" ref={wrapperRef}>
        <ReactFlow
          key={sop.id}
          nodes={flowNodes}
          edges={flowEdges}
          nodeTypes={nodeTypes}
          onNodesChange={handleNodesChange}
          onNodeDragStop={handleNodeDragStop}
          onNodeClick={(_event, node) => onSelect({ kind: 'node', id: node.id })}
          onEdgeClick={(_event, edge) => onSelect({ kind: 'edge', id: edge.id })}
          onPaneClick={() => onSelect(null)}
          onConnect={handleConnect}
          onInit={handleInit}
          defaultEdgeOptions={defaultEdgeOptions}
          nodesDraggable={!running}
          nodesConnectable={!running}
          deleteKeyCode={null}
          minZoom={MIN_ZOOM}
          maxZoom={1.8}
          fitViewOptions={{ padding: INITIAL_FIT_PADDING, maxZoom: MAX_FIT_ZOOM }}
          connectionLineStyle={{ stroke: 'var(--accent)', strokeWidth: 1.5 }}
          aria-label="SOP 流程图"
        >
          <Background
            variant={BackgroundVariant.Dots}
            gap={18}
            size={1}
            color="var(--border-strong)"
          />
          {nodes.length === 0 ? (
            <Panel position="top-center" className="sop-canvas-empty">
              <EmptyState
                icon={<Icon name="workflow" size={20} />}
                title="先添加一个开始节点"
                description="SOP 就是一张可执行的流程图：节点是步骤，连线决定下一步。"
                action={
                  <Button
                    variant="primary"
                    size="sm"
                    iconLeft={<Icon name="plus" size={14} />}
                    onClick={() => addNode('start')}
                  >
                    添加开始节点
                  </Button>
                }
                compact
              />
            </Panel>
          ) : null}
        </ReactFlow>
      </div>
    </section>
  );
}

export function SopCanvas(props: SopCanvasProps) {
  return (
    <ReactFlowProvider>
      <SopCanvasInner {...props} />
    </ReactFlowProvider>
  );
}
