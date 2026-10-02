import type { ApprovalRequest } from '../types/approval';
import {
  DEFAULT_FILTERS,
  NO_SEVERITY,
  applyQueueFilters,
  approvalSeverity,
  effectiveFilters,
  queueFacets,
  readQueueFilters,
  writeQueueFilters,
} from './queueFilters';

const req = (id: string, over: Partial<ApprovalRequest> = {}): ApprovalRequest => ({
  id,
  request_id: id,
  status: 'pending',
  request_data: {},
  created_at: '2026-09-20T00:00:00Z',
  ...over,
});

describe('approvalSeverity', () => {
  it('reads the payload severity, lower-cased, and never invents one', () => {
    expect(approvalSeverity(req('a', { request_data: { payload: { signal_severity: ' HIGH ' } } }))).toBe('high');
    expect(approvalSeverity(req('b', { request_data: { severity: 'low' } }))).toBe('low');
    expect(approvalSeverity(req('c'))).toBe(NO_SEVERITY);
    expect(approvalSeverity(req('d', { request_data: { payload: { signal_severity: 3 } } }))).toBe(NO_SEVERITY);
  });
});

describe('queueFacets', () => {
  it('counts categories most-first and orders severities worst-first with "none" last', () => {
    const facets = queueFacets([
      req('1', { action_category: 'b.x', request_data: { payload: { signal_severity: 'low' } } }),
      req('2', { action_category: 'a.y', request_data: { payload: { signal_severity: 'critical' } } }),
      req('3', { action_category: 'a.y' }),
      req('4', { action_type: 'a.y', requires_human_session: true }),
    ]);

    expect(facets.categories).toEqual([
      { value: 'a.y', count: 3 },
      { value: 'b.x', count: 1 },
    ]);
    expect(facets.severities.map((f) => f.value)).toEqual(['critical', 'low', NO_SEVERITY]);
    expect(facets.needsPerson).toBe(1);
  });
});

describe('effectiveFilters', () => {
  it('drops a facet value the queue no longer holds, and a needs-a-person filter with nothing to show', () => {
    const facets = queueFacets([req('1', { action_category: 'a.y' })]);

    expect(
      effectiveFilters({ ...DEFAULT_FILTERS, category: 'gone', severity: 'high', needsPerson: true }, facets)
    ).toEqual(DEFAULT_FILTERS);
  });
});

describe('applyQueueFilters', () => {
  const rows = [
    req('old', { action_category: 'a', created_at: '2026-09-20T00:00:00Z' }),
    req('mid', { action_category: 'b', created_at: '2026-09-21T00:00:00Z' }),
    req('new', { action_category: 'a', created_at: '2026-09-22T00:00:00Z' }),
  ];

  it('keeps the server order for oldest first and reverses it for newest first', () => {
    expect(applyQueueFilters(rows, DEFAULT_FILTERS).map((r) => r.id)).toEqual(['old', 'mid', 'new']);
    expect(applyQueueFilters(rows, { ...DEFAULT_FILTERS, order: 'newest' }).map((r) => r.id)).toEqual([
      'new',
      'mid',
      'old',
    ]);
  });

  it('pins a request that needs a person above the rest, keeping each group in the chosen order', () => {
    const mixed = [
      req('a', { created_at: '2026-09-20T00:00:00Z' }),
      req('b', { created_at: '2026-09-21T00:00:00Z', requires_human_session: true }),
      req('c', { created_at: '2026-09-22T00:00:00Z' }),
      req('d', { created_at: '2026-09-23T00:00:00Z', requires_human_session: true }),
    ];

    expect(applyQueueFilters(mixed, DEFAULT_FILTERS).map((r) => r.id)).toEqual(['b', 'd', 'a', 'c']);
    expect(applyQueueFilters(mixed, { ...DEFAULT_FILTERS, order: 'newest' }).map((r) => r.id)).toEqual([
      'd',
      'b',
      'c',
      'a',
    ]);
  });

  it('breaks a created_at tie by the server position, later first', () => {
    const tied = [req('x', { created_at: '2026-09-20T00:00:00Z' }), req('y', { created_at: '2026-09-20T00:00:00Z' })];

    expect(applyQueueFilters(tied, { ...DEFAULT_FILTERS, order: 'newest' }).map((r) => r.id)).toEqual(['y', 'x']);
  });

  it('never filters away a pinned request (the deep-linked one, or the one a push announced)', () => {
    const view = applyQueueFilters(rows, { ...DEFAULT_FILTERS, category: 'a' }, ['mid']);

    expect(view.map((r) => r.id)).toEqual(['old', 'mid', 'new']);
  });
});

describe('the URL', () => {
  it('writes only what differs from the default and keeps the deep link and anything else', () => {
    const next = writeQueueFilters(new URLSearchParams('request=r1&tab=queue'), {
      category: 'a.y',
      severity: '',
      needsPerson: true,
      order: 'newest',
    });

    expect(next.get('request')).toBe('r1');
    expect(next.get('tab')).toBe('queue');
    expect(next.get('category')).toBe('a.y');
    expect(next.get('needs_person')).toBe('1');
    expect(next.get('order')).toBe('newest');
    expect(next.has('severity')).toBe(false);
  });

  it('round-trips, and clears a filter by omitting it', () => {
    const filters = { category: 'a.y', severity: 'high', needsPerson: true, order: 'newest' as const };

    expect(readQueueFilters(writeQueueFilters(new URLSearchParams(), filters))).toEqual(filters);
    expect(writeQueueFilters(new URLSearchParams('category=a.y'), DEFAULT_FILTERS).toString()).toBe('');
  });

  it('treats an unknown order as the default', () => {
    expect(readQueueFilters(new URLSearchParams('order=sideways')).order).toBe('oldest');
  });
});
