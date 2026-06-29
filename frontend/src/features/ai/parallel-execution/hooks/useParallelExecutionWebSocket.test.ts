import { renderHook } from '@testing-library/react';
import { useParallelExecutionWebSocket } from './useParallelExecutionWebSocket';
import type { ParallelExecutionUpdate } from '../types';

// Capture how the hook talks to the shared WebSocket singleton.
const mockUnsubscribe = jest.fn();
const mockSubscribe = jest.fn();
let mockIsConnected = true;

jest.mock('@/shared/hooks/useWebSocket', () => ({
  useWebSocket: () => ({
    isConnected: mockIsConnected,
    subscribe: mockSubscribe,
  }),
}));

describe('useParallelExecutionWebSocket', () => {
  beforeEach(() => {
    // jest.config has resetMocks:true, so re-establish behaviour each test.
    mockIsConnected = true;
    mockSubscribe.mockReturnValue(mockUnsubscribe);
  });

  it('routes through the shared singleton with the worktree_session channel params', () => {
    const { result } = renderHook(() =>
      useParallelExecutionWebSocket({ sessionId: 'sess-1', enabled: true }),
    );

    expect(mockSubscribe).toHaveBeenCalledTimes(1);
    expect(mockSubscribe).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: 'AiOrchestrationChannel',
        params: { type: 'worktree_session', id: 'sess-1' },
      }),
    );
    expect(result.current.isConnected).toBe(true);
  });

  it('never reads the auth token from localStorage (token lives in Redux)', () => {
    const getItemSpy = jest.spyOn(Storage.prototype, 'getItem');

    renderHook(() => useParallelExecutionWebSocket({ sessionId: 'sess-1', enabled: true }));

    expect(getItemSpy).not.toHaveBeenCalledWith('auth_token');
    getItemSpy.mockRestore();
  });

  it('forwards routed messages to onUpdate', () => {
    const onUpdate = jest.fn();
    renderHook(() => useParallelExecutionWebSocket({ sessionId: 'sess-1', enabled: true, onUpdate }));

    const subscription = mockSubscribe.mock.calls[0][0] as unknown as {
      onMessage: (data: unknown) => void;
    };
    const update: ParallelExecutionUpdate = {
      event: 'worktree_session.updated',
      resource_type: 'worktree_session',
      resource_id: 'sess-1',
      payload: {},
      timestamp: '2026-06-29T00:00:00Z',
    };
    subscription.onMessage(update);

    expect(onUpdate).toHaveBeenCalledWith(update);
  });

  it('does not subscribe when disabled, sessionless, or the socket is down', () => {
    renderHook(() => useParallelExecutionWebSocket({ sessionId: 'sess-1', enabled: false }));
    expect(mockSubscribe).not.toHaveBeenCalled();

    renderHook(() => useParallelExecutionWebSocket({ enabled: true }));
    expect(mockSubscribe).not.toHaveBeenCalled();

    mockIsConnected = false;
    const { result } = renderHook(() =>
      useParallelExecutionWebSocket({ sessionId: 'sess-1', enabled: true }),
    );
    expect(mockSubscribe).not.toHaveBeenCalled();
    expect(result.current.isConnected).toBe(false);
  });

  it('unsubscribes on unmount', () => {
    const { unmount } = renderHook(() =>
      useParallelExecutionWebSocket({ sessionId: 'sess-1', enabled: true }),
    );
    unmount();
    expect(mockUnsubscribe).toHaveBeenCalledTimes(1);
  });
});
