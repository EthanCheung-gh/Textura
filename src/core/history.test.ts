import { describe, expect, it } from 'vitest';
import { createHistory } from './history';

describe('createHistory', () => {
  it('undo and redo walk the snapshot stack', () => {
    const history = createHistory<number>(80);
    expect(history.canUndo()).toBe(false);
    expect(history.canRedo()).toBe(false);

    history.record(1);
    history.record(2);
    expect(history.canUndo()).toBe(true);

    expect(history.undo(3)).toBe(2);
    expect(history.undo(2)).toBe(1);
    expect(history.undo(1)).toBeNull();
    expect(history.canRedo()).toBe(true);

    expect(history.redo(1)).toBe(2);
    expect(history.redo(2)).toBe(3);
    expect(history.redo(3)).toBeNull();
  });

  it('drops redo history after a new record', () => {
    const history = createHistory<string>(80);
    history.record('a');
    expect(history.undo('b')).toBe('a');
    history.record('a2');
    expect(history.canRedo()).toBe(false);
    expect(history.redo('x')).toBeNull();
  });

  it('caps stored snapshots at the limit', () => {
    const history = createHistory<number>(3);
    history.record(1);
    history.record(2);
    history.record(3);
    history.record(4);
    history.record(5);
    expect(history.size()).toBe(3);
    expect(history.undo(6)).toBe(5);
    expect(history.undo(5)).toBe(4);
    expect(history.undo(4)).toBe(3);
    expect(history.undo(3)).toBeNull();
  });

  it('clear resets both stacks', () => {
    const history = createHistory<number>();
    history.record(1);
    history.undo(2);
    history.clear();
    expect(history.canUndo()).toBe(false);
    expect(history.canRedo()).toBe(false);
  });
});
