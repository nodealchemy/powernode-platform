import { renderHook, act } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore, combineReducers } from '@reduxjs/toolkit';
import type { ReactNode } from 'react';
import { createElement } from 'react';
import { useWebSocket } from './useWebSocket';
import authReducer from '../services/slices/authSlice';
import uiReducer from '../services/slices/uiSlice';

// Mock the WebSocketManager
const mockSubscribe = jest.fn(() => jest.fn());
const mockSendMessage = jest.fn(() => Promise.resolve(true));
const mockInitialize = jest.fn();
const mockDisconnect = jest.fn();
const mockAddStateListener = jest.fn(() => jest.fn());
const mockGetIsConnected = jest.fn(() => false);
const mockReconnect = jest.fn();
const mockResetTokenRefreshFlag = jest.fn();

jest.mock('@/shared/services/WebSocketManager', () => ({
  wsManager: {
    subscribe: (...args: Parameters<typeof mockSubscribe>) => mockSubscribe(...args),
    sendMessage: (...args: Parameters<typeof mockSendMessage>) => mockSendMessage(...args),
    initialize: (...args: Parameters<typeof mockInitialize>) => mockInitialize(...args),
    disconnect: () => mockDisconnect(),
    addStateListener: (...args: Parameters<typeof mockAddStateListener>) => mockAddStateListener(...args),
    getIsConnected: () => mockGetIsConnected(),
    reconnect: () => mockReconnect(),
    resetTokenRefreshFlag: () => mockResetTokenRefreshFlag(),
  },
}));

const rootReducer = combineReducers({
  auth: authReducer,
  ui: uiReducer,
});

// Helper to create a test store with specific state
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const createTestStore = (preloadedState?: any) => {
  return configureStore({
    reducer: rootReducer,
    preloadedState,
  });
};

// Wrapper component for renderHook
const createWrapper = (store: ReturnType<typeof createTestStore>) => {
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(Provider, { store, children });
  };
};

describe('useWebSocket', () => {
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

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetIsConnected.mockReturnValue(false);
  });

  describe('initial state', () => {
    it('returns initial disconnected state', () => {
      const store = createTestStore({
        auth: {
          user: null,
          access_token: null,
          isLoading: false,
          isAuthenticated: false,
          error: null,
        },
      });

      const { result } = renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.isConnected).toBe(false);
      expect(result.current.error).toBeNull();
      expect(result.current.lastConnected).toBeNull();
    });

    it('returns all expected properties', () => {
      const store = createTestStore({
        auth: {
          user: null,
          access_token: null,
          isLoading: false,
          isAuthenticated: false,
          error: null,
        },
      });

      const { result } = renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(result.current).toHaveProperty('isConnected');
      expect(result.current).toHaveProperty('error');
      expect(result.current).toHaveProperty('lastConnected');
      expect(result.current).toHaveProperty('subscribe');
      expect(result.current).toHaveProperty('sendMessage');
    });
  });

  describe('subscribe method', () => {
    it('returns a function', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(typeof result.current.subscribe).toBe('function');
    });

    it('calls wsManager.subscribe with subscription config', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      const subscription = {
        channel: 'TestChannel',
        params: { id: '123' },
        onMessage: jest.fn(),
      };

      result.current.subscribe(subscription);

      expect(mockSubscribe).toHaveBeenCalledWith(subscription);
    });

    it('returns unsubscribe function from wsManager', () => {
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

      const { result } = renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      const unsubscribe = result.current.subscribe({
        channel: 'TestChannel',
      });

      expect(unsubscribe).toBe(mockUnsubscribe);
    });
  });

  describe('sendMessage method', () => {
    it('returns a function', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(typeof result.current.sendMessage).toBe('function');
    });

    it('calls wsManager.sendMessage with correct arguments', async () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.sendMessage('TestChannel', 'test_action', { key: 'value' }, { param: '1' });
      });

      expect(mockSendMessage).toHaveBeenCalledWith('TestChannel', 'test_action', { key: 'value' }, { param: '1' });
    });

    it('returns a promise that resolves to boolean', async () => {
      mockSendMessage.mockResolvedValue(true);

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      let sendResult: boolean | undefined;
      await act(async () => {
        sendResult = await result.current.sendMessage('TestChannel', 'test_action');
      });

      expect(sendResult).toBe(true);
    });
  });

  describe('initialization', () => {
    it('initializes WebSocket when user and token are present', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(mockInitialize).toHaveBeenCalled();
    });

    it('does not initialize when user is not present', () => {
      const store = createTestStore({
        auth: {
          user: null,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: false,
          error: null,
        },
      });

      renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(mockInitialize).not.toHaveBeenCalled();
    });

    it('does not initialize when token is not present', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: null,
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(mockInitialize).not.toHaveBeenCalled();
    });
  });

  describe('disconnection', () => {
    it('disconnects when user logs out', () => {
      const store = createTestStore({
        auth: {
          user: null,
          access_token: null,
          isLoading: false,
          isAuthenticated: false,
          error: null,
        },
      });

      renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(mockDisconnect).toHaveBeenCalled();
    });

    it('disconnects when token is removed', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: null,
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(mockDisconnect).toHaveBeenCalled();
    });
  });

  describe('state listener', () => {
    it('adds state listener on mount', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(mockAddStateListener).toHaveBeenCalled();
    });

    it('syncs initial connected state from manager', () => {
      mockGetIsConnected.mockReturnValue(true);

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useWebSocket(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.isConnected).toBe(true);
    });
  });
});
