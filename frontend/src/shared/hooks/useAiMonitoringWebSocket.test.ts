import { renderHook, act } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore, combineReducers } from '@reduxjs/toolkit';
import type { ReactNode } from 'react';
import { createElement } from 'react';
import {
  useAiMonitoringWebSocket,
  DashboardStats,
  WorkflowExecution,
  SystemAlert,
  CostAlert,
} from './useAiMonitoringWebSocket';
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

describe('useAiMonitoringWebSocket', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockIsConnected = true;
    mockError = null;
  });

  describe('subscription', () => {
    it('subscribes to AiWorkflowMonitoringChannel when connected', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useAiMonitoringWebSocket({}), {
        wrapper: createWrapper(store),
      });

      expect(mockSubscribe).toHaveBeenCalledWith({
        channel: 'AiWorkflowMonitoringChannel',
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

      renderHook(() => useAiMonitoringWebSocket({}), {
        wrapper: createWrapper(store),
      });

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

      const { unmount } = renderHook(() => useAiMonitoringWebSocket({}), {
        wrapper: createWrapper(store),
      });

      unmount();

      expect(mockUnsubscribe).toHaveBeenCalled();
    });
  });

  describe('message handling', () => {
    it('calls onDashboardStats when dashboard_stats received', () => {
      const onDashboardStats = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useAiMonitoringWebSocket({ onDashboardStats }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockStats: DashboardStats = {
        total_workflows: 10,
        active_executions: 3,
        completed_today: 25,
        failed_today: 2,
      };

      act(() => {
        onMessage({
          type: 'dashboard_stats',
          stats: mockStats,
        });
      });

      expect(onDashboardStats).toHaveBeenCalledWith(mockStats);
    });

    it('calls onActiveExecutions when active_executions received', () => {
      const onActiveExecutions = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useAiMonitoringWebSocket({ onActiveExecutions }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockExecutions: WorkflowExecution[] = [
        {
          id: 'exec-1',
          run_id: 'run-1',
          workflow_id: 'workflow-1',
          workflow_name: 'Test Workflow',
          status: 'running',
          started_at: new Date().toISOString(),
          completed_at: null,
          execution_time_ms: null,
          total_cost: null,
        },
      ];

      act(() => {
        onMessage({
          type: 'active_executions',
          executions: mockExecutions,
        });
      });

      expect(onActiveExecutions).toHaveBeenCalledWith(mockExecutions);
    });

    it('calls onSystemAlert when system_alert received', () => {
      const onSystemAlert = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useAiMonitoringWebSocket({ onSystemAlert }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockAlert: SystemAlert = {
        id: 'alert-1',
        severity: 'warning',
        message: 'High API latency detected',
        source: 'monitoring',
        timestamp: new Date().toISOString(),
      };

      act(() => {
        onMessage({
          type: 'system_alert',
          alert: mockAlert,
        });
      });

      expect(onSystemAlert).toHaveBeenCalledWith(mockAlert);
    });

    it('calls onCostAlert when cost_alert received', () => {
      const onCostAlert = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useAiMonitoringWebSocket({ onCostAlert }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockCostAlert: CostAlert = {
        threshold_type: 'daily',
        current_value: 150,
        threshold_value: 100,
        message: 'Daily cost threshold exceeded',
        timestamp: new Date().toISOString(),
      };

      act(() => {
        onMessage({
          type: 'cost_alert',
          cost_data: mockCostAlert,
        });
      });

      expect(onCostAlert).toHaveBeenCalledWith(mockCostAlert);
    });

    it('calls onError when error message received', () => {
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

      renderHook(() => useAiMonitoringWebSocket({ onError }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({
          type: 'error',
          error: 'Monitoring channel error',
        });
      });

      expect(onError).toHaveBeenCalledWith('Monitoring channel error');
    });

    it('handles subscription.confirmed silently', () => {
      const onError = jest.fn();
      const onDashboardStats = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useAiMonitoringWebSocket({ onError, onDashboardStats }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({ type: 'subscription.confirmed' });
      });

      expect(onError).not.toHaveBeenCalled();
      expect(onDashboardStats).not.toHaveBeenCalled();
    });
  });

  describe('requestDashboardStats', () => {
    it('sends get_dashboard_stats message when connected', async () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useAiMonitoringWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.requestDashboardStats();
      });

      expect(mockSendMessage).toHaveBeenCalledWith(
        'AiWorkflowMonitoringChannel',
        'get_dashboard_stats',
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

      const { result } = renderHook(() => useAiMonitoringWebSocket({}), {
        wrapper: createWrapper(store),
      });

      let requestResult: boolean | undefined;
      await act(async () => {
        requestResult = await result.current.requestDashboardStats();
      });

      expect(requestResult).toBe(false);
      expect(mockSendMessage).not.toHaveBeenCalled();
    });
  });

  describe('requestActiveExecutions', () => {
    it('sends get_active_executions message when connected', async () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useAiMonitoringWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.requestActiveExecutions();
      });

      expect(mockSendMessage).toHaveBeenCalledWith(
        'AiWorkflowMonitoringChannel',
        'get_active_executions',
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

      const { result } = renderHook(() => useAiMonitoringWebSocket({}), {
        wrapper: createWrapper(store),
      });

      let requestResult: boolean | undefined;
      await act(async () => {
        requestResult = await result.current.requestActiveExecutions();
      });

      expect(requestResult).toBe(false);
    });
  });

  describe('return values', () => {
    it('returns all expected properties', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useAiMonitoringWebSocket({}), {
        wrapper: createWrapper(store),
      });

      expect(result.current).toHaveProperty('isConnected');
      expect(result.current).toHaveProperty('requestDashboardStats');
      expect(result.current).toHaveProperty('requestActiveExecutions');
      expect(result.current).toHaveProperty('error');
    });

    it('returns error state from connection', () => {
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

      const { result } = renderHook(() => useAiMonitoringWebSocket({}), {
        wrapper: createWrapper(store),
      });

      expect(result.current.error).toBe('Connection failed');
    });
  });
});
