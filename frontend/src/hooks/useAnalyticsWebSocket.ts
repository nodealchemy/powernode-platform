import { useEffect, useRef, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../store';
import { safeWebSocketSend } from '../utils/websocketUtils';

export interface AnalyticsUpdateData {
  current_metrics: {
    mrr: number;
    arr: number;
    active_customers: number;
    churn_rate: number;
    arpu: number;
    growth_rate: number;
    [key: string]: any;
  };
  today_activity?: {
    new_subscriptions: number;
    cancelled_subscriptions: number;
    payments_processed: number;
    failed_payments: number;
    revenue_today: number;
  };
  weekly_trend?: Array<{
    date: string;
    new_subscriptions: number;
    revenue: number;
    payments_count: number;
  }>;
  timestamp: string;
  account_id?: string;
}

interface AnalyticsWebSocketOptions {
  onAnalyticsUpdate?: (data: AnalyticsUpdateData) => void;
  onError?: (error: string) => void;
  accountId?: string;
  autoRequest?: boolean;
  requestInterval?: number;
}

export const useAnalyticsWebSocket = ({
  onAnalyticsUpdate,
  onError,
  accountId,
  autoRequest = false,
  requestInterval = 30000
}: AnalyticsWebSocketOptions) => {
  const { user, accessToken } = useSelector((state: RootState) => state.auth);
  const wsRef = useRef<WebSocket | null>(null);
  const isConnectedRef = useRef(false);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    if (!user?.account?.id || !accessToken) return;

    const connectWebSocket = () => {
      try {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const hostname = window.location.hostname;
        const port = process.env.NODE_ENV === 'development' ? '3000' : window.location.port;
        const wsUrl = `${protocol}//${hostname}:${port}/cable?token=${encodeURIComponent(accessToken)}`;

        wsRef.current = new WebSocket(wsUrl);

        wsRef.current.onopen = () => {
          console.log('Analytics WebSocket connected');
          isConnectedRef.current = true;

          // Wait for connection to be fully established before subscribing
          setTimeout(async () => {
            const subscribeMessage = {
              command: 'subscribe',
              identifier: JSON.stringify({
                channel: 'AnalyticsChannel',
                account_id: accountId || user.account?.id
              })
            };
            
            const sent = await safeWebSocketSend(wsRef.current, subscribeMessage);
            if (!sent) {
              console.warn('Failed to subscribe to Analytics channel');
            }
          }, 100); // Small delay to ensure connection is fully ready
        };

        wsRef.current.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);
            
            // Ignore system messages
            if (data.type === 'ping' || data.type === 'welcome' || data.type === 'confirm_subscription') {
              return;
            }

            // Handle analytics updates
            if (data.message?.type === 'analytics_update' && onAnalyticsUpdate) {
              onAnalyticsUpdate(data.message.data);
            } else if (data.type === 'analytics_update' && onAnalyticsUpdate) {
              onAnalyticsUpdate(data.data);
            }
            
            // Handle connection established message
            if (data.message?.type === 'analytics_connection_established') {
              console.log('Analytics connection established:', data.message.message);
              // Start auto-request interval if enabled
              if (autoRequest && !intervalRef.current) {
                intervalRef.current = setInterval(() => {
                  requestAnalyticsUpdate();
                }, requestInterval);
              }
            }

            // Handle errors
            if (data.message?.type === 'error' && onError) {
              onError(data.message.message);
            } else if (data.type === 'error' && onError) {
              onError(data.message);
            }
          } catch (error) {
            console.error('Error parsing analytics WebSocket message:', error);
          }
        };

        wsRef.current.onclose = () => {
          console.log('Analytics WebSocket disconnected');
          isConnectedRef.current = false;
          
          // Clear auto-request interval
          if (intervalRef.current) {
            clearInterval(intervalRef.current);
            intervalRef.current = null;
          }
          
          // Attempt to reconnect after 5 seconds
          reconnectTimeoutRef.current = setTimeout(() => {
            if (user?.account?.id && accessToken) {
              connectWebSocket();
            }
          }, 5000);
        };

        wsRef.current.onerror = (error) => {
          console.error('Analytics WebSocket error:', error);
          if (onError) {
            onError('WebSocket connection error');
          }
        };
      } catch (error) {
        console.error('Failed to create analytics WebSocket:', error);
        if (onError) {
          onError('Failed to establish WebSocket connection');
        }
      }
    };

    connectWebSocket();

    return () => {
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
      }
      isConnectedRef.current = false;
    };
  }, [user?.account?.id, accessToken, accountId, onAnalyticsUpdate, onError, autoRequest, requestInterval]);

  const requestAnalyticsUpdate = useCallback(async () => {
    if (!isConnectedRef.current || !wsRef.current) {
      console.warn('WebSocket not connected, cannot request analytics update');
      return;
    }
    const requestMessage = {
      command: 'message',
      identifier: JSON.stringify({
        channel: 'AnalyticsChannel',
        account_id: accountId || user?.account?.id
      }),
      data: JSON.stringify({
        action: 'request_analytics',
        account_id: accountId || user?.account?.id
      })
    };

    const sent = await safeWebSocketSend(wsRef.current, requestMessage);
    if (!sent) {
      console.warn('Failed to request analytics update');
    }
  }, [accountId, user?.account?.id]);

  return {
    requestAnalyticsUpdate,
    isConnected: isConnectedRef.current,
    startAutoRequests: () => {
      if (!intervalRef.current && isConnectedRef.current) {
        intervalRef.current = setInterval(() => {
          requestAnalyticsUpdate();
        }, requestInterval);
      }
    },
    stopAutoRequests: () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    }
  };
};