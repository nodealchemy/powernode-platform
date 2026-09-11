import { renderHook, act, waitFor } from '@testing-library/react';
import { useComponentDrawerExtras } from './useComponentDrawerExtras';
import * as api from '@/features/platform/status/api/platformStatusApi';
import type { ComponentEventsResult } from '@/features/platform/status/api/platformStatusApi';
import type {
  ComponentRunbookData,
  Investigation,
  InvestigationsData,
  RemediationRouteData,
} from '@/shared/types/platformStatus';

jest.mock('@/features/platform/status/api/platformStatusApi');

const mockedApi = api as jest.Mocked<typeof api>;

// The drawer's A9 reads, at hook level (C3p2 review R6, R1, R2). The drawer
// suite exercises these through the UI; these examples pin the three
// properties that suite could not see going wrong:
//
//   R6  the initial reads' sequence guard   — a late read for a component left
//   R1  the investigations re-read          — captured when the POST STARTS
//   R2  a failed events read                — reported as failed, not as []

const deferred = <T,>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
};

const runbookFor = (id: string) =>
  ({
    component_status_id: id,
    signal_kind: 'instance.silent',
    runbook: { kind: 'doc', doc: `docs/${id}.md`, path: `docs/${id}.md`, anchor: null },
  }) as unknown as ComponentRunbookData;

const investigationsFor = (id: string): InvestigationsData => ({
  component_status_id: id,
  open: [],
  recent: [],
  daily_cap: 20,
});

const eventsOk = (id: string): ComponentEventsResult => ({
  component_status_id: id,
  events: [],
  pagination: { current_page: 1, per_page: 20, total_count: 0, total_pages: 1 },
});

const renderExtras = (id: string | null) =>
  renderHook(({ id: current }) => useComponentDrawerExtras(current), {
    initialProps: { id },
  });

describe('useComponentDrawerExtras', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedApi.fetchComponentRunbook.mockImplementation(async (id: string) => runbookFor(id));
    mockedApi.fetchRemediationRoute.mockResolvedValue({
      component_status_id: 'x',
      signal_kind: null,
      routed: false,
    } as RemediationRouteData);
    mockedApi.fetchComponentEvents.mockImplementation(async (id: string) => eventsOk(id));
    mockedApi.fetchInvestigations.mockImplementation(async (id: string) => investigationsFor(id));
  });

  it('drops a late initial read for a component the drawer already left (R6)', async () => {
    const alphaRunbook = deferred<ComponentRunbookData>();
    mockedApi.fetchComponentRunbook.mockImplementation((id: string) =>
      id === 'row-A' ? alphaRunbook.promise : Promise.resolve(runbookFor(id))
    );

    const { result, rerender } = renderExtras('row-A');
    rerender({ id: 'row-B' });
    await waitFor(() => expect(result.current.runbook?.component_status_id).toBe('row-B'));

    // Alpha's batch completes only now. None of it may land.
    await act(async () => {
      alphaRunbook.resolve(runbookFor('row-A'));
    });

    expect(result.current.runbook?.component_status_id).toBe('row-B');
    expect(result.current.investigations?.component_status_id).toBe('row-B');
  });

  it('a re-read begun on one component does nothing once the drawer has moved on (R1)', async () => {
    const { result, rerender } = renderExtras('row-A');
    await waitFor(() => expect(result.current.investigations?.component_status_id).toBe('row-A'));

    // The investigation POST starts on alpha…
    const refreshAfterOpen = result.current.beginInvestigationRefresh();
    // …the operator follows an edge to bravo…
    rerender({ id: 'row-B' });
    await waitFor(() => expect(result.current.investigations?.component_status_id).toBe('row-B'));
    const readsBefore = mockedApi.fetchInvestigations.mock.calls.length;

    // …and alpha's POST lands.
    await act(async () => {
      refreshAfterOpen();
      await Promise.resolve();
    });

    expect(result.current.investigations?.component_status_id).toBe('row-B');
    expect(mockedApi.fetchInvestigations.mock.calls.length).toBe(readsBefore);
  });

  it('a re-read begun and landed on the SAME component re-reads it', async () => {
    const { result } = renderExtras('row-A');
    await waitFor(() => expect(result.current.investigations?.open).toEqual([]));

    mockedApi.fetchInvestigations.mockResolvedValue({
      ...investigationsFor('row-A'),
      open: [{ id: 'inv-new' } as unknown as Investigation],
    });
    const refreshAfterOpen = result.current.beginInvestigationRefresh();
    await act(async () => {
      refreshAfterOpen();
    });

    await waitFor(() => expect(result.current.investigations?.open).toHaveLength(1));
  });

  it('reports a failed events read as FAILED, not as an empty history (R2)', async () => {
    mockedApi.fetchComponentEvents.mockRejectedValue(
      new Error('Malformed events response: no events array')
    );
    const { result } = renderExtras('row-A');
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.eventsFailed).toBe(true);
    expect(result.current.events).toEqual([]);
    // Independent doors: the other reads still landed.
    expect(result.current.runbook?.component_status_id).toBe('row-A');
  });

  it('reports a successful empty read as NOT failed, and clears a failure on re-point', async () => {
    mockedApi.fetchComponentEvents.mockImplementation((id: string) =>
      id === 'row-A' ? Promise.reject(new Error('events door down')) : Promise.resolve(eventsOk(id))
    );
    const { result, rerender } = renderExtras('row-A');
    await waitFor(() => expect(result.current.eventsFailed).toBe(true));

    rerender({ id: 'row-B' });
    await waitFor(() => expect(result.current.runbook?.component_status_id).toBe('row-B'));
    expect(result.current.eventsFailed).toBe(false);
  });

  it('reports a failed route read, and clears it when the drawer moves to a component whose route loads (C3p2 review R4)', async () => {
    mockedApi.fetchRemediationRoute.mockImplementation(async (id: string) => {
      if (id === 'row-A') throw new Error('gateway timeout');
      return { component_status_id: id, signal_kind: null, routed: false } as RemediationRouteData;
    });

    const { result, rerender } = renderExtras('row-A');
    await waitFor(() => expect(result.current.routeFailed).toBe(true));
    expect(result.current.route).toBeNull();

    rerender({ id: 'row-B' });
    await waitFor(() => expect(result.current.route?.component_status_id).toBe('row-B'));
    expect(result.current.routeFailed).toBe(false);
  });
});
