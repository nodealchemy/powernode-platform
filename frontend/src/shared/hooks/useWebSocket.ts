import { useEffect, useCallback, useState, useRef } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { refreshAccessToken, applyRefreshedTokens } from '@/shared/services/slices/authSlice';
import { setMaintenanceMode } from '@/shared/services/slices/uiSlice';
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
  params?: Record<string, unknown>;
  onMessage?: (data: unknown) => void;
  onError?: (error: string) => void;
}

interface UseWebSocketReturn {
  isConnected: boolean;
  error: string | null;
  lastConnected: Date | null;
  subscribe: (subscription: ChannelSubscription) => () => void;
  sendMessage: (channel: string, action: string, data?: Record<string, unknown>, params?: Record<string, unknown>) => Promise<boolean>;
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
  const { user, access_token: accessToken, refresh_token: refreshToken } = useSelector((state: RootState) => state.auth);
  const maintenanceActive = useSelector((state: RootState) => state.ui?.maintenance?.active ?? false);
  const dispatch = useDispatch<AppDispatch>();

  const mountedRef = useRef<boolean>(true);
  const refreshingTokenRef = useRef<boolean>(false);
  // Tracks the PREVIOUS maintenanceActive value so the reconnect-on-clear
  // effect below can tell "just transitioned true -> false" apart from
  // "was already false at mount" — without this, every mount with an
  // unconnected session (the common case, before the WS has connected at
  // all) would call reconnect() unconditionally.
  const wasMaintenanceActiveRef = useRef<boolean>(maintenanceActive);

  const [state, setState] = useState<WebSocketState>({
    isConnected: false,
    error: null,
    lastConnected: null,
  });

  /**
   * Get WebSocket URL with authentication.
   *
   * Includes both `token` (access) and `refresh_token` query params when
   * available. The server-side ApplicationCable::Connection prefers the
   * access token; if it's expired and the refresh token is valid, the
   * server mints fresh tokens and pushes them down via an `auth_refreshed`
   * system message. Avoids an HTTP /auth/refresh roundtrip on reconnect.
   */
  const getWebSocketUrl = useCallback(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';

    // Use environment-aware host resolution
    const host = window.location.hostname;
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
    const params: string[] = [];
    if (accessToken) params.push(`token=${encodeURIComponent(accessToken)}`);
    if (refreshToken) params.push(`refresh_token=${encodeURIComponent(refreshToken)}`);
    return params.length > 0 ? `${baseUrl}?${params.join('&')}` : baseUrl;
  }, [accessToken, refreshToken]);

  /**
   * Send message to a channel
   */
  const sendMessage = useCallback(async (
    channel: string,
    action: string,
    data?: Record<string, unknown>,
    params?: Record<string, unknown>
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
        onAuthRefreshed: (tokens) => {
          // Server pushed fresh tokens after accepting our refresh_token on
          // an expired access_token. Swap them into auth state synchronously
          // so subsequent HTTP calls + the next WS reconnect use the new pair.
          if (mountedRef.current) {
            dispatch(applyRefreshedTokens({
              access_token: tokens.access_token,
              refresh_token: tokens.refresh_token,
            }));
          }
        },
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
        },
        onMaintenanceMode: (message, estimatedCompletion) => {
          // N2: the server closed with reason: 'maintenance_mode' — set the
          // SAME flag api.ts's HTTP interceptor sets on a 503, so
          // MaintenanceScreen takes over regardless of which channel
          // (HTTP or cable) noticed first. wsManager itself already stopped
          // reconnecting (see WebSocketManager#connect's guard); the
          // maintenance-cleared effect below is what resumes it.
          //
          // Item 7b: skip the dispatch when HTTP already set the flag —
          // Rails' Connection#close(reason:, reconnect:) can't carry a
          // custom message/estimated_completion, so this callback's own
          // args are currently always undefined; overwriting an
          // HTTP-sourced message with `undefined` would blank it out for no
          // reason. wasMaintenanceActiveRef mirrors the latest known
          // ui.maintenance.active (kept in sync by the effect below), not a
          // stale value closed over at mount.
          if (mountedRef.current && !wasMaintenanceActiveRef.current) {
            dispatch(setMaintenanceMode({ message, estimatedCompletion }));
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

  /**
   * N2: keep wsManager's reconnect guard in sync with ui.maintenance.active
   * — the single source of truth, since a maintenance flag can be set by
   * EITHER the HTTP interceptor (api.ts, on a 503) or the cable
   * onMaintenanceMode callback above. When it clears, proactively reconnect
   * if we still hold a session: wsManager's #connect() never scheduled
   * itself while the guard was up, so nothing else will do this.
   */
  useEffect(() => {
    wsManager.setMaintenanceActive(maintenanceActive);

    const justCleared = wasMaintenanceActiveRef.current && !maintenanceActive;
    wasMaintenanceActiveRef.current = maintenanceActive;

    if (justCleared && user?.account?.id && accessToken && !wsManager.getIsConnected()) {
      wsManager.reconnect();
    }
  }, [maintenanceActive, user?.account?.id, accessToken]);

  return {
    isConnected: state.isConnected,
    error: state.error,
    lastConnected: state.lastConnected,
    subscribe,
    sendMessage
  };
};
