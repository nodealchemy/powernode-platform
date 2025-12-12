import { useCallback, useRef, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from './useWebSocket';

interface CustomerWebSocketOptions {
  onCustomerUpdate?: (data: unknown) => void;
  onSearchResults?: (data: unknown) => void;
  onError?: (error: string) => void;
}

export const useCustomerWebSocket = ({
  onCustomerUpdate,
  onSearchResults,
  onError
}: CustomerWebSocketOptions) => {
  const { isConnected, subscribe, sendMessage, error: connectionError } = useWebSocket();
  const user = useSelector((state: RootState) => state.auth.user);
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Store latest callback refs to avoid dependency issues
  const onCustomerUpdateRef = useRef(onCustomerUpdate);
  const onSearchResultsRef = useRef(onSearchResults);
  const onErrorRef = useRef(onError);
  
  onCustomerUpdateRef.current = onCustomerUpdate;
  onSearchResultsRef.current = onSearchResults;
  onErrorRef.current = onError;

  // Type guard for WebSocket message data
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const isWebSocketMessage = (data: unknown): data is { type: string; data?: any; message?: string } => {
    return typeof data === 'object' && data !== null && 'type' in data;
  };

  // Handle incoming messages
  const handleMessage = useCallback((data: unknown) => {
    if (!isWebSocketMessage(data)) return;
    
    switch (data.type) {
      case 'customer_updated':
      case 'customer_created':
      case 'customer_status_changed':
        onCustomerUpdateRef.current?.(data);
        break;
      
      case 'search_results':
        onSearchResultsRef.current?.(data);
        break;
        
      case 'error':
        onErrorRef.current?.(data.message || 'Customer channel error');
        break;
    }
  }, []);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to customer channel
  const subscribeToCustomers = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }

    // Only subscribe if user has an account
    if (!user?.account?.id) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[CustomerWebSocket] Cannot subscribe: user account not available');
      }
      return;
    }

    unsubscribeRef.current = subscribe({
      channel: 'CustomerChannel',
      params: { account_id: user.account.id },
      onMessage: handleMessage,
      onError: handleError
    });

  }, [subscribe, handleMessage, handleError, user?.account?.id]);

  // Search customers
  const searchCustomers = useCallback(async (query: string, filters: unknown = {}) => {
    if (!isConnected) {
      return;
    }
    
    await sendMessage('CustomerChannel', 'search', { query, filters });
  }, [isConnected, sendMessage]);

  // Update customer status
  const updateCustomerStatus = useCallback(async (customerId: string, status: string) => {
    if (!isConnected) {
      return;
    }
    
    await sendMessage('CustomerChannel', 'update_customer_status', { 
      customer_id: customerId, 
      status 
    });
  }, [isConnected, sendMessage]);

  // Load customers list
  const loadCustomers = useCallback(async (filters: unknown = {}) => {
    if (!isConnected) {
      return;
    }
    
    await sendMessage('CustomerChannel', 'load_customers', filters);
  }, [isConnected, sendMessage]);

  // Auto-subscribe when connected
  useEffect(() => {
    if (isConnected) {
      subscribeToCustomers();
    }
    
    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [isConnected, subscribeToCustomers]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    searchCustomers,
    updateCustomerStatus,
    loadCustomers,
    error: connectionError
  };
};