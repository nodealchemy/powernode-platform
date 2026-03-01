import { renderHook, act } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore, combineReducers } from '@reduxjs/toolkit';
import type { ReactNode } from 'react';
import { createElement } from 'react';
import { useCustomerWebSocket } from './useCustomerWebSocket';
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

describe('useCustomerWebSocket', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockIsConnected = true;
    mockError = null;
  });

  describe('subscription', () => {
    it('subscribes to CustomerChannel when connected', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      expect(mockSubscribe).toHaveBeenCalledWith({
        channel: 'CustomerChannel',
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

      renderHook(() => useCustomerWebSocket({}), {
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

      const { unmount } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      unmount();

      expect(mockUnsubscribe).toHaveBeenCalled();
    });
  });

  describe('message handling', () => {
    it('calls onCustomerUpdate when customer_updated received', () => {
      const onCustomerUpdate = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useCustomerWebSocket({ onCustomerUpdate }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockData = {
        type: 'customer_updated',
        data: {
          id: 'customer-1',
          name: 'Updated Customer',
          email: 'updated@example.com',
        },
      };

      act(() => {
        onMessage(mockData);
      });

      expect(onCustomerUpdate).toHaveBeenCalledWith(mockData);
    });

    it('calls onCustomerUpdate when customer_created received', () => {
      const onCustomerUpdate = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useCustomerWebSocket({ onCustomerUpdate }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockData = {
        type: 'customer_created',
        data: {
          id: 'customer-2',
          name: 'New Customer',
          email: 'new@example.com',
        },
      };

      act(() => {
        onMessage(mockData);
      });

      expect(onCustomerUpdate).toHaveBeenCalledWith(mockData);
    });

    it('calls onCustomerUpdate when customer_status_changed received', () => {
      const onCustomerUpdate = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useCustomerWebSocket({ onCustomerUpdate }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockData = {
        type: 'customer_status_changed',
        data: {
          id: 'customer-1',
          status: 'active',
          previous_status: 'pending',
        },
      };

      act(() => {
        onMessage(mockData);
      });

      expect(onCustomerUpdate).toHaveBeenCalledWith(mockData);
    });

    it('calls onSearchResults when search_results received', () => {
      const onSearchResults = jest.fn();

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      renderHook(() => useCustomerWebSocket({ onSearchResults }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      const mockData = {
        type: 'search_results',
        data: {
          customers: [
            { id: 'customer-1', name: 'Test Customer' },
          ],
          total: 1,
        },
      };

      act(() => {
        onMessage(mockData);
      });

      expect(onSearchResults).toHaveBeenCalledWith(mockData);
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

      renderHook(() => useCustomerWebSocket({ onError }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({
          type: 'error',
          message: 'Customer not found',
        });
      });

      expect(onError).toHaveBeenCalledWith('Customer not found');
    });

    it('uses default error message when not provided', () => {
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

      renderHook(() => useCustomerWebSocket({ onError }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage({ type: 'error' });
      });

      expect(onError).toHaveBeenCalledWith('Customer channel error');
    });

    it('ignores invalid message data', () => {
      const onCustomerUpdate = jest.fn();
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

      renderHook(() => useCustomerWebSocket({ onCustomerUpdate, onError }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const onMessage = subscribeOptions.onMessage;

      act(() => {
        onMessage(null);
        onMessage(undefined);
        onMessage('string');
        onMessage({ noType: 'property' });
      });

      expect(onCustomerUpdate).not.toHaveBeenCalled();
      expect(onError).not.toHaveBeenCalled();
    });
  });

  describe('searchCustomers', () => {
    it('sends search message with query and filters', async () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.searchCustomers('test query', { status: 'active' });
      });

      expect(mockSendMessage).toHaveBeenCalledWith('CustomerChannel', 'search', {
        query: 'test query',
        filters: { status: 'active' },
      });
    });

    it('sends search with default empty filters', async () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.searchCustomers('search term');
      });

      expect(mockSendMessage).toHaveBeenCalledWith('CustomerChannel', 'search', {
        query: 'search term',
        filters: {},
      });
    });

    it('does not send message when not connected', async () => {
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

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.searchCustomers('test');
      });

      expect(mockSendMessage).not.toHaveBeenCalled();
    });
  });

  describe('updateCustomerStatus', () => {
    it('sends update_customer_status message', async () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.updateCustomerStatus('customer-123', 'active');
      });

      expect(mockSendMessage).toHaveBeenCalledWith(
        'CustomerChannel',
        'update_customer_status',
        {
          customer_id: 'customer-123',
          status: 'active',
        }
      );
    });

    it('does not send message when not connected', async () => {
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

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.updateCustomerStatus('customer-123', 'active');
      });

      expect(mockSendMessage).not.toHaveBeenCalled();
    });
  });

  describe('loadCustomers', () => {
    it('sends load_customers message with filters', async () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.loadCustomers({ page: 1, per_page: 25, status: 'active' });
      });

      expect(mockSendMessage).toHaveBeenCalledWith(
        'CustomerChannel',
        'load_customers',
        { page: 1, per_page: 25, status: 'active' }
      );
    });

    it('sends load_customers with default empty filters', async () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.loadCustomers();
      });

      expect(mockSendMessage).toHaveBeenCalledWith(
        'CustomerChannel',
        'load_customers',
        {}
      );
    });

    it('does not send message when not connected', async () => {
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

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      await act(async () => {
        await result.current.loadCustomers({ status: 'all' });
      });

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

      renderHook(() => useCustomerWebSocket({ onError }), {
        wrapper: createWrapper(store),
      });

      const subscribeOptions = getSubscribeOptions();
      const handleError = subscribeOptions.onError;

      act(() => {
        handleError('Connection terminated');
      });

      expect(onError).toHaveBeenCalledWith('Connection terminated');
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

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      expect(result.current).toHaveProperty('isConnected');
      expect(result.current).toHaveProperty('searchCustomers');
      expect(result.current).toHaveProperty('updateCustomerStatus');
      expect(result.current).toHaveProperty('loadCustomers');
      expect(result.current).toHaveProperty('error');
    });

    it('returns error state', () => {
      mockError = 'Connection error';

      const store = createTestStore({
        auth: {
          user: mockUser,
          access_token: 'test-token',
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useCustomerWebSocket({}), {
        wrapper: createWrapper(store),
      });

      expect(result.current.error).toBe('Connection error');
    });
  });
});
