import { useEffect, useCallback, useState, useRef } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { refreshAccessToken } from '../services/slices/authSlice';
import { wsManager } from '@/shared/services/WebSocketManager';

// WebSocket connection state
interface WebSocketState {
  isConnected: boolean;
  error: string | null;
  lastConnected: Date | null;
}

// Channel subscription interface
interface ChannelSubscription {
  channel: string;
  params?: Record<string, any>;
  onMessage?: (data: unknown) => void;
  onError?: (error: string) => void;
}

interface UseWebSocketReturn {
  isConnected: boolean;
  error: string | null;
  lastConnected: Date | null;
  subscribe: (subscription: ChannelSubscription) => () => void;
  sendMessage: (channel: string, action: string, data?: any, params?: Record<string, any>) => Promise<boolean>;
}

/**
 * Custom hook for WebSocket connections
 *
 * Uses a singleton WebSocket manager to share a single connection
 * across all components in the application.
 *
 * Benefits:
 * - Reduces resource usage (single connection for entire app)
 * - Centralized connection management
 * - Automatic reconnection handling
 * - Proper cleanup on unmount
 */
export const useWebSocket = (): UseWebSocketReturn => {
  const { user, access_token: accessToken } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch<AppDispatch>();

  const mountedRef = useRef<boolean>(true);
  const refreshingTokenRef = useRef<boolean>(false);

  const [state, setState] = useState<WebSocketState>({
    isConnected: false,
    error: null,
    lastConnected: null,
  });

  /**
   * Get WebSocket URL with authentication
   */
  const getWebSocketUrl = useCallback(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';

    // Use environment-aware host resolution
    let host = window.location.hostname;
    let port = ':3000';

    // Handle different development environments
    if (host === 'localhost' || host === '127.0.0.1') {
      // Local development
      port = ':3000';
    } else {
      // Check if we're behind a reverse proxy
      const isDirectDevConnection = window.location.port && !['80', '443'].includes(window.location.port);

      // Standard proxy ports indicate we're behind a reverse proxy
      const isStandardPort =
        (window.location.protocol === 'https:' && (!window.location.port || window.location.port === '443')) ||
        (window.location.protocol === 'http:' && (!window.location.port || window.location.port === '80'));

      const isProxied = isStandardPort && !isDirectDevConnection;

      if (isProxied) {
        // Behind reverse proxy - use same port as frontend
        port = window.location.port ? `:${window.location.port}` : '';
      } else {
        // Direct development access - use backend port
        port = ':3000';
      }
    }

    const baseUrl = `${protocol}//${host}${port}/cable`;
    const wsUrl = accessToken ? `${baseUrl}?token=${encodeURIComponent(accessToken)}` : baseUrl;

    return wsUrl;
  }, [accessToken]);

  /**
   * Send message to a channel
   */
  const sendMessage = useCallback(async (
    channel: string,
    action: string,
    data?: any,
    params?: Record<string, any>
  ): Promise<boolean> => {
    return wsManager.sendMessage(channel, action, data, params);
  }, []);

  /**
   * Subscribe to a channel
   */
  const subscribe = useCallback((subscription: ChannelSubscription) => {
    return wsManager.subscribe(subscription);
  }, []);

  /**
   * Handle token refresh on unauthorized disconnect
   */
  const handleUnauthorized = useCallback(() => {
    if (refreshingTokenRef.current || !mountedRef.current) {
      return;
    }

    refreshingTokenRef.current = true;

    dispatch(refreshAccessToken())
      .unwrap()
      .then(() => {
        refreshingTokenRef.current = false;
        wsManager.resetTokenRefreshFlag();

        // Reconnect with new token
        if (mountedRef.current && user?.account?.id) {
          setTimeout(() => {
            wsManager.reconnect();
          }, 1000);
        }
      })
      .catch(() => {
        refreshingTokenRef.current = false;
        wsManager.resetTokenRefreshFlag();

        if (mountedRef.current) {
          setState(prev => ({
            ...prev,
            error: 'Session expired - please login again',
            isConnected: false
          }));
        }
      });
  }, [dispatch, user]);

  /**
   * Initialize WebSocket manager when component mounts
   * The manager itself ensures only one initialization happens globally
   */
  useEffect(() => {
    mountedRef.current = true;

    if (user?.account?.id && accessToken) {
      wsManager.initialize({
        getUrl: getWebSocketUrl,
        onConnect: () => {
          if (mountedRef.current) {
            setState({
              isConnected: true,
              error: null,
              lastConnected: new Date()
            });
          }
        },
        onDisconnect: (code, reason) => {
          if (!mountedRef.current) return;

          let errorMessage: string | null = null;
          if (code === 1006) {
            errorMessage = 'Connection lost unexpectedly - check network';
          } else if (code === 1008) {
            errorMessage = 'Connection closed due to policy violation';
          } else if (code !== 1000) {
            errorMessage = reason || 'Connection lost';
          }

          setState(prev => ({
            ...prev,
            isConnected: false,
            error: errorMessage
          }));
        },
        onError: () => {
          if (mountedRef.current) {
            setState(prev => ({
              ...prev,
              isConnected: false,
              error: 'WebSocket connection error'
            }));
          }
        }
      });
    }

    return () => {
      mountedRef.current = false;
    };
  }, [user?.account?.id, accessToken, getWebSocketUrl]);

  /**
   * Listen to state changes from the WebSocket manager
   */
  useEffect(() => {
    const unsubscribe = wsManager.addStateListener((isConnected, error) => {
      if (!mountedRef.current) return;

      setState(prev => ({
        isConnected,
        error: error || prev.error,
        lastConnected: isConnected ? new Date() : prev.lastConnected
      }));

      // Handle unauthorized disconnect
      if (error === 'Session expired') {
        handleUnauthorized();
      }
    });

    // Sync initial state
    setState(prev => ({
      ...prev,
      isConnected: wsManager.getIsConnected()
    }));

    return unsubscribe;
  }, [handleUnauthorized]);

  /**
   * Disconnect when user logs out
   */
  useEffect(() => {
    if (!user?.account?.id || !accessToken) {
      wsManager.disconnect();
    }
  }, [user?.account?.id, accessToken]);

  return {
    isConnected: state.isConnected,
    error: state.error,
    lastConnected: state.lastConnected,
    subscribe,
    sendMessage
  };
};
