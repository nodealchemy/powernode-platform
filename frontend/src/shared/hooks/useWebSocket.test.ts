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
const mockSetMaintenanceActive = jest.fn();

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
    setMaintenanceActive: (...args: Parameters<typeof mockSetMaintenanceActive>) => mockSetMaintenanceActive(...args),
  },
}));

const rootReducer = combineReducers({
  auth: authReducer,
  ui: uiReducer,
});

// Helper to create a test store with specific state
 
type TestState = ReturnType<typeof rootReducer>;
type DeepPartial<T> = T extends object ? { [K in keyof T]?: DeepPartial<T[K]> } : T;

const createTestStore = (preloadedState?: DeepPartial<TestState>) => {
  return configureStore({
    reducer: rootReducer,
    preloadedState: preloadedState as TestState | undefined,
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

  // N2: reason: 'unauthorized' silently refreshes+reconnects (see
  // handleUnauthorized above), which is exactly wrong for a maintenance-mode
  // disconnect — refresh itself is never gated, so it succeeds immediately
  // and the new connection gets rejected again, looping. wsManager's own
  // #connect() guard is what actually stops the loop; this hook's job is
  // just to keep that guard in sync with ui.maintenance.active.
  describe('maintenance mode', () => {
    it('tells wsManager maintenance is active as soon as ui.maintenance.active is true', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
        ui: { maintenance: { active: true, message: 'Upgrading' } },
      });

      renderHook(() => useWebSocket(), { wrapper: createWrapper(store) });

      expect(mockSetMaintenanceActive).toHaveBeenCalledWith(true);
    });

    it('tells wsManager maintenance is inactive, and does NOT reconnect, when never active', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useWebSocket(), { wrapper: createWrapper(store) });

      expect(mockSetMaintenanceActive).toHaveBeenCalledWith(false);
      expect(mockReconnect).not.toHaveBeenCalled();
    });

    it('reconnects once maintenance clears, if a session is still held and not already connected', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
        ui: { maintenance: { active: true, message: 'Upgrading' } },
      });

      renderHook(() => useWebSocket(), { wrapper: createWrapper(store) });
      expect(mockReconnect).not.toHaveBeenCalled();

      act(() => {
        store.dispatch({ type: 'ui/clearMaintenanceMode' });
      });

      expect(mockSetMaintenanceActive).toHaveBeenCalledWith(false);
      expect(mockReconnect).toHaveBeenCalled();
    });

    it('does not reconnect on clear when already connected', () => {
      mockGetIsConnected.mockReturnValue(true);

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
        ui: { maintenance: { active: true, message: 'Upgrading' } },
      });

      renderHook(() => useWebSocket(), { wrapper: createWrapper(store) });

      act(() => {
        store.dispatch({ type: 'ui/clearMaintenanceMode' });
      });

      expect(mockReconnect).not.toHaveBeenCalled();
    });

    // Item 7b: the cable path's own message/estimatedCompletion args are
    // currently always undefined (Rails' Connection#close(reason:,
    // reconnect:) can't carry custom fields) — dispatching unconditionally
    // would blank out a message the HTTP interceptor already set.
    it('sets the maintenance flag from the cable disconnect when nothing had set it yet', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useWebSocket(), { wrapper: createWrapper(store) });
      const config = mockInitialize.mock.calls[mockInitialize.mock.calls.length - 1][0];

      act(() => {
        config.onMaintenanceMode(undefined, undefined);
      });

      expect(store.getState().ui.maintenance?.active).toBe(true);
    });

    it('does NOT overwrite an already-active maintenance flag (e.g. one the HTTP interceptor already set)', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
        ui: { maintenance: { active: true, message: 'Upgrading the database' } },
      });

      renderHook(() => useWebSocket(), { wrapper: createWrapper(store) });
      const config = mockInitialize.mock.calls[mockInitialize.mock.calls.length - 1][0];

      act(() => {
        config.onMaintenanceMode(undefined, undefined);
      });

      expect(store.getState().ui.maintenance?.message).toBe('Upgrading the database');
    });
  });
});
