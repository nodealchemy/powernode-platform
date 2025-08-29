import { useCallback, useRef, useEffect } from 'react';
import { useWebSocket } from './useWebSocket';

interface AnalyticsWebSocketOptions {
  onAnalyticsUpdate?: (data: unknown) => void;
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

  // Type guard for WebSocket message data
  const isWebSocketMessage = (data: unknown): data is { type: string; data?: any; message?: string } => {
    return typeof data === 'object' && data !== null && 'type' in data;
  };

  // Handle incoming messages
  const handleMessage = useCallback((data: unknown) => {
    if (!isWebSocketMessage(data)) return;
    
    if (data.type === 'analytics_update' && data.data) {
      onAnalyticsUpdateRef.current?.(data.data);
    } else if (data.type === 'error') {
      onErrorRef.current?.(data.message || 'Analytics error');
    }
  }, []);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to analytics channel - memoize to prevent recreations
  const subscribeToAnalytics = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }
    
    unsubscribeRef.current = subscribe({
      channel: 'AnalyticsChannel',
      onMessage: handleMessage,
      onError: handleError
    });
    
  }, [subscribe]); // Remove handleMessage, handleError to prevent recreations

  // Request analytics update
  const requestAnalyticsUpdate = useCallback(async () => {
    if (!isConnected) {
      return;
    }
    
    await sendMessage('AnalyticsChannel', 'request_analytics');
  }, [isConnected, sendMessage]);

  // Auto-subscribe when connected - but only once
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
  }, [isConnected]); // Remove subscribeToAnalytics dependency to prevent recreation

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