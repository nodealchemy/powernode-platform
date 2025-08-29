import { useEffect, useRef, useCallback, useState } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { refreshAccessToken } from '../services/slices/authSlice';

// Simplified WebSocket connection state
interface WebSocketState {
  isConnected: boolean;
  error: string | null;
  lastConnected: Date | null;
}

// Simple channel subscription
interface ChannelSubscription {
  channel: string;
  onMessage?: (data: unknown) => void;
  onError?: (error: string) => void;
}

interface UseWebSocketReturn {
  isConnected: boolean;
  error: string | null;
  lastConnected: Date | null;
  subscribe: (subscription: ChannelSubscription) => () => void;
  sendMessage: (channel: string, action: string, data?: any) => Promise<boolean>;
}

export const useWebSocket = (): UseWebSocketReturn => {
  const { user, accessToken } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch<AppDispatch>();
  
  const wsRef = useRef<WebSocket | null>(null);
  const subscriptionsRef = useRef<Map<string, ChannelSubscription>>(new Map());
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const connectingRef = useRef<boolean>(false);
  const mountedRef = useRef<boolean>(true);
  const connectionDebounceRef = useRef<NodeJS.Timeout | null>(null);
  
  const [state, setState] = useState<WebSocketState>({
    isConnected: false,
    error: null,
    lastConnected: null,
  });

  // Get WebSocket URL with authentication
  const getWebSocketUrl = useCallback(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    
    // Use environment-aware host resolution
    let host = window.location.hostname;
    let port = ':3000';
    
    // Handle different development environments
    if (host === 'localhost' || host === '127.0.0.1') {
      // Local development
      port = ':3000';
    } else if (host.includes('ipnode.net')) {
      // Development server environment - use the backend port
      port = ':3000';
    } else {
      // Production or other environments
      port = window.location.port ? `:${window.location.port}` : '';
    }
    
    const baseUrl = `${protocol}//${host}${port}/cable`;
    
    return accessToken ? `${baseUrl}?token=${encodeURIComponent(accessToken)}` : baseUrl;
  }, [accessToken]);

  // Send message safely
  const sendMessage = useCallback(async (channel: string, action: string, data?: any): Promise<boolean> => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
      return false;
    }

    const message = {
      command: 'message',
      identifier: JSON.stringify({ 
        channel, 
        account_id: user?.account?.id 
      }),
      data: JSON.stringify({ action, ...data })
    };

    try {
      wsRef.current.send(JSON.stringify(message));
      return true;
    } catch (error) {
      return false;
    }
  }, [user?.account?.id]);

  // Subscribe to a channel
  const subscribe = useCallback((subscription: ChannelSubscription) => {
    const { channel, onError } = subscription;
    
    // Store subscription
    subscriptionsRef.current.set(channel, subscription);

    // Subscribe if connected
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      const subscribeMessage = {
        command: 'subscribe',
        identifier: JSON.stringify({ 
          channel, 
          account_id: user?.account?.id 
        })
      };
      
      try {
        wsRef.current.send(JSON.stringify(subscribeMessage));
      } catch (error) {
        onError?.('Failed to subscribe to channel');
      }
    }

    // Return unsubscribe function
    return () => {
      subscriptionsRef.current.delete(channel);
      
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        const unsubscribeMessage = {
          command: 'unsubscribe',
          identifier: JSON.stringify({ 
            channel, 
            account_id: user?.account?.id 
          })
        };
        
        try {
          wsRef.current.send(JSON.stringify(unsubscribeMessage));
        } catch (error) {
        }
      }
    };
  }, [user?.account?.id]);

  // Connect to WebSocket with debouncing
  const connect = useCallback(() => {
    if (!user?.account?.id || !accessToken || !mountedRef.current) {
      // This is expected when user is not logged in or during component unmount
      if (!mountedRef.current) {
        // Component unmounted, no need to log
        return;
      }
      if (!user?.account?.id && !accessToken) {
        // User not logged in - this is normal, no need to log
        return;
      }
      // Only log if we have partial auth state (which might indicate an issue)
      if (user && !user.account?.id) {
      } else if (!accessToken && user) {
      }
      return;
    }

    // Prevent overlapping connection attempts
    if (connectingRef.current || 
        wsRef.current?.readyState === WebSocket.CONNECTING || 
        wsRef.current?.readyState === WebSocket.OPEN) {
      return;
    }

    // Clear any existing debounce timeout
    if (connectionDebounceRef.current) {
      clearTimeout(connectionDebounceRef.current);
      connectionDebounceRef.current = null;
    }

    // Debounce connection attempts to handle StrictMode
    connectionDebounceRef.current = setTimeout(() => {
      if (!mountedRef.current || !user?.account?.id || !accessToken) {
        return;
      }

      connectingRef.current = true;

      // Clear any existing reconnect timeout
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
      }

      // Close any existing connection before creating new one
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }

      try {
        const wsUrl = getWebSocketUrl();
        
        wsRef.current = new WebSocket(wsUrl);

      wsRef.current.onopen = () => {
        if (!mountedRef.current) return;
        
        connectingRef.current = false;
        setState({
          isConnected: true,
          error: null,
          lastConnected: new Date()
        });

        // Re-subscribe to all channels
        subscriptionsRef.current.forEach((subscription, channel) => {
          const subscribeMessage = {
            command: 'subscribe',
            identifier: JSON.stringify({ 
              channel, 
              account_id: user.account?.id 
            })
          };
          
          try {
            wsRef.current?.send(JSON.stringify(subscribeMessage));
          } catch (error) {
          }
        });
      };

      wsRef.current.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          
          // Handle system messages
          if (data.type === 'welcome' || data.type === 'ping') {
            return;
          }

          // Handle disconnect (authentication failure)
          if (data.type === 'disconnect' && data.reason === 'unauthorized') {
            dispatch(refreshAccessToken())
              .unwrap()
              .then(() => {
                setTimeout(connect, 1000);
              })
              .catch((error) => {
                setState(prev => ({
                  ...prev,
                  error: 'Authentication failed - please login again'
                }));
              });
            return;
          }

          // Handle confirmation and rejection
          if (data.type === 'confirm_subscription') {
            return;
          }

          if (data.type === 'reject_subscription') {
            return;
          }

          // Route messages to channel handlers
          if (data.identifier) {
            try {
              const identifier = JSON.parse(data.identifier);
              const subscription = subscriptionsRef.current.get(identifier.channel);
              
              if (subscription?.onMessage && data.message) {
                subscription.onMessage(data.message);
              }
            } catch (error) {
            }
          }

        } catch (error) {
        }
      };

      wsRef.current.onclose = (event) => {
        connectingRef.current = false;
        if (!mountedRef.current) return;
        
        
        // Check for specific error codes
        let errorMessage: string | null = null;
        if (event.code === 1006) {
          errorMessage = 'Connection lost unexpectedly - check network';
        } else if (event.code === 1008) {
          errorMessage = 'Connection closed due to policy violation';
        } else if (event.code !== 1000) {
          errorMessage = `Connection closed: ${event.reason || 'Connection lost'}`;
        }
        
        setState(prev => ({
          ...prev,
          isConnected: false,
          error: errorMessage
        }));

        // Auto-reconnect after 3 seconds if not a normal closure and user is still authenticated
        if (event.code !== 1000 && accessToken && user?.account?.id && mountedRef.current) {
          reconnectTimeoutRef.current = setTimeout(() => {
            if (mountedRef.current) {
              connect();
            }
          }, 3000);
        } else if (event.code !== 1000) {
        }
      };

      wsRef.current.onerror = (error) => {
        connectingRef.current = false;
        if (!mountedRef.current) return;
        
        setState(prev => ({
          ...prev,
          isConnected: false,
          error: 'WebSocket connection error'
        }));
        
        // Close the connection to prevent "closed before connection established" errors
        if (wsRef.current && wsRef.current.readyState !== WebSocket.CLOSED) {
          wsRef.current.close();
          wsRef.current = null;
        }
      };

    } catch (error) {
      connectingRef.current = false;
      setState(prev => ({
        ...prev,
        isConnected: false,
        error: `Failed to create WebSocket: ${error}`
      }));
    }
    }, 100); // 100ms debounce to handle StrictMode double invocation
  }, [user, accessToken, getWebSocketUrl, dispatch]);

  // Disconnect WebSocket
  const disconnect = useCallback(() => {
    connectingRef.current = false;
    
    // Clear all timeouts
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    
    if (connectionDebounceRef.current) {
      clearTimeout(connectionDebounceRef.current);
      connectionDebounceRef.current = null;
    }

    if (wsRef.current) {
      wsRef.current.close(1000, 'User disconnect');
      wsRef.current = null;
    }

    subscriptionsRef.current.clear();
    setState({
      isConnected: false,
      error: null,
      lastConnected: null
    });
  }, []);

  // Set mounted state
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // Auto-connect/disconnect based on auth state
  useEffect(() => {
    
    if (user?.account?.id && accessToken) {
      connect();
    } else {
      disconnect();
    }

    return () => {
      disconnect();
    };
  }, [user?.account?.id, accessToken, connect, disconnect]);

  return {
    isConnected: state.isConnected,
    error: state.error,
    lastConnected: state.lastConnected,
    subscribe,
    sendMessage
  };
};