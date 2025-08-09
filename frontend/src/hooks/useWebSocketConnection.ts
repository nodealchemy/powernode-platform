import { useEffect, useState, useCallback, useRef } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../store';

export type WebSocketStatus = 'disconnected' | 'connecting' | 'connected' | 'error' | 'reconnecting';

interface WebSocketConnectionState {
  status: WebSocketStatus;
  isConnected: boolean;
  lastConnected: Date | null;
  reconnectAttempts: number;
  latency: number | null;
  error: string | null;
}

interface UseWebSocketConnectionReturn extends WebSocketConnectionState {
  connect: () => void;
  disconnect: () => void;
  ping: () => void;
  getConnectionQuality: () => 'excellent' | 'good' | 'fair' | 'poor' | 'unknown';
}

export const useWebSocketConnection = (): UseWebSocketConnectionReturn => {
  const { user, accessToken } = useSelector((state: RootState) => state.auth);
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const pingIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const pingTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const lastPingTimeRef = useRef<number | null>(null);

  const [state, setState] = useState<WebSocketConnectionState>({
    status: 'disconnected',
    isConnected: false,
    lastConnected: null,
    reconnectAttempts: 0,
    latency: null,
    error: null,
  });

  const clearTimeouts = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    if (pingIntervalRef.current) {
      clearInterval(pingIntervalRef.current);
      pingIntervalRef.current = null;
    }
    if (pingTimeoutRef.current) {
      clearTimeout(pingTimeoutRef.current);
      pingTimeoutRef.current = null;
    }
  }, []);

  const updateState = useCallback((updates: Partial<WebSocketConnectionState>) => {
    setState(prev => ({ ...prev, ...updates }));
  }, []);

  const getWebSocketUrl = useCallback(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const hostname = window.location.hostname;
    const port = process.env.NODE_ENV === 'development' ? '3000' : window.location.port;
    const baseUrl = `${protocol}//${hostname}:${port}/cable`;
    
    // Add token as query parameter for authentication
    if (accessToken) {
      return `${baseUrl}?token=${encodeURIComponent(accessToken)}`;
    }
    return baseUrl;
  }, [accessToken]);

  const ping = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      const pingStart = Date.now();
      lastPingTimeRef.current = pingStart;
      
      const pingMessage = {
        command: 'message',
        identifier: JSON.stringify({ channel: 'NotificationChannel', account_id: user?.account?.id }),
        data: JSON.stringify({ action: 'ping', timestamp: pingStart })
      };

      wsRef.current.send(JSON.stringify(pingMessage));

      // Set timeout for ping response
      pingTimeoutRef.current = setTimeout(() => {
        updateState({ 
          status: 'error', 
          error: 'Ping timeout',
          latency: null 
        });
        lastPingTimeRef.current = null;
      }, 5000);
    }
  }, [user?.account?.id, updateState]);

  const startHeartbeat = useCallback(() => {
    pingIntervalRef.current = setInterval(() => {
      ping();
    }, 30000); // Ping every 30 seconds
  }, [ping]);

  const stopHeartbeat = useCallback(() => {
    if (pingIntervalRef.current) {
      clearInterval(pingIntervalRef.current);
      pingIntervalRef.current = null;
    }
  }, []);

  const connect = useCallback(() => {
    if (!user?.account?.id || !accessToken) return;
    
    if (wsRef.current?.readyState === WebSocket.CONNECTING || 
        wsRef.current?.readyState === WebSocket.OPEN) {
      return;
    }

    updateState({ status: 'connecting', error: null });

    try {
      const wsUrl = getWebSocketUrl();
      wsRef.current = new WebSocket(wsUrl);

      wsRef.current.onopen = () => {
        updateState({ 
          status: 'connected', 
          isConnected: true, 
          lastConnected: new Date(),
          reconnectAttempts: 0,
          error: null
        });

        // Subscribe to notification channel
        const subscribeMessage = {
          command: 'subscribe',
          identifier: JSON.stringify({
            channel: 'NotificationChannel',
            account_id: user.account?.id
          })
        };
        
        wsRef.current?.send(JSON.stringify(subscribeMessage));
        startHeartbeat();
        
        // Initial ping to measure latency
        setTimeout(() => ping(), 1000);
      };

      wsRef.current.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          
          if (data.type === 'ping' || data.type === 'welcome' || data.type === 'confirm_subscription') {
            return; // Ignore system messages
          }
          

          // Handle pong response for latency calculation
          // ActionCable sends: { message: { type: 'pong', timestamp: ..., server_timestamp: ... }, identifier: ... }
          if (data.message?.type === 'pong' || data.type === 'pong') {
            // Calculate latency using locally stored ping time
            if (lastPingTimeRef.current) {
              const latency = Date.now() - lastPingTimeRef.current;
              
              if (pingTimeoutRef.current) {
                clearTimeout(pingTimeoutRef.current);
                pingTimeoutRef.current = null;
              }
              
              // Only update if latency is reasonable (0-2000ms)
              if (latency >= 0 && latency < 2000) {
                updateState({ latency, status: 'connected' });
              }
              
              lastPingTimeRef.current = null;
            }
          }
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      wsRef.current.onclose = (event) => {
        updateState({ 
          status: 'disconnected', 
          isConnected: false,
          error: event.code !== 1000 ? `Connection closed: ${event.reason || 'Unknown reason'}` : null
        });
        
        stopHeartbeat();
        clearTimeouts();

        // Attempt to reconnect with exponential backoff
        if (event.code !== 1000 && state.reconnectAttempts < 5) {
          updateState({ 
            status: 'reconnecting',
            reconnectAttempts: state.reconnectAttempts + 1 
          });
          
          const delay = Math.min(1000 * Math.pow(2, state.reconnectAttempts), 30000);
          reconnectTimeoutRef.current = setTimeout(() => {
            connect();
          }, delay);
        }
      };

      wsRef.current.onerror = (error) => {
        console.error('WebSocket error:', error);
        updateState({ 
          status: 'error', 
          isConnected: false,
          error: 'WebSocket connection error'
        });
      };

    } catch (error) {
      updateState({ 
        status: 'error', 
        isConnected: false,
        error: `Failed to create WebSocket: ${error}`
      });
    }
  }, [user, accessToken, getWebSocketUrl, updateState, startHeartbeat, stopHeartbeat, ping, state.reconnectAttempts, clearTimeouts]);

  const disconnect = useCallback(() => {
    clearTimeouts();
    stopHeartbeat();
    
    if (wsRef.current) {
      wsRef.current.close(1000, 'User initiated disconnect');
      wsRef.current = null;
    }
    
    updateState({ 
      status: 'disconnected', 
      isConnected: false,
      reconnectAttempts: 0,
      error: null
    });
  }, [clearTimeouts, stopHeartbeat, updateState]);

  const getConnectionQuality = useCallback((): 'excellent' | 'good' | 'fair' | 'poor' | 'unknown' => {
    if (!state.isConnected || state.latency === null) return 'unknown';
    
    if (state.latency < 100) return 'excellent';
    if (state.latency < 200) return 'good';
    if (state.latency < 500) return 'fair';
    return 'poor';
  }, [state.isConnected, state.latency]);

  // Auto-connect when user and token are available
  useEffect(() => {
    if (user?.account?.id && accessToken) {
      connect();
    } else {
      disconnect();
    }

    return () => {
      disconnect();
    };
  }, [user?.account?.id, accessToken]); // Depend on account ID and token

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      disconnect();
    };
  }, []);

  return {
    ...state,
    connect,
    disconnect,
    ping,
    getConnectionQuality,
  };
};