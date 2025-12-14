import { renderHook, act } from '@testing-library/react';
import { useAnalyticsWebSocket } from './useAnalyticsWebSocket';

// Mock the useWebSocket hook
interface SubscribeOptions {
  channel: string;
  params: Record<string, string>;
  onMessage: (data: unknown) => void;
  onError: (error: string) => void;
}

const mockSubscribe = jest.fn<() => void, [SubscribeOptions]>(() => jest.fn());
const mockSendMessage = jest.fn(() => Promise.resolve(true));
let mockIsConnected = true;
let mockError: string | null = null;

// Helper to get the subscribe call options safely
const getSubscribeOptions = () => {
  const call = mockSubscribe.mock.calls[0];
  if (!call) throw new Error('mockSubscribe was not called');
  return call[0];
};

jest.mock('./useWebSocket', () => ({
  useWebSocket: () => ({
    isConnected: mockIsConnected,
    subscribe: mockSubscribe,
    sendMessage: mockSendMessage,
    error: mockError,
  }),
}));

describe('useAnalyticsWebSocket', () => {
  const mockAccountId = 'account-123';

  beforeEach(() => {
    jest.clearAllMocks();
    mockIsConnected = true;
    mockError = null;
  });

  describe('subscription', () => {
    it('subscribes to AnalyticsChannel when connected with accountId', () => {
      renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
        })
      );

      expect(mockSubscribe).toHaveBeenCalledWith({
        channel: 'AnalyticsChannel',
        params: { account_id: mockAccountId },
        onMessage: expect.any(Function),
        onError: expect.any(Function),
      });
    });

    it('does not subscribe when accountId is not provided', () => {
      renderHook(() =>
        useAnalyticsWebSocket({
          accountId: undefined,
        })
      );

      expect(mockSubscribe).not.toHaveBeenCalled();
    });

    it('does not subscribe when accountId is empty string', () => {
      renderHook(() =>
        useAnalyticsWebSocket({
          accountId: '',
        })
      );

      expect(mockSubscribe).not.toHaveBeenCalled();
    });

    it('unsubscribes on unmount', () => {
      const mockUnsubscribe = jest.fn();
      mockSubscribe.mockReturnValue(mockUnsubscribe);

      const { unmount } = renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
        })
      );

      unmount();

      expect(mockUnsubscribe).toHaveBeenCalled();
    });

    it('resubscribes when accountId changes', () => {
      const mockUnsubscribe = jest.fn();
      mockSubscribe.mockReturnValue(mockUnsubscribe);

      const { rerender } = renderHook(
        ({ accountId }) => useAnalyticsWebSocket({ accountId }),
        { initialProps: { accountId: mockAccountId } }
      );

      expect(mockSubscribe).toHaveBeenCalledTimes(1);

      rerender({ accountId: 'new-account-456' });

      expect(mockUnsubscribe).toHaveBeenCalled();
      expect(mockSubscribe).toHaveBeenCalledTimes(2);
      expect(mockSubscribe).toHaveBeenLastCalledWith({
        channel: 'AnalyticsChannel',
        params: { account_id: 'new-account-456' },
        onMessage: expect.any(Function),
        onError: expect.any(Function),
      });
    });
  });

  describe('message handling', () => {
    it('calls onAnalyticsUpdate when analytics_update received', () => {
      const onAnalyticsUpdate = jest.fn();

      renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
          onAnalyticsUpdate,
        })
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockData = {
        totalRevenue: 15000,
        activeSubscriptions: 150,
        churnRate: 2.5,
      };

      act(() => {
        onMessage({
          type: 'analytics_update',
          data: mockData,
        });
      });

      expect(onAnalyticsUpdate).toHaveBeenCalledWith(mockData);
    });

    it('calls onError when error message received', () => {
      const onError = jest.fn();

      renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
          onError,
        })
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({
          type: 'error',
          message: 'Analytics fetch failed',
        });
      });

      expect(onError).toHaveBeenCalledWith('Analytics fetch failed');
    });

    it('uses default error message when not provided', () => {
      const onError = jest.fn();

      renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
          onError,
        })
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({
          type: 'error',
        });
      });

      expect(onError).toHaveBeenCalledWith('Analytics error');
    });

    it('ignores messages without type field', () => {
      const onAnalyticsUpdate = jest.fn();
      const onError = jest.fn();

      renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
          onAnalyticsUpdate,
          onError,
        })
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({ data: 'some data' });
        onMessage(null);
        onMessage(undefined);
        onMessage('string');
      });

      expect(onAnalyticsUpdate).not.toHaveBeenCalled();
      expect(onError).not.toHaveBeenCalled();
    });

    it('does not call onAnalyticsUpdate when data is missing', () => {
      const onAnalyticsUpdate = jest.fn();

      renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
          onAnalyticsUpdate,
        })
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({
          type: 'analytics_update',
          // no data field
        });
      });

      expect(onAnalyticsUpdate).not.toHaveBeenCalled();
    });
  });

  describe('requestAnalyticsUpdate', () => {
    it('sends request_analytics message when connected', async () => {
      const { result } = renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
        })
      );

      await act(async () => {
        await result.current.requestAnalyticsUpdate();
      });

      expect(mockSendMessage).toHaveBeenCalledWith(
        'AnalyticsChannel',
        'request_analytics'
      );
    });

    it('does not send message when not connected', async () => {
      mockIsConnected = false;

      const { result } = renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
        })
      );

      await act(async () => {
        await result.current.requestAnalyticsUpdate();
      });

      expect(mockSendMessage).not.toHaveBeenCalled();
    });
  });

  describe('error handling', () => {
    it('calls onError when channel error occurs', () => {
      const onError = jest.fn();

      renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
          onError,
        })
      );

      const subscribeOptions = getSubscribeOptions();
      const handleError = subscribeOptions.onError;

      act(() => {
        handleError('Channel disconnected');
      });

      expect(onError).toHaveBeenCalledWith('Channel disconnected');
    });
  });

  describe('return values', () => {
    it('returns isConnected state', () => {
      const { result } = renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
        })
      );

      expect(result.current.isConnected).toBe(true);
    });

    it('returns requestAnalyticsUpdate function', () => {
      const { result } = renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
        })
      );

      expect(typeof result.current.requestAnalyticsUpdate).toBe('function');
    });

    it('returns error state', () => {
      mockError = 'Connection lost';

      const { result } = renderHook(() =>
        useAnalyticsWebSocket({
          accountId: mockAccountId,
        })
      );

      expect(result.current.error).toBe('Connection lost');
    });
  });
});
