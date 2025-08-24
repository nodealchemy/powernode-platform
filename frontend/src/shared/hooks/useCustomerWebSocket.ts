import { useCallback, useRef, useEffect } from 'react';
import { useWebSocket } from './useWebSocket';

interface CustomerWebSocketOptions {
  onCustomerUpdate?: (data: any) => void;
  onSearchResults?: (data: any) => void;
  onError?: (error: string) => void;
}

export const useCustomerWebSocket = ({
  onCustomerUpdate,
  onSearchResults,
  onError
}: CustomerWebSocketOptions) => {
  const { isConnected, subscribe, sendMessage, error: connectionError } = useWebSocket();
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Store latest callback refs to avoid dependency issues
  const onCustomerUpdateRef = useRef(onCustomerUpdate);
  const onSearchResultsRef = useRef(onSearchResults);
  const onErrorRef = useRef(onError);
  
  onCustomerUpdateRef.current = onCustomerUpdate;
  onSearchResultsRef.current = onSearchResults;
  onErrorRef.current = onError;

  // Handle incoming messages
  const handleMessage = useCallback((data: any) => {
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
    console.error('❌ Customer channel error:', errorMessage);
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to customer channel
  const subscribeToCustomers = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }
    
    unsubscribeRef.current = subscribe({
      channel: 'CustomerChannel',
      onMessage: handleMessage,
      onError: handleError
    });
    
  }, [subscribe, handleMessage, handleError]);

  // Search customers
  const searchCustomers = useCallback(async (query: string, filters: unknown = {}) => {
    if (!isConnected) {
      console.warn('Cannot search customers: WebSocket not connected');
      return;
    }
    
    await sendMessage('CustomerChannel', 'search', { query, filters });
  }, [isConnected, sendMessage]);

  // Update customer status
  const updateCustomerStatus = useCallback(async (customerId: string, status: string) => {
    if (!isConnected) {
      console.warn('Cannot update customer: WebSocket not connected');
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
      console.warn('Cannot load customers: WebSocket not connected');
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