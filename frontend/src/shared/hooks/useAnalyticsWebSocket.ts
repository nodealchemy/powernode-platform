import { useCallback, useRef, useEffect } from 'react';
import { useWebSocket } from './useWebSocket';

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
  const { isConnected, subscribe, sendMessage, error: connectionError } = useWebSocket();
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Store latest callback refs to avoid dependency issues
  const onAnalyticsUpdateRef = useRef(onAnalyticsUpdate);
  const onErrorRef = useRef(onError);
  
  onAnalyticsUpdateRef.current = onAnalyticsUpdate;
  onErrorRef.current = onError;

  // Handle incoming messages
  const handleMessage = useCallback((data: any) => {
    if (data.type === 'analytics_update' && data.data) {
      onAnalyticsUpdateRef.current?.(data.data);
    } else if (data.type === 'error') {
      onErrorRef.current?.(data.message || 'Analytics error');
    }
  }, []);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    console.error('❌ Analytics channel error:', errorMessage);
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to analytics channel
  const subscribeToAnalytics = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }
    
    unsubscribeRef.current = subscribe({
      channel: 'AnalyticsChannel',
      onMessage: handleMessage,
      onError: handleError
    });
    
  }, [subscribe, handleMessage, handleError]);

  // Request analytics update
  const requestAnalyticsUpdate = useCallback(async () => {
    if (!isConnected) {
      console.warn('Cannot request analytics: WebSocket not connected');
      return;
    }
    
    await sendMessage('AnalyticsChannel', 'request_analytics');
  }, [isConnected, sendMessage]);

  // Auto-subscribe when connected
  useEffect(() => {
    if (isConnected) {
      subscribeToAnalytics();
    }
    
    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [isConnected, subscribeToAnalytics]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    requestAnalyticsUpdate,
    error: connectionError
  };
};