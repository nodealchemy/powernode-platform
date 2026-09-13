import { renderHook, act, waitFor } from '@testing-library/react';
import { useComponentStatusDetail } from './useComponentStatusDetail';
import * as api from '@/features/platform/status/api/platformStatusApi';
import type {
  ComponentStatusDetail,
  ComponentStatusImpactData,
  ComponentStatusShowData,
} from '@/shared/types/platformStatus';

jest.mock('@/features/platform/status/api/platformStatusApi');

const mockedApi = api as jest.Mocked<typeof api>;

// useComponentStatusDetail — the C3 review's two HIGH findings, each with its
// own arm (F1, F2), both through re-pointing the drawer from one component to
// another, which is what the drawer's "follow an edge" affordance does.
//
// Deferred promises rather than resolved mocks: the defects live entirely in
// the WINDOW between a re-point and a response, and a mock that resolves
// immediately closes that window before the assertion can see it.

const deferred = <T,>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
};

const detailFor = (id: string, condition: string): ComponentStatusDetail =>
  ({
    id,
    component_kind: 'node_instance',
    component_ref: id,
    display_name: id,
    verdict: 'degraded',
    conditions: [
      {
        type: condition,
        status: false,
        reason: 'Probe',
        message: null,
        severity: 'degraded',
        evidence: {},
        observed_generation: null,
        observed_at: null,
        last_transition_at: null,
      },
    ],
    // The dangerous half: an action whose path names THIS component's door.
    actions: [
      {
        key: 'reap',
        label: 'Reap',
        method: 'POST',
        path: `/system/instances/${id}/reap`,
        permission: 'system.instances.destroy',
        destructive: true,
      },
    ],
  }) as unknown as ComponentStatusDetail;

const show = (id: string, condition: string): ComponentStatusShowData => ({
  component_status: detailFor(id, condition),
  impact: { count: 0, worst_verdict: 'ok', components: [] },
});

describe('useComponentStatusDetail', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedApi.fetchComponentImpact.mockResolvedValue({} as ComponentStatusImpactData);
  });

  it('F1: re-pointing to another component clears the previous body BEFORE the new read lands', async () => {
    const bravo = deferred<ComponentStatusShowData>();
    mockedApi.fetchComponentStatus.mockImplementation((id: string) =>
      id === 'alpha' ? Promise.resolve(show('alpha', 'AlphaCondition')) : bravo.promise
    );

    const { result, rerender } = renderHook(({ id }) => useComponentStatusDetail(id), {
      initialProps: { id: 'alpha' as string | null },
    });
    await waitFor(() => expect(result.current.detail?.id).toBe('alpha'));

    // Re-point at bravo; bravo's read is still in flight.
    rerender({ id: 'bravo' });

    // Alpha's conditions and — the safety half — alpha's action paths must be
    // GONE, not merely about to be replaced.
    expect(result.current.detail).toBeNull();
    expect(result.current.loading).toBe(true);

    await act(async () => {
      bravo.resolve(show('bravo', 'BravoCondition'));
    });
    expect(result.current.detail?.id).toBe('bravo');
    expect(result.current.detail?.actions[0].path).toBe('/system/instances/bravo/reap');
  });

  it('F2: a late response for a component already left is DROPPED, not applied', async () => {
    const alpha = deferred<ComponentStatusShowData>();
    mockedApi.fetchComponentStatus.mockImplementation((id: string) =>
      id === 'alpha' ? alpha.promise : Promise.resolve(show('bravo', 'BravoCondition'))
    );

    const { result, rerender } = renderHook(({ id }) => useComponentStatusDetail(id), {
      initialProps: { id: 'alpha' as string | null },
    });

    // Leave alpha before its read returns; bravo's lands first.
    rerender({ id: 'bravo' });
    await waitFor(() => expect(result.current.detail?.id).toBe('bravo'));

    // Now alpha's late response arrives. It must lose.
    await act(async () => {
      alpha.resolve(show('alpha', 'AlphaCondition'));
    });

    expect(result.current.detail?.id).toBe('bravo');
    expect(result.current.detail?.conditions[0].type).toBe('BravoCondition');
    expect(result.current.detail?.actions[0].path).toBe('/system/instances/bravo/reap');
  });

  it('closing the drawer while a read is in flight keeps it closed', async () => {
    const alpha = deferred<ComponentStatusShowData>();
    mockedApi.fetchComponentStatus.mockReturnValue(alpha.promise);

    const { result, rerender } = renderHook(({ id }) => useComponentStatusDetail(id), {
      initialProps: { id: 'alpha' as string | null },
    });
    rerender({ id: null });

    await act(async () => {
      alpha.resolve(show('alpha', 'AlphaCondition'));
    });

    expect(result.current.detail).toBeNull();
    expect(result.current.loading).toBe(false);
  });

  it('a late FAILURE for a component already left does not paint an error over the current one', async () => {
    const alpha = deferred<ComponentStatusShowData>();
    let rejectAlpha!: (e: Error) => void;
    const alphaFailing = new Promise<ComponentStatusShowData>((_, reject) => {
      rejectAlpha = reject;
    });
    void alpha;
    mockedApi.fetchComponentStatus.mockImplementation((id: string) =>
      id === 'alpha' ? alphaFailing : Promise.resolve(show('bravo', 'BravoCondition'))
    );

    const { result, rerender } = renderHook(({ id }) => useComponentStatusDetail(id), {
      initialProps: { id: 'alpha' as string | null },
    });
    rerender({ id: 'bravo' });
    await waitFor(() => expect(result.current.detail?.id).toBe('bravo'));

    await act(async () => {
      rejectAlpha(new Error('alpha timed out'));
    });

    expect(result.current.error).toBeNull();
    expect(result.current.detail?.id).toBe('bravo');
  });
});
