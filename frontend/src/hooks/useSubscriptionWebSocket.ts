import { useEffect, useCallback, useRef } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { RootState, AppDispatch } from '../store';
import { fetchSubscriptions, setCurrentSubscription } from '../store/slices/subscriptionSlice';
import { useWebSocketConnection } from './useWebSocketConnection';

interface SubscriptionUpdate {
  type: 'subscription_updated' | 'subscription_cancelled' | 'payment_processed' | 'trial_ending';
  subscription: any;
  message?: string;
}

export const useSubscriptionWebSocket = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { user } = useSelector((state: RootState) => state.auth);
  const { isConnected, status } = useWebSocketConnection();
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const reconnectAttemptsRef = useRef(0);

  const connect = useCallback(() => {
    if (!user || wsRef.current?.readyState === WebSocket.CONNECTING || wsRef.current?.readyState === WebSocket.OPEN) {
      return;
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.hostname}:3000/cable`;
    
    try {
      wsRef.current = new WebSocket(wsUrl);

      wsRef.current.onopen = () => {
        console.log('WebSocket connected for subscription updates');
        reconnectAttemptsRef.current = 0;
        
        // Subscribe to subscription updates channel
        const subscribeMessage = {
          command: 'subscribe',
          identifier: JSON.stringify({
            channel: 'SubscriptionChannel',
            account_id: user.account?.id
          })
        };
        
        wsRef.current?.send(JSON.stringify(subscribeMessage));
      };

      wsRef.current.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          
          if (data.type === 'ping' || data.type === 'welcome' || data.type === 'confirm_subscription') {
            return; // Ignore system messages
          }

          if (data.message && data.message.type) {
            const update: SubscriptionUpdate = data.message;
            handleSubscriptionUpdate(update);
          }
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      wsRef.current.onclose = (event) => {
        console.log('WebSocket closed:', event.code, event.reason);
        wsRef.current = null;
        
        // Attempt to reconnect with exponential backoff
        if (reconnectAttemptsRef.current < 5) {
          const delay = Math.min(1000 * Math.pow(2, reconnectAttemptsRef.current), 30000);
          reconnectAttemptsRef.current++;
          
          reconnectTimeoutRef.current = setTimeout(() => {
            connect();
          }, delay);
        }
      };

      wsRef.current.onerror = (error) => {
        console.error('WebSocket error:', error);
      };

    } catch (error) {
      console.error('Failed to create WebSocket connection:', error);
    }
  }, [user]);

  const handleSubscriptionUpdate = useCallback((update: SubscriptionUpdate) => {
    console.log('Received subscription update:', update);
    
    switch (update.type) {
      case 'subscription_updated':
      case 'subscription_cancelled':
      case 'payment_processed':
        // Refresh subscriptions data
        dispatch(fetchSubscriptions());
        break;
        
      case 'trial_ending':
        // Show notification and refresh data
        dispatch(fetchSubscriptions());
        // You could also trigger a notification here
        break;
        
      default:
        console.log('Unknown subscription update type:', update.type);
    }
  }, [dispatch]);

  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
    
    reconnectAttemptsRef.current = 0;
  }, []);

  // Connect when user is available, disconnect when user is gone
  useEffect(() => {
    if (user) {
      connect();
    } else {
      disconnect();
    }

    return () => {
      disconnect();
    };
  }, [user, connect, disconnect]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      disconnect();
    };
  }, [disconnect]);

  return {
    isConnected: isConnected,
    connectionStatus: status,
    reconnectAttempts: reconnectAttemptsRef.current,
    connect,
    disconnect
  };
};