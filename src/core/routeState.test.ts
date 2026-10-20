import { describe, expect, it } from 'vitest';
import {
  ROUTE_IDS,
  isRoute,
  itemIdFromSearch,
  resolveInitialRoute,
  routeFromSearch,
  routeFromStored,
  routeWithSearch,
} from './routeState';

describe('routeFromSearch', () => {
  it('accepts every known route and rejects invalid values', () => {
    for (const route of ROUTE_IDS) {
      expect(routeFromSearch(`?route=${route}`)).toBe(route);
    }
    expect(routeFromSearch('?route=OKR')).toBeNull();
    expect(routeFromSearch('?route=nope')).toBeNull();
    expect(routeFromSearch('')).toBeNull();
    expect(routeFromSearch('?item=abc')).toBeNull();
  });

  it('reads route from a query string without the leading question mark', () => {
    expect(routeFromSearch('route=gantt')).toBe('gantt');
  });
});

describe('itemIdFromSearch', () => {
  it('reads and trims the item id', () => {
    expect(itemIdFromSearch('?route=okr&item=obj_activation')).toBe('obj_activation');
    expect(itemIdFromSearch('?item=%20kr_nps%20')).toBe('kr_nps');
    expect(itemIdFromSearch('?item=%20%20')).toBeNull();
    expect(itemIdFromSearch('?route=okr')).toBeNull();
  });
});

describe('resolveInitialRoute', () => {
  it('prefers a valid query route over stored memory', () => {
    expect(resolveInitialRoute('?route=sop', 'gtd')).toBe('sop');
  });

  it('falls back to stored memory when the query is missing or invalid', () => {
    expect(resolveInitialRoute('', 'gtd')).toBe('gtd');
    expect(resolveInitialRoute('?route=invalid', 'gtd')).toBe('gtd');
  });

  it('defaults to dashboard when neither source is valid', () => {
    expect(resolveInitialRoute('', null)).toBe('dashboard');
    expect(resolveInitialRoute('?route=invalid', 'also-invalid')).toBe('dashboard');
  });

  it('validates stored values', () => {
    expect(routeFromStored('gantt')).toBe('gantt');
    expect(routeFromStored('GANTT')).toBeNull();
    expect(routeFromStored(null)).toBeNull();
  });
});

describe('routeWithSearch', () => {
  it('sets route while preserving other parameters', () => {
    expect(routeWithSearch('?item=obj_activation', 'okr')).toBe('?item=obj_activation&route=okr');
    expect(routeWithSearch('?route=gtd&item=kr_nps', 'sop')).toBe('?route=sop&item=kr_nps');
  });

  it('creates a query string from scratch', () => {
    expect(routeWithSearch('', 'dashboard')).toBe('?route=dashboard');
    expect(routeWithSearch('?', 'settings')).toBe('?route=settings');
  });
});

describe('isRoute', () => {
  it('narrows only known route ids', () => {
    expect(isRoute('gantt')).toBe(true);
    expect(isRoute('dashboard')).toBe(true);
    expect(isRoute(undefined)).toBe(false);
    expect(isRoute(1)).toBe(false);
  });
});
