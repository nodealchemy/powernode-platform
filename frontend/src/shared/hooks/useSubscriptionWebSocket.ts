import { useCallback, useRef, useEffect } from 'react';
import { useWebSocket } from './useWebSocket';

interface SubscriptionWebSocketOptions {
  onSubscriptionUpdate?: (data: any) => void;
  onSubscriptionCancelled?: (data: any) => void;
  onPaymentProcessed?: (data: any) => void;
  onTrialEnding?: (data: any) => void;
  onError?: (error: string) => void;
}

export const useSubscriptionWebSocket = ({
  onSubscriptionUpdate,
  onSubscriptionCancelled,
  onPaymentProcessed,
  onTrialEnding,
  onError
}: SubscriptionWebSocketOptions) => {
  const { isConnected, subscribe, sendMessage, error: connectionError } = useWebSocket();
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Store latest callback refs to avoid dependency issues
  const onSubscriptionUpdateRef = useRef(onSubscriptionUpdate);
  const onSubscriptionCancelledRef = useRef(onSubscriptionCancelled);
  const onPaymentProcessedRef = useRef(onPaymentProcessed);
  const onTrialEndingRef = useRef(onTrialEnding);
  const onErrorRef = useRef(onError);
  
  onSubscriptionUpdateRef.current = onSubscriptionUpdate;
  onSubscriptionCancelledRef.current = onSubscriptionCancelled;
  onPaymentProcessedRef.current = onPaymentProcessed;
  onTrialEndingRef.current = onTrialEnding;
  onErrorRef.current = onError;

  // Handle incoming messages
  const handleMessage = useCallback((data: any) => {
    switch (data.type) {
      case 'subscription_updated':
        onSubscriptionUpdateRef.current?.(data);
        break;
      
      case 'subscription_cancelled':
        onSubscriptionCancelledRef.current?.(data);
        break;
        
      case 'payment_processed':
        onPaymentProcessedRef.current?.(data);
        break;
        
      case 'trial_ending':
        onTrialEndingRef.current?.(data);
        break;
        
      case 'error':
        onErrorRef.current?.(data.message || 'Subscription channel error');
        break;
    }
  }, []);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    console.error('❌ Subscription channel error:', errorMessage);
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to subscription channel
  const subscribeToSubscriptions = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }
    
    unsubscribeRef.current = subscribe({
      channel: 'SubscriptionChannel',
      onMessage: handleMessage,
      onError: handleError
    });
    
  }, [subscribe, handleMessage, handleError]);

  // Request subscription updates
  const requestSubscriptionUpdate = useCallback(async (subscriptionId?: string) => {
    if (!isConnected) {
      console.warn('Cannot request subscription update: WebSocket not connected');
      return;
    }
    
    await sendMessage('SubscriptionChannel', 'request_update', { 
      subscription_id: subscriptionId 
    });
  }, [isConnected, sendMessage]);

  // Monitor subscription status
  const monitorSubscription = useCallback(async (subscriptionId: string) => {
    if (!isConnected) {
      console.warn('Cannot monitor subscription: WebSocket not connected');
      return;
    }
    
    await sendMessage('SubscriptionChannel', 'monitor', { 
      subscription_id: subscriptionId 
    });
  }, [isConnected, sendMessage]);

  // Auto-subscribe when connected
  useEffect(() => {
    if (isConnected) {
      subscribeToSubscriptions();
    }
    
    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [isConnected, subscribeToSubscriptions]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    requestSubscriptionUpdate,
    monitorSubscription,
    error: connectionError
  };
};