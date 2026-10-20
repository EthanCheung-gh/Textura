import { describe, expect, it } from 'vitest';
import { createSeedWorkspace } from './fixtures';
import { itemsOfKind, objectivesOfPeriod, sopGraph, edgeTargetsOf, inboxItems, waitingItems } from './selectors';

describe('createSeedWorkspace', () => {
  const ws = createSeedWorkspace();

  it('provides three areas and a fully populated demo', () => {
    expect(ws.areas.map((area) => area.name)).toEqual(['产品', '运营', '个人']);
    expect(ws.items.length).toBeGreaterThanOrEqual(30);
    expect(ws.runs).toHaveLength(3);
  });

  it('contains one objective with three metric KRs in the current quarter', () => {
    const objective = ws.items.find((item) => item.kind === 'objective');
    expect(objective).toBeTruthy();
    const period = objective!.okr!.period;
    expect(objectivesOfPeriod(ws, period)).toHaveLength(1);
    const krs = itemsOfKind(ws, 'keyresult');
    expect(krs).toHaveLength(3);
    expect(krs.map((kr) => kr.okr?.confidence)).toEqual([4, 6, 7]);
    expect(krs.every((kr) => kr.okr?.metric !== undefined)).toBe(true);
  });

  it('builds a seven-step SOP graph with labelled flow edges', () => {
    const sop = ws.items.find((item) => item.kind === 'sop')!;
    const graph = sopGraph(ws, sop.id);
    expect(graph.nodes).toHaveLength(7);
    expect(graph.edges).toHaveLength(7);
    const nodeTypes = new Set(graph.nodes.map((node) => node.sop?.nodeType));
    for (const type of ['start', 'action', 'decision', 'check', 'end'] as const) {
      expect(nodeTypes.has(type)).toBe(true);
    }
    expect(graph.edges.map((edge) => edge.label)).toEqual(
      expect.arrayContaining(['是', '否']),
    );
  });

  it('has a project with six scheduled actions and two dependency edges', () => {
    const project = ws.items.find((item) => item.kind === 'project')!;
    const actions = ws.items.filter((item) => item.kind === 'action' && item.parentId === project.id);
    expect(actions).toHaveLength(6);
    expect(actions.every((action) => action.gantt?.start && action.gantt?.end)).toBe(true);
    const depends = ws.edges.filter((edge) => edge.type === 'depends');
    expect(depends).toHaveLength(2);
    expect(edgeTargetsOf(ws, 'act_build', 'depends').map((item) => item.id)).toEqual(['act_design']);
  });

  it('seeds inbox, next and waiting lists as specified', () => {
    expect(inboxItems(ws)).toHaveLength(6);
    expect(inboxItems(ws).every((item) => item.gtd?.clarified === false)).toBe(true);
    expect(ws.items.filter((item) => item.kind === 'action' && item.status === 'next')).toHaveLength(3);
    expect(waitingItems(ws)).toHaveLength(1);
  });
});
