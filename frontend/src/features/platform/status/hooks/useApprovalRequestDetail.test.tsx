import { renderHook, act, waitFor } from '@testing-library/react';
import { useApprovalRequestDetail } from './useApprovalRequestDetail';
import * as api from '@/features/platform/status/api/approvalsApi';
import type { ApprovalRequestDetail } from '@/features/platform/status/components/approvals/approvalChainTypes';

jest.mock('@/features/platform/status/api/approvalsApi');

const mockedApi = api as jest.Mocked<typeof api>;

const detail = (id: string, currentStep: number): ApprovalRequestDetail => ({
  id,
  status: 'pending',
  current_step: currentStep,
  step_statuses: [],
});

const deferred = <T,>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
};

describe('useApprovalRequestDetail', () => {
  beforeEach(() => jest.clearAllMocks());

  it('re-reads the chain when the list row reports a new current step', async () => {
    mockedApi.fetchApprovalRequestDetail.mockImplementation(async (id: string) => detail(id, 0));
    const { result, rerender } = renderHook(
      ({ step }) => useApprovalRequestDetail('req-1', { currentStep: step, status: 'pending' }),
      { initialProps: { step: 0 } }
    );
    await waitFor(() => expect(result.current.detail?.current_step).toBe(0));

    mockedApi.fetchApprovalRequestDetail.mockImplementation(async (id: string) => detail(id, 1));
    rerender({ step: 1 });

    await waitFor(() => expect(result.current.detail?.current_step).toBe(1));
    expect(mockedApi.fetchApprovalRequestDetail).toHaveBeenCalledTimes(2);
  });

  it('reads nothing while disabled — a collapsed card costs no request', () => {
    renderHook(() => useApprovalRequestDetail('req-1', { enabled: false }));
    expect(mockedApi.fetchApprovalRequestDetail).not.toHaveBeenCalled();
  });

  it('drops a late response for a request the card no longer shows', async () => {
    const first = deferred<ApprovalRequestDetail>();
    mockedApi.fetchApprovalRequestDetail.mockImplementation((id: string) =>
      id === 'req-1' ? first.promise : Promise.resolve(detail('req-2', 0))
    );

    const { result, rerender } = renderHook(({ id }) => useApprovalRequestDetail(id), {
      initialProps: { id: 'req-1' },
    });
    rerender({ id: 'req-2' });
    await waitFor(() => expect(result.current.detail?.id).toBe('req-2'));

    await act(async () => {
      first.resolve(detail('req-1', 0));
    });
    expect(result.current.detail?.id).toBe('req-2');
  });

  it('clears the previous request while the next one loads (C3b1 review F2)', async () => {
    const second = deferred<ApprovalRequestDetail>();
    mockedApi.fetchApprovalRequestDetail.mockImplementation((id: string) =>
      id === 'req-A' ? Promise.resolve(detail('req-A', 0)) : second.promise
    );
    const { result, rerender } = renderHook(({ id }) => useApprovalRequestDetail(id), {
      initialProps: { id: 'req-A' },
    });
    await waitFor(() => expect(result.current.detail?.id).toBe('req-A'));

    rerender({ id: 'req-B' });
    // req-A's chain must be GONE while req-B loads, not merely about to be replaced.
    expect(result.current.detail).toBeNull();
    expect(result.current.loading).toBe(true);

    await act(async () => {
      second.resolve(detail('req-B', 0));
    });
    expect(result.current.detail?.id).toBe('req-B');
  });

  it('clears the previous STEP while the new step loads (C3b1 review F2)', async () => {
    const next = deferred<ApprovalRequestDetail>();
    mockedApi.fetchApprovalRequestDetail
      .mockImplementationOnce(async (id: string) => detail(id, 0))
      .mockImplementationOnce(() => next.promise);
    const { result, rerender } = renderHook(
      ({ step }) => useApprovalRequestDetail('req-1', { currentStep: step, status: 'pending' }),
      { initialProps: { step: 0 } }
    );
    await waitFor(() => expect(result.current.detail?.current_step).toBe(0));

    rerender({ step: 1 });
    expect(result.current.detail).toBeNull();

    await act(async () => {
      next.resolve(detail('req-1', 1));
    });
    expect(result.current.detail?.current_step).toBe(1);
  });

  it('re-reads when only the STATUS moves — a final approval leaves current_step in place (C3b1 review F3)', async () => {
    mockedApi.fetchApprovalRequestDetail.mockImplementation(async (id: string) => detail(id, 2));
    const { rerender } = renderHook(
      ({ status }) => useApprovalRequestDetail('req-1', { currentStep: 2, status }),
      { initialProps: { status: 'pending' } }
    );
    await waitFor(() => expect(mockedApi.fetchApprovalRequestDetail).toHaveBeenCalledTimes(1));

    rerender({ status: 'approved' });

    await waitFor(() => expect(mockedApi.fetchApprovalRequestDetail).toHaveBeenCalledTimes(2));
  });
});
