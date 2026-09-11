import React from 'react';
import { renderHook, act, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useLiveApprovalQueue, isApprovalNotification, APPROVAL_POLL_MS } from './useLiveApprovalQueue';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { usePolling } from '@/shared/hooks/usePolling';
import { featureRegistry } from '@/shared/services/featureRegistry';

// C3b oracle: "a new approval appears without reload".
//
// Like the status page's churn guard, this does NOT mock `usePageWebSocket`:
// the notification is delivered through the REAL hook's message handler, so
// the channel key, the message type and the metadata discriminator are all
// exercised as production wires them. Only the socket underneath is faked.

const mockGet = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  apiClient: { get: (...args: unknown[]) => mockGet(...args), post: jest.fn() },
  default: { get: (...args: unknown[]) => mockGet(...args), post: jest.fn() },
}));
jest.mock('@/shared/hooks/useWebSocket');
jest.mock('@/shared/hooks/usePolling', () => ({ usePolling: jest.fn() }));
jest.mock('react-redux', () => ({
  ...jest.requireActual('react-redux'),
  useSelector: (selector: (state: unknown) => unknown) =>
    selector({ auth: { user: { id: 'u-1', account: { id: 'acct-1' } } } }),
}));

const mockedWebSocket = useWebSocket as jest.MockedFunction<typeof useWebSocket>;
const mockedPolling = usePolling as jest.MockedFunction<typeof usePolling>;

interface CapturedSubscription {
  channel: string;
  onMessage: (data: unknown) => void;
}
let subscriptions: CapturedSubscription[];

const row = (id: string) => ({
  id,
  request_id: id,
  status: 'pending',
  request_data: {},
  created_at: '2026-09-10T00:00:00Z',
  current_step: 0,
  total_steps: 1,
});

const approvalNotification = (approvalRequestId: string) => ({
  type: 'new_notification',
  notification: {
    id: `n-${approvalRequestId}`,
    // A custom content handler may choose any type; the discriminator is the
    // provenance key, so the type here is deliberately not the default one.
    notification_type: 'fleet_signal_decision',
    metadata: { approval_request_id: approvalRequestId, current_step: 0, total_steps: 1 },
  },
});

const makeWrapper = () => {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const Wrapper = ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
  return Wrapper;
};

/** Deliver a message on the LATEST NotificationChannel subscription, as ActionCable would. */
const deliver = (data: unknown) => {
  const onChannel = subscriptions.filter((sub) => sub.channel === 'NotificationChannel');
  const latest = onChannel[onChannel.length - 1];
  if (!latest) throw new Error('no NotificationChannel subscription was made');
  act(() => latest.onMessage(data));
};

const ids = (data: unknown) => (data as { id: string }[] | undefined)?.map((r) => r.id);

describe('useLiveApprovalQueue', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    subscriptions = [];
    mockedWebSocket.mockReturnValue({
      isConnected: true,
      error: null,
      subscribe: jest.fn((sub: CapturedSubscription) => {
        subscriptions.push(sub);
        return jest.fn();
      }),
    } as unknown as ReturnType<typeof useWebSocket>);
  });

  it('a new approval appears without reload when its notification arrives', async () => {
    mockGet.mockResolvedValue({ data: { data: [row('req-1')] } });
    const { result } = renderHook(() => useLiveApprovalQueue(), { wrapper: makeWrapper() });
    await waitFor(() => expect(ids(result.current.data)).toEqual(['req-1']));
    expect(subscriptions.some((sub) => sub.channel === 'NotificationChannel')).toBe(true);

    mockGet.mockResolvedValue({ data: { data: [row('req-1'), row('req-2')] } });
    deliver(approvalNotification('req-2'));

    await waitFor(() => expect(ids(result.current.data)).toEqual(['req-1', 'req-2']));
    expect(result.current.lastPushAt).not.toBeNull();
  });

  it('ignores an approval-shaped message on ANOTHER channel of the same page type (C3b1 review F4)', async () => {
    // An extension channel registered for the 'dashboard' page type rides the
    // same onDataUpdate. Without the channel check, its approval-shaped message
    // would refetch the queue and claim a push.
    featureRegistry.registerChannels('probe', [
      { key: 'probeExt', channelName: 'ProbeExtChannel', defaultPageTypes: ['dashboard'] } as never,
    ]);
    try {
      mockGet.mockResolvedValue({ data: { data: [row('req-1')] } });
      const { result } = renderHook(() => useLiveApprovalQueue(), { wrapper: makeWrapper() });
      await waitFor(() => expect(ids(result.current.data)).toEqual(['req-1']));

      const extension = subscriptions.filter((sub) => sub.channel === 'ProbeExtChannel').pop();
      expect(extension).toBeDefined();
      const readsBefore = mockGet.mock.calls.length;

      act(() => extension!.onMessage(approvalNotification('req-x')));
      await act(async () => {
        await Promise.resolve();
      });

      expect(mockGet.mock.calls.length).toBe(readsBefore);
      expect(result.current.lastPushAt).toBeNull();
    } finally {
      featureRegistry.clear();
    }
  });

  it('reads once on reconnect, so a push lost while the cable was down does not wait for the poll (C3b1 review F5)', async () => {
    let connected = true;
    const subscribe = jest.fn((sub: CapturedSubscription) => {
      subscriptions.push(sub);
      return jest.fn();
    });
    mockedWebSocket.mockImplementation(
      () => ({ isConnected: connected, error: null, subscribe }) as unknown as ReturnType<typeof useWebSocket>
    );
    mockGet.mockResolvedValue({ data: { data: [row('req-1')] } });
    const { result, rerender } = renderHook(() => useLiveApprovalQueue(), { wrapper: makeWrapper() });
    await waitFor(() => expect(ids(result.current.data)).toEqual(['req-1']));

    connected = false;
    rerender();
    await act(async () => {
      await Promise.resolve();
    });
    const readsWhileDown = mockGet.mock.calls.length;

    mockGet.mockResolvedValue({ data: { data: [row('req-1'), row('req-raised-during-outage')] } });
    connected = true;
    rerender();

    await waitFor(() => expect(mockGet.mock.calls.length).toBeGreaterThan(readsWhileDown));
    await waitFor(() =>
      expect(ids(result.current.data)).toEqual(['req-1', 'req-raised-during-outage'])
    );
  });

  it('ignores notifications that are not about an approval', async () => {
    mockGet.mockResolvedValue({ data: { data: [row('req-1')] } });
    const { result } = renderHook(() => useLiveApprovalQueue(), { wrapper: makeWrapper() });
    await waitFor(() => expect(ids(result.current.data)).toEqual(['req-1']));
    const readsBefore = mockGet.mock.calls.length;

    deliver({ type: 'new_notification', notification: { id: 'n-x', metadata: {} } });
    deliver({ type: 'notification_read', notification_id: 'n-x' });
    await act(async () => {
      await Promise.resolve();
    });

    expect(mockGet.mock.calls.length).toBe(readsBefore);
    expect(result.current.lastPushAt).toBeNull();
  });

  it('polls ALWAYS — the push reaches only the step approvers, never other deciders or the expiry sweep', async () => {
    mockGet.mockResolvedValue({ data: { data: [row('req-1')] } });
    renderHook(() => useLiveApprovalQueue(), { wrapper: makeWrapper() });
    await waitFor(() => expect(mockGet).toHaveBeenCalled());

    // Registered at the declared interval and never switched off, although the
    // socket in this test is connected.
    const [pollFn, interval, options] = mockedPolling.mock.calls[mockedPolling.mock.calls.length - 1];
    expect(interval).toBe(APPROVAL_POLL_MS);
    expect(options?.enabled).not.toBe(false);

    const readsBefore = mockGet.mock.calls.length;
    await act(async () => {
      pollFn();
      await Promise.resolve();
    });
    await waitFor(() => expect(mockGet.mock.calls.length).toBeGreaterThan(readsBefore));
  });
});

describe('isApprovalNotification', () => {
  it.each([
    ['an approval notification', approvalNotification('req-9'), true],
    ['no metadata', { type: 'new_notification', notification: { id: 'n' } }, false],
    ['an empty id', { notification: { metadata: { approval_request_id: '' } } }, false],
    ['a non-string id', { notification: { metadata: { approval_request_id: 42 } } }, false],
    ['no notification', { type: 'new_notification' }, false],
    ['null', null, false],
  ] as const)('%s → %p', (_label, payload, expected) => {
    expect(isApprovalNotification(payload)).toBe(expected);
  });
});
