/**
 * 列表卡片只读回归：非编辑态不得渲染任何输入控件。
 *
 * 用 `react-dom/server` 的 `renderToStaticMarkup` 渲染真实 `ObjectiveCard`（含子卡片
 * `KrRow`），对最终 markup 做断言 —— 覆盖「组件树里是否还会挂载 input/select/textarea/
 * contenteditable」这一渲染压力问题，而不是只测某个子组件的 props。
 */
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeAll, describe, expect, it } from 'vitest';
import type { Item } from '../../core/model';
import { createSeedWorkspace } from '../../core/fixtures';
import { childrenOf } from '../../core/selectors';
import { useWorkspace } from '../../core/store';
import { ObjectiveCard } from './ObjectiveCard';

const OBJECTIVE_ID = 'obj_activation';

let markup = '';
let keyResults: Item[] = [];

beforeAll(() => {
  const workspace = createSeedWorkspace();
  // 列表页的数据来源就是这个 store；SSR 下组件内部订阅同样需要 ready 的工作区。
  useWorkspace.setState({ workspace, status: 'ready' });

  const objective = workspace.items.find((item) => item.id === OBJECTIVE_ID);
  if (!objective) throw new Error(`seed workspace is missing ${OBJECTIVE_ID}`);
  keyResults = childrenOf(workspace, objective.id).filter((item) => item.kind === 'keyresult');

  markup = renderToStaticMarkup(
    createElement(ObjectiveCard, {
      workspace,
      objective,
      keyResults,
      elapsedPercent: 42,
      density: 'detailed',
      onEdit: () => {},
    }),
  );
});

describe('OKR 列表卡片只读渲染', () => {
  it('seed 目标带有可用于渲染的 KR', () => {
    expect(keyResults.length).toBeGreaterThan(0);
  });

  it('不包含任何输入控件', () => {
    expect(markup).not.toContain('<input');
    expect(markup).not.toContain('<select');
    expect(markup).not.toContain('<textarea');
    expect(markup).not.toContain('contenteditable="true"');
    expect(markup).not.toContain('okr-metric-input');
  });

  it('保留编辑入口（焦点归还依赖 data-edit-objective）与编辑文案', () => {
    expect(markup).toContain(`data-edit-objective="${OBJECTIVE_ID}"`);
    expect(markup).toContain(`aria-label="编辑目标：`);
    expect(markup).toContain('编辑');
  });

  it('保留关键结果结构与新增 KR 的纯文本提示', () => {
    expect(markup).toContain('关键结果');
    expect(markup).toContain('okr-kr-list');
    expect(markup).toContain('在编辑视图新增或调整关键结果');
  });

  it('标题、信心、KR 行均为只读结构', () => {
    expect(markup).toContain('okr-objective-title--readonly');
    expect(markup).toContain('okr-kr-title--readonly');
    expect(markup).toContain('okr-conf--readonly');
    // 只读信心刻度是非交互 span：无 radio、无按钮。
    expect(markup).not.toContain('role="radiogroup"');
    expect(markup).toContain('aria-label="信心 ');
  });

  it('KR 行渲染状态、指标、负责人与执行项摘要', () => {
    expect(markup).toContain('42 → 60 分');
    expect(markup).toContain('林一');
    expect(markup).toContain('执行项 ');
    expect(markup).toContain('已完成 ');
    expect(markup).not.toContain('okr-check');
  });
});
