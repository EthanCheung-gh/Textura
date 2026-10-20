import { describe, expect, it, vi } from 'vitest';
import {
  flushMetricDrafts,
  metricToDraft,
  pendingMetricPatch,
} from './metricDraft';

const BASE = { start: 42, target: 60, current: 47, unit: '分' };

describe('pendingMetricPatch / flushMetricDrafts', () => {
  it('flushes a pending field exactly once with a normalized value', () => {
    const latest = { ...BASE };
    const lastCommitted = metricToDraft(latest);
    const draft = { ...lastCommitted, current: '60' };
    const update = vi.fn();

    const decision = flushMetricDrafts(latest, draft, lastCommitted, update);

    expect(update).toHaveBeenCalledTimes(1);
    expect(update).toHaveBeenCalledWith({ start: 42, target: 60, current: 60, unit: '分' });
    expect(decision?.fields).toEqual(['current']);
    expect(decision?.normalized.current).toBe('60');
  });

  it('merges multiple pending fields into one update and normalizes text', () => {
    const latest = { ...BASE };
    const lastCommitted = metricToDraft(latest);
    const draft = {
      start: '40.0',
      current: '65',
      target: '80',
      unit: ' % ',
    };
    const update = vi.fn();

    const decision = flushMetricDrafts(latest, draft, lastCommitted, update);

    expect(update).toHaveBeenCalledTimes(1);
    expect(update).toHaveBeenCalledWith({ start: 40, target: 80, current: 65, unit: '%' });
    expect(decision?.fields).toEqual(['start', 'current', 'target', 'unit']);
    expect(decision?.normalized).toEqual({
      start: '40',
      current: '65',
      target: '80',
      unit: '%',
    });
  });

  it('ignores empty / invalid numeric fields and still flushes valid ones', () => {
    const latest = { ...BASE };
    const lastCommitted = metricToDraft(latest);
    const invalidOnly = {
      ...lastCommitted,
      start: '',
      current: 'abc',
      target: '',
    };
    const noopUpdate = vi.fn();
    expect(flushMetricDrafts(latest, invalidOnly, lastCommitted, noopUpdate)).toBeNull();
    expect(noopUpdate).not.toHaveBeenCalled();

    const mixed = { ...lastCommitted, current: '70', target: '' };
    const update = vi.fn();
    const decision = flushMetricDrafts(latest, mixed, lastCommitted, update);
    expect(update).toHaveBeenCalledTimes(1);
    expect(update).toHaveBeenCalledWith({ start: 42, target: 60, current: 70, unit: '分' });
    expect(decision?.fields).toEqual(['current']);
  });

  it('does not overwrite an external store change with a stale draft (undo safety)', () => {
    const latest = { ...BASE, current: 47 };
    const draft = { ...metricToDraft(latest), current: '50' };
    const lastCommitted = { ...metricToDraft(latest), current: '50' };
    const update = vi.fn();

    expect(pendingMetricPatch(latest, draft, lastCommitted)).toBeNull();
    expect(flushMetricDrafts(latest, draft, lastCommitted, update)).toBeNull();
    expect(update).not.toHaveBeenCalled();
  });

  it('allows clearing the text unit but skips unchanged values', () => {
    const latest = { ...BASE };
    const lastCommitted = metricToDraft(latest);
    const update = vi.fn();

    const decision = flushMetricDrafts(
      latest,
      { ...lastCommitted, unit: '  ' },
      lastCommitted,
      update,
    );
    expect(update).toHaveBeenCalledTimes(1);
    expect(update).toHaveBeenCalledWith({ start: 42, target: 60, current: 47, unit: '' });
    expect(decision?.fields).toEqual(['unit']);

    const noop = vi.fn();
    flushMetricDrafts(latest, { ...lastCommitted, unit: '分' }, lastCommitted, noop);
    expect(noop).not.toHaveBeenCalled();
  });

  it('flushes a flat-range target edit (target === start) as a valid numeric change', () => {
    const latest = { ...BASE };
    const lastCommitted = metricToDraft(latest);
    const update = vi.fn();

    const decision = flushMetricDrafts(
      latest,
      { ...lastCommitted, target: '42' },
      lastCommitted,
      update,
    );

    expect(update).toHaveBeenCalledTimes(1);
    expect(update).toHaveBeenCalledWith({ start: 42, target: 42, current: 47, unit: '分' });
    expect(decision?.fields).toEqual(['target']);
  });
});
