import { renderHook, act } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore, combineReducers } from '@reduxjs/toolkit';
import type { ReactNode } from 'react';
import { createElement } from 'react';
import { useNotificationWebSocket, WebSocketNotification } from './useNotificationWebSocket';
import authReducer from '../services/slices/authSlice';
import uiReducer from '../services/slices/uiSlice';

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

jest.mock('./useWebSocket', () => ({
  useWebSocket: () => ({
    isConnected: mockIsConnected,
    subscribe: mockSubscribe,
    sendMessage: mockSendMessage,
    error: mockError,
  }),
}));

const rootReducer = combineReducers({
  auth: authReducer,
  ui: uiReducer,
});

const mockUser = {
  id: '123',
  email: 'test@example.com',
  name: 'Test User',
  permissions: ['users.read'],
  roles: ['account.member'],
  status: 'active',
  email_verified: true,
  account: {
    id: '456',
    name: 'Test Company',
    status: 'active',
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const createTestStore = (preloadedState?: any) => {
  return configureStore({
    reducer: rootReducer,
    preloadedState,
  });
};

const createWrapper = (store: ReturnType<typeof createTestStore>) => {
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(Provider, { store, children });
  };
};

describe('useNotificationWebSocket', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockIsConnected = true;
    mockError = null;
  });

  describe('subscription', () => {
    it('subscribes to NotificationChannel when connected', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(
        () => useNotificationWebSocket({}),
        { wrapper: createWrapper(store) }
      );

      expect(mockSubscribe).toHaveBeenCalledWith({
        channel: 'NotificationChannel',
        params: { account_id: '456' },
        onMessage: expect.any(Function),
        onError: expect.any(Function),
      });
    });

    it('does not subscribe when user has no account', () => {
      const userWithoutAccount = { ...mockUser, account: undefined };
      const store = createTestStore({
        auth: {
          user: userWithoutAccount,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(
        () => useNotificationWebSocket({}),
        { wrapper: createWrapper(store) }
      );

      expect(mockSubscribe).not.toHaveBeenCalled();
    });

    it('unsubscribes on unmount', () => {
      const mockUnsubscribe = jest.fn();
      mockSubscribe.mockReturnValue(mockUnsubscribe);

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { unmount } = renderHook(
        () => useNotificationWebSocket({}),
        { wrapper: createWrapper(store) }
      );

      unmount();

      expect(mockUnsubscribe).toHaveBeenCalled();
    });
  });

  // Helper to get the subscribe call options safely
  const getSubscribeOptions = () => {
    const call = mockSubscribe.mock.calls[0];
    if (!call) throw new Error('mockSubscribe was not called');
    return call[0];
  };

  describe('message handling', () => {
    it('calls onNewNotification when new_notification received', async () => {
      const onNewNotification = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(
        () => useNotificationWebSocket({ onNewNotification }),
        { wrapper: createWrapper(store) }
      );

      // Get the onMessage callback that was passed to subscribe
      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockNotification: WebSocketNotification = {
        id: 'notif-1',
        notification_type: 'subscription.renewed',
        title: 'Subscription Renewed',
        message: 'Your subscription has been renewed',
        severity: 'success',
        created_at: new Date().toISOString(),
      };

      // Simulate receiving a message
      act(() => {
        onMessage({
          type: 'new_notification',
          notification: mockNotification,
        });
      });

      expect(onNewNotification).toHaveBeenCalledWith(mockNotification);
    });

    it('calls onNotificationRead when notification_read received', async () => {
      const onNotificationRead = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(
        () => useNotificationWebSocket({ onNotificationRead }),
        { wrapper: createWrapper(store) }
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({
          type: 'notification_read',
          notification_id: 'notif-1',
        });
      });

      expect(onNotificationRead).toHaveBeenCalledWith('notif-1');
    });

    it('calls onConnected when connection_established received', async () => {
      const onConnected = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(
        () => useNotificationWebSocket({ onConnected }),
        { wrapper: createWrapper(store) }
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({ type: 'connection_established' });
      });

      expect(onConnected).toHaveBeenCalled();
    });

    it('calls onError when error message received', async () => {
      const onError = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(
        () => useNotificationWebSocket({ onError }),
        { wrapper: createWrapper(store) }
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({
          type: 'error',
          message: 'Something went wrong',
        });
      });

      expect(onError).toHaveBeenCalledWith('Something went wrong');
    });

    it('ignores pong messages silently', () => {
      const onError = jest.fn();
      const onNewNotification = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(
        () => useNotificationWebSocket({ onError, onNewNotification }),
        { wrapper: createWrapper(store) }
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({ type: 'pong' });
      });

      expect(onError).not.toHaveBeenCalled();
      expect(onNewNotification).not.toHaveBeenCalled();
    });

    it('ignores invalid message data', () => {
      const onError = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(
        () => useNotificationWebSocket({ onError }),
        { wrapper: createWrapper(store) }
      );

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      // Test with various invalid inputs
      act(() => {
        onMessage(null);
        onMessage(undefined);
        onMessage('string');
        onMessage({ noType: 'property' });
      });

      expect(onError).not.toHaveBeenCalled();
    });
  });

  describe('ping', () => {
    it('sends ping message when connected', async () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(
        () => useNotificationWebSocket({}),
        { wrapper: createWrapper(store) }
      );

      await act(async () => {
        await result.current.ping();
      });

      expect(mockSendMessage).toHaveBeenCalledWith(
        'NotificationChannel',
        'ping',
        {}
      );
    });

    it('returns false when not connected', async () => {
      mockIsConnected = false;

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(
        () => useNotificationWebSocket({}),
        { wrapper: createWrapper(store) }
      );

      let pingResult: boolean | undefined;
      await act(async () => {
        pingResult = await result.current.ping();
      });

      expect(pingResult).toBe(false);
      expect(mockSendMessage).not.toHaveBeenCalled();
    });
  });

  describe('error handling', () => {
    it('calls onError when channel error occurs', () => {
      const onError = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(
        () => useNotificationWebSocket({ onError }),
        { wrapper: createWrapper(store) }
      );

      const subscribeOptions = getSubscribeOptions();
      const handleError = subscribeOptions.onError;

      act(() => {
        handleError('Channel error occurred');
      });

      expect(onError).toHaveBeenCalledWith('Channel error occurred');
    });
  });

  describe('return values', () => {
    it('returns isConnected state', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(
        () => useNotificationWebSocket({}),
        { wrapper: createWrapper(store) }
      );

      expect(result.current.isConnected).toBe(true);
    });

    it('returns ping function', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(
        () => useNotificationWebSocket({}),
        { wrapper: createWrapper(store) }
      );

      expect(typeof result.current.ping).toBe('function');
    });

    it('returns error state', () => {
      mockError = 'Connection failed';

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(
        () => useNotificationWebSocket({}),
        { wrapper: createWrapper(store) }
      );

      expect(result.current.error).toBe('Connection failed');
    });
  });
});
