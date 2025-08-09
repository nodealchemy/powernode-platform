import { useState, useEffect, useCallback, useRef } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../store';
import { Customer, CustomerStats, customersApi } from '../services/customersApi';
import { useWebSocketConnection } from './useWebSocketConnection';
import { safeWebSocketSend } from '../utils/websocketUtils';

interface CustomerWebSocketData {
  customers: Customer[];
  stats: CustomerStats;
  searchResults: Customer[];
  lastUpdate: Date | null;
  error: string | null;
}

interface CustomerUpdateMessage {
  type: 'customer_updated' | 'search_results' | 'connection_established' | 'pong';
  event?: 'created' | 'updated' | 'status_changed' | 'deactivated';
  customer?: Customer;
  customer_id?: string;
  stats?: CustomerStats;
  results?: Customer[];
  query?: string;
  timestamp: string;
}

export const useCustomerWebSocket = () => {
  const { user, accessToken } = useSelector((state: RootState) => state.auth);
  const { isConnected, status, reconnectAttempts } = useWebSocketConnection();
  // TODO: Use globalConnect and globalDisconnect for global connection management
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  const [data, setData] = useState<CustomerWebSocketData>({
    customers: [],
    stats: {
      total_customers: 0,
      active_customers: 0,
      active_subscriptions: 0,
      new_this_month: 0,
      total_mrr: 0,
      churn_rate: 0
    },
    searchResults: [],
    lastUpdate: null,
    error: null
  });

  const updateData = useCallback((updates: Partial<CustomerWebSocketData>) => {
    setData(prev => ({ 
      ...prev, 
      ...updates, 
      lastUpdate: new Date() 
    }));
  }, []);

  const getWebSocketUrl = useCallback(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const hostname = window.location.hostname;
    const port = process.env.NODE_ENV === 'development' ? '3001' : window.location.port;
    const baseUrl = `${protocol}//${hostname}:${port}/cable`;
    
    if (accessToken) {
      return `${baseUrl}?token=${encodeURIComponent(accessToken)}`;
    }
    return baseUrl;
  }, [accessToken]);

  const handleCustomerUpdate = useCallback((message: CustomerUpdateMessage) => {
    console.log('Customer update received:', message);
    
    if (message.stats) {
      updateData({ stats: message.stats });
    }
    
    if (message.customer && message.event) {
      setData(prev => {
        let updatedCustomers = [...prev.customers];
        
        switch (message.event) {
          case 'created':
            // Add new customer to the beginning of the list
            updatedCustomers.unshift(message.customer!);
            break;
            
          case 'updated':
          case 'status_changed':
            // Update existing customer
            updatedCustomers = updatedCustomers.map(customer => 
              customer.id === message.customer!.id ? message.customer! : customer
            );
            break;
            
          case 'deactivated':
            // Update customer status or remove from active list
            updatedCustomers = updatedCustomers.map(customer => 
              customer.id === message.customer!.id ? message.customer! : customer
            );
            break;
        }
        
        return {
          ...prev,
          customers: updatedCustomers,
          stats: message.stats || prev.stats,
          lastUpdate: new Date()
        };
      });
    }
  }, [updateData]);

  const connect = useCallback(() => {
    if (!user || !accessToken || wsRef.current) return;

    const wsUrl = getWebSocketUrl();
    
    try {
      wsRef.current = new WebSocket(wsUrl);
      
      wsRef.current.onopen = () => {
        console.log('Customer WebSocket connected');
        updateData({ error: null });
        
        // Subscribe to customer updates channel
        const subscribeMessage = {
          command: "subscribe",
          identifier: JSON.stringify({
            channel: "CustomerChannel",
            account_id: user.account?.id
          })
        };
        
        safeWebSocketSend(wsRef.current, subscribeMessage);
      };

      wsRef.current.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data) as CustomerUpdateMessage;
          
          switch (message.type) {
            case 'connection_established':
              console.log('Customer channel connection established');
              break;
              
            case 'customer_updated':
              handleCustomerUpdate(message);
              break;
              
            case 'search_results':
              if (message.results) {
                updateData({ searchResults: message.results });
              }
              break;
              
            case 'pong':
              // Handle ping response for connection monitoring
              break;
          }
        } catch (error) {
          console.error('Error parsing customer WebSocket message:', error);
        }
      };

      wsRef.current.onerror = (error) => {
        console.error('Customer WebSocket error:', error);
        updateData({ error: 'Connection error' });
      };

      wsRef.current.onclose = (event) => {
        console.log('Customer WebSocket disconnected:', event.code, event.reason);
        wsRef.current = null;
      };
    } catch (error) {
      console.error('Failed to create customer WebSocket connection:', error);
      updateData({ error: 'Failed to connect' });
    }
  }, [user, accessToken, getWebSocketUrl, updateData, handleCustomerUpdate]);

  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
  }, []);

  // Real-time search functionality
  const searchCustomers = useCallback(async (query: string, filters: any = {}) => {
    if (!wsRef.current || !isConnected) return;
    
    const searchMessage = {
      command: "message",
      identifier: JSON.stringify({
        channel: "CustomerChannel",
        account_id: user?.account?.id
      }),
      data: JSON.stringify({
        action: "search",
        query,
        filters
      })
    };
    
    await safeWebSocketSend(wsRef.current, searchMessage);
  }, [isConnected, user?.account?.id]);

  // Real-time customer status update
  const updateCustomerStatus = useCallback(async (customerId: string, status: string) => {
    if (!wsRef.current || !isConnected) return;
    
    const updateMessage = {
      command: "message",
      identifier: JSON.stringify({
        channel: "CustomerChannel",
        account_id: user?.account?.id
      }),
      data: JSON.stringify({
        action: "update_customer_status",
        customer_id: customerId,
        status
      })
    };
    
    await safeWebSocketSend(wsRef.current, updateMessage);
  }, [isConnected, user?.account?.id]);

  // Load initial customer data
  const loadCustomers = useCallback(async (options: any = {}) => {
    try {
      const response = await customersApi.getCustomers(options);
      updateData({
        customers: response.customers,
        stats: response.stats,
        error: null
      });
      return response;
    } catch (error) {
      console.error('Failed to load customers:', error);
      updateData({ error: 'Failed to load customers' });
      throw error;
    }
  }, [updateData]);

  // Connect when user is authenticated
  useEffect(() => {
    if (user && accessToken) {
      connect();
    }
    
    return () => {
      disconnect();
    };
  }, [user, accessToken, connect, disconnect]);

  return {
    ...data,
    isConnected,
    connectionStatus: status,
    reconnectAttempts,
    connect,
    disconnect,
    searchCustomers,
    updateCustomerStatus,
    loadCustomers
  };
};