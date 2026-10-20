/** SOP 模块入口：列表 + 画布 + 检查器 + 运行。 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import type { Item } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { itemsOfKind, sopGraph } from '../../core/selectors';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { RunHistory } from './RunHistory';
import { SopCanvas } from './SopCanvas';
import { SopInspector } from './SopInspector';
import { SopList } from './SopList';
import { SopRunBar } from './SopRunBar';
import { advance, elapsedMinutes, startStepId, summarizeResults } from './runLogic';
import type { BranchOption, RunResult } from './runLogic';
import type { RunSession, SopSelection } from './types';
import './sop.css';

interface BranchState {
  options: BranchOption[];
  result: RunResult;
}

export function SopPage() {
  const workspace = useWorkspace((state) => state.workspace);
  const logRun = useWorkspace((state) => state.logRun);
  const deleteItems = useWorkspace((state) => state.deleteItems);
  const deleteEdge = useWorkspace((state) => state.deleteEdge);
  const notify = useWorkspace((state) => state.notify);

  const [selectedSopId, setSelectedSopId] = useState<string | null>(null);
  const [selection, setSelection] = useState<SopSelection>(null);
  const [run, setRun] = useState<RunSession | null>(null);
  const [branch, setBranch] = useState<BranchState | null>(null);
  // 窄屏默认收起右栏（抽屉），1440 及以上默认展开；避免挤压画布到不可读。
  const [inspectorOpen, setInspectorOpen] = useState(
    () => typeof window === 'undefined' || window.innerWidth >= 1440,
  );

  const sops = useMemo(() => itemsOfKind(workspace, 'sop'), [workspace]);
  const activeSop: Item | null = sops.find((sop) => sop.id === selectedSopId) ?? sops[0] ?? null;
  const activeSopId = activeSop?.id ?? null;

  const graph = useMemo(
    () => (activeSopId ? sopGraph(workspace, activeSopId) : { nodes: [], edges: [] }),
    [activeSopId, workspace],
  );

  // 切换 SOP 时清空画布选中与运行态。
  useEffect(() => {
    setSelection(null);
    setRun(null);
    setBranch(null);
  }, [activeSopId]);

  const currentStep = run ? (graph.nodes.find((node) => node.id === run.currentId) ?? null) : null;

  // 运行中当前节点被删除时安全退出。
  useEffect(() => {
    if (run && !graph.nodes.some((node) => node.id === run.currentId)) {
      setRun(null);
      setBranch(null);
    }
  }, [graph.nodes, run]);

  const selectSop = useCallback((id: string) => {
    setSelectedSopId(id);
  }, []);

  const deleteSelection = useCallback(() => {
    if (!selection) return;
    if (selection.kind === 'node') {
      deleteItems([selection.id]);
      notify('已删除节点及其连线', 'info');
    } else {
      deleteEdge(selection.id);
      notify('已删除连线', 'info');
    }
    setSelection(null);
  }, [deleteEdge, deleteItems, notify, selection]);

  const finishRun = useCallback(
    (session: RunSession) => {
      const stats = summarizeResults(session.results);
      const minutes = elapsedMinutes(session.startedAt, new Date().toISOString());
      notify(
        `流程结束：通过 ${stats.pass} / 未通过 ${stats.fail} / 跳过 ${stats.skip}，耗时 ${minutes} 分钟`,
        'success',
      );
      setRun(null);
      setBranch(null);
    },
    [notify],
  );

  const moveTo = useCallback((session: RunSession, stepId: string) => {
    setRun({
      ...session,
      currentId: stepId,
      visited: session.visited.includes(stepId) ? session.visited : [...session.visited, stepId],
    });
    setSelection({ kind: 'node', id: stepId });
    setBranch(null);
  }, []);

  const toggleRun = useCallback(() => {
    if (run) {
      setRun(null);
      setBranch(null);
      notify('已退出运行模式', 'info');
      return;
    }
    if (!activeSop) return;
    const start = startStepId(
      graph.nodes.map((node) => ({ id: node.id, nodeType: node.sop?.nodeType })),
      graph.edges,
    );
    if (!start) {
      notify('画布还没有步骤，先添加一个开始节点', 'error');
      return;
    }
    setRun({
      currentId: start,
      visited: [start],
      failed: [],
      startedAt: new Date().toISOString(),
      results: [],
    });
    setSelection({ kind: 'node', id: start });
  }, [activeSop, graph.edges, graph.nodes, notify, run]);

  const runResult = useCallback(
    (result: RunResult) => {
      if (!run || !activeSop) return;
      logRun({ sopId: activeSop.id, stepId: run.currentId, result });

      const outcome = advance({
        stepId: run.currentId,
        edges: graph.edges,
        result,
        visited: run.visited,
      });
      const next: RunSession = {
        ...run,
        results: [...run.results, result],
        failed: result === 'fail' ? [...run.failed, run.currentId] : run.failed,
      };

      if (outcome.status === 'next') {
        moveTo(next, outcome.stepId);
      } else if (outcome.status === 'branch') {
        setRun(next);
        setBranch({ options: outcome.options, result });
      } else {
        finishRun(next);
      }
    },
    [activeSop, finishRun, graph.edges, logRun, moveTo, run],
  );

  const chooseBranch = useCallback(
    (edgeId: string) => {
      if (!run || !branch) return;
      const outcome = advance({
        stepId: run.currentId,
        edges: graph.edges,
        result: branch.result,
        choice: edgeId,
        visited: run.visited,
      });
      if (outcome.status === 'next') {
        moveTo(run, outcome.stepId);
      } else {
        setBranch(null);
      }
    },
    [branch, graph.edges, moveTo, run],
  );

  const exitRun = useCallback(() => {
    setRun(null);
    setBranch(null);
  }, []);

  const cancelBranch = useCallback(() => {
    setBranch(null);
  }, []);

  // 键盘：Delete/Backspace 删除选中、Cmd/Ctrl+Z 撤销、Esc 取消选中 / 退出运行。
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const target = event.target instanceof Element ? event.target : null;
      // 输入控件内的按键交给控件本身处理。
      if (target?.closest('input, textarea, select, [contenteditable="true"]')) return;
      // 任意模态框打开时不响应画布快捷键（不依赖 Modal 的具体实现细节）。
      if (target?.closest('[role="dialog"]') || document.querySelector('[role="dialog"]')) return;

      if (event.key === 'Delete' || event.key === 'Backspace') {
        if (!selection) return;
        event.preventDefault();
        deleteSelection();
        return;
      }
      if (event.key === 'Escape') {
        if (branch) {
          cancelBranch();
        } else if (run) {
          exitRun();
        } else {
          setSelection(null);
        }
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [branch, cancelBranch, deleteSelection, exitRun, run, selection]);

  return (
    <div className="page sop-page">
      <header className="page-header sop-header">
        <div className="page-header-titles">
          <h1>SOP</h1>
          <p>把流程画成可执行的图：节点是步骤，连线决定下一步。</p>
        </div>
        <div className="page-actions">
          {activeSop ? (
            <Button
              size="sm"
              variant="ghost"
              iconLeft={
                <Icon name={inspectorOpen ? 'chevron-right' : 'chevron-left'} size={14} />
              }
              title={inspectorOpen ? '收起右栏（检查器与运行历史）' : '展开右栏'}
              onClick={() => setInspectorOpen((open) => !open)}
            >
              {inspectorOpen ? '收起右栏' : '展开右栏'}
            </Button>
          ) : null}
        </div>
      </header>

      {activeSop && run ? (
        <SopRunBar
          current={currentStep}
          nodes={graph.nodes}
          session={run}
          branch={branch}
          onResult={runResult}
          onChoose={chooseBranch}
          onCancelBranch={cancelBranch}
          onExit={exitRun}
        />
      ) : null}

      <div
        className="sop-body"
        data-inspector={activeSop && inspectorOpen ? 'open' : 'closed'}
      >
        <SopList sops={sops} selectedId={activeSopId} onSelect={selectSop} />

        {activeSop ? (
          <SopCanvas
            sop={activeSop}
            nodes={graph.nodes}
            edges={graph.edges}
            areas={workspace.areas}
            selection={selection}
            onSelect={setSelection}
            run={run}
            onToggleRun={toggleRun}
            onDeleteSelection={deleteSelection}
          />
        ) : (
          <section className="sop-canvas sop-canvas--empty" aria-label="SOP 画布">
            <EmptyState
              icon={<Icon name="workflow" size={22} />}
              title="先创建一个 SOP"
              description="SOP = 可执行的流程图：把步骤画成节点，用连线决定下一步，运行时逐步记录结果。"
            />
          </section>
        )}

        {activeSop && inspectorOpen ? (
          <aside className="sop-side" aria-label="检查器与运行历史">
            <SopInspector
              sop={activeSop}
              nodes={graph.nodes}
              edges={graph.edges}
              selection={selection}
              onSelect={setSelection}
              onDeleteSelection={deleteSelection}
            />
            <RunHistory sopId={activeSop.id} />
          </aside>
        ) : null}
      </div>
    </div>
  );
}
