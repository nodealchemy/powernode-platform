import { useEffect, useRef } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../store';

interface AnalyticsWebSocketOptions {
  onAnalyticsUpdate?: (data: any) => void;
  onError?: (error: string) => void;
  accountId?: string;
}

export const useAnalyticsWebSocket = ({
  onAnalyticsUpdate,
  onError,
  accountId
}: AnalyticsWebSocketOptions) => {
  const { user, accessToken } = useSelector((state: RootState) => state.auth);
  const wsRef = useRef<WebSocket | null>(null);
  const isConnectedRef = useRef(false);

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

          // Subscribe to analytics channel
          const subscribeMessage = {
            command: 'subscribe',
            identifier: JSON.stringify({
              channel: 'AnalyticsChannel',
              account_id: accountId || user.account?.id
            })
          };
          
          wsRef.current?.send(JSON.stringify(subscribeMessage));
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
          
          // Attempt to reconnect after 5 seconds
          setTimeout(() => {
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
      isConnectedRef.current = false;
    };
  }, [user?.account?.id, accessToken, accountId, onAnalyticsUpdate, onError]);

  const requestAnalyticsUpdate = () => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
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

      wsRef.current.send(JSON.stringify(requestMessage));
    }
  };

  return {
    requestAnalyticsUpdate,
    isConnected: isConnectedRef.current
  };
};