import { useEffect, useRef, useCallback, useState } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '../store';
import { refreshAccessToken } from '../store/slices/authSlice';

// Simplified WebSocket connection state
interface WebSocketState {
  isConnected: boolean;
  error: string | null;
  lastConnected: Date | null;
}

// Simple channel subscription
interface ChannelSubscription {
  channel: string;
  onMessage?: (data: any) => void;
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
  
  const [state, setState] = useState<WebSocketState>({
    isConnected: false,
    error: null,
    lastConnected: null,
  });

  // Get WebSocket URL with authentication
  const getWebSocketUrl = useCallback(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.hostname;
    const port = host === 'localhost' || host === '127.0.0.1' ? ':3000' : ':3000';
    const baseUrl = `${protocol}//${host}${port}/cable`;
    
    return accessToken ? `${baseUrl}?token=${encodeURIComponent(accessToken)}` : baseUrl;
  }, [accessToken]);

  // Send message safely
  const sendMessage = useCallback(async (channel: string, action: string, data?: any): Promise<boolean> => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
      console.warn('WebSocket not connected');
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
      console.error('Failed to send WebSocket message:', error);
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
        console.log(`📡 Subscribed to ${channel}`);
      } catch (error) {
        console.error(`Failed to subscribe to ${channel}:`, error);
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
          console.log(`📡 Unsubscribed from ${channel}`);
        } catch (error) {
          console.error(`Failed to unsubscribe from ${channel}:`, error);
        }
      }
    };
  }, [user?.account?.id]);

  // Connect to WebSocket
  const connect = useCallback(() => {
    if (!user?.account?.id || !accessToken) {
      console.log('Cannot connect: missing user or token');
      return;
    }

    if (wsRef.current?.readyState === WebSocket.CONNECTING || 
        wsRef.current?.readyState === WebSocket.OPEN) {
      return;
    }

    // Clear any existing reconnect timeout
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }

    try {
      const wsUrl = getWebSocketUrl();
      console.log('🔌 Connecting to WebSocket:', wsUrl.replace(/token=[^&]+/, 'token=***'));
      
      wsRef.current = new WebSocket(wsUrl);

      wsRef.current.onopen = () => {
        console.log('✅ WebSocket connected');
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
            console.log(`🔄 Re-subscribed to ${channel}`);
          } catch (error) {
            console.error(`Failed to re-subscribe to ${channel}:`, error);
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
            console.log('🔄 Token expired, refreshing...');
            dispatch(refreshAccessToken()).then(() => {
              setTimeout(connect, 1000);
            });
            return;
          }

          // Handle confirmation and rejection
          if (data.type === 'confirm_subscription') {
            console.log('✅ Subscription confirmed:', data.identifier);
            return;
          }

          if (data.type === 'reject_subscription') {
            console.error('❌ Subscription rejected:', data.identifier);
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
              console.error('Error parsing message identifier:', error);
            }
          }

        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      wsRef.current.onclose = (event) => {
        console.log('❌ WebSocket disconnected:', event.code, event.reason);
        setState(prev => ({
          ...prev,
          isConnected: false,
          error: event.code !== 1000 ? `Connection closed: ${event.reason || 'Unknown'}` : null
        }));

        // Auto-reconnect after 3 seconds if not a normal closure
        if (event.code !== 1000) {
          reconnectTimeoutRef.current = setTimeout(connect, 3000);
        }
      };

      wsRef.current.onerror = (error) => {
        console.error('💥 WebSocket error:', error);
        setState(prev => ({
          ...prev,
          isConnected: false,
          error: 'WebSocket connection error'
        }));
      };

    } catch (error) {
      console.error('Failed to create WebSocket:', error);
      setState(prev => ({
        ...prev,
        isConnected: false,
        error: `Failed to create WebSocket: ${error}`
      }));
    }
  }, [user, accessToken, getWebSocketUrl, dispatch]);

  // Disconnect WebSocket
  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
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

  // Auto-connect/disconnect based on auth state
  useEffect(() => {
    if (user?.account?.id && accessToken) {
      connect();
    } else {
      disconnect();
    }

    return disconnect;
  }, [user?.account?.id, accessToken, connect, disconnect]);

  return {
    isConnected: state.isConnected,
    error: state.error,
    lastConnected: state.lastConnected,
    subscribe,
    sendMessage
  };
};