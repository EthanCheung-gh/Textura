import { describe, expect, it } from 'vitest';
import { WORKSPACE_VERSION } from '../../core/model';
import { isWorkspaceShape, parseImportText, summarizeImport } from './importValidation';

const validWorkspace = {
  version: WORKSPACE_VERSION,
  items: [
    {
      id: 'a',
      kind: 'action',
      title: '任务',
      notes: '',
      parentId: null,
      order: 0,
      status: 'next',
      tags: [],
      areaId: null,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
      completedAt: null,
    },
  ],
  edges: [{ id: 'e', from: 'a', to: 'a', type: 'related', label: '' }],
  areas: [{ id: 'area', name: '产品', color: '#C0663A', order: 0 }],
  runs: [
    { id: 'r', sopId: 'sop', stepId: 'step', at: '2026-01-01T00:00:00.000Z', result: 'pass', note: '' },
  ],
  updatedAt: '2026-01-01T00:00:00.000Z',
};

describe('isWorkspaceShape', () => {
  it('accepts a workspace-like object', () => {
    expect(isWorkspaceShape(validWorkspace)).toBe(true);
  });

  it('accepts legacy files with only items and no version', () => {
    expect(isWorkspaceShape({ items: [] })).toBe(true);
  });

  it('rejects arbitrary JSON and malformed collection fields', () => {
    expect(isWorkspaceShape({ foo: 1 })).toBe(false);
    expect(isWorkspaceShape(null)).toBe(false);
    expect(isWorkspaceShape([])).toBe(false);
    expect(isWorkspaceShape({ items: 'nope' })).toBe(false);
    expect(isWorkspaceShape({ version: '1', items: [] })).toBe(false);
    expect(isWorkspaceShape({ items: [], updatedAt: 123 })).toBe(false);
  });
});

describe('parseImportText', () => {
  it('parses and migrates a valid workspace', () => {
    const parsed = parseImportText(JSON.stringify(validWorkspace));
    expect(parsed.items.map((item) => item.id)).toEqual(['a']);
    expect(parsed.areas.map((area) => area.name)).toEqual(['产品']);
    expect(parsed.version).toBe(WORKSPACE_VERSION);
  });

  it('rejects invalid JSON with a readable message', () => {
    expect(() => parseImportText('{not json')).toThrow('文件不是合法的 JSON');
  });

  it('rejects look-alike JSON before it becomes an empty workspace', () => {
    expect(() => parseImportText('{"foo":1}')).toThrow(/不是 Textura 工作区文件/);
    expect(() => parseImportText('{"items":{}}')).toThrow(/不是 Textura 工作区文件/);
  });

  it('rejects unsupported versions', () => {
    expect(() =>
      parseImportText(JSON.stringify({ ...validWorkspace, version: WORKSPACE_VERSION + 1 })),
    ).toThrow(/版本/);
  });
});

describe('summarizeImport', () => {
  it('counts collections for the confirmation dialog', () => {
    const parsed = parseImportText(JSON.stringify(validWorkspace));
    expect(summarizeImport(parsed)).toEqual({
      items: 1,
      areas: 1,
      edges: 1,
      runs: 1,
      version: WORKSPACE_VERSION,
    });
  });
});
