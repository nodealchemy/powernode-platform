import { useCallback, useRef, useEffect } from 'react';
import { useWebSocket } from './useWebSocket';

interface SettingsWebSocketOptions {
  onSettingsUpdate?: (data: any) => void;
  onPreferencesUpdate?: (data: any) => void;
  onNotificationsUpdate?: (data: any) => void;
  onProfileUpdate?: (data: any) => void;
  onError?: (error: string) => void;
}

export const useSettingsWebSocket = ({
  onSettingsUpdate,
  onPreferencesUpdate,
  onNotificationsUpdate,
  onProfileUpdate,
  onError
}: SettingsWebSocketOptions) => {
  const { isConnected, subscribe, sendMessage, error: connectionError } = useWebSocket();
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Store latest callback refs to avoid dependency issues
  const onSettingsUpdateRef = useRef(onSettingsUpdate);
  const onPreferencesUpdateRef = useRef(onPreferencesUpdate);
  const onNotificationsUpdateRef = useRef(onNotificationsUpdate);
  const onProfileUpdateRef = useRef(onProfileUpdate);
  const onErrorRef = useRef(onError);
  
  onSettingsUpdateRef.current = onSettingsUpdate;
  onPreferencesUpdateRef.current = onPreferencesUpdate;
  onNotificationsUpdateRef.current = onNotificationsUpdate;
  onProfileUpdateRef.current = onProfileUpdate;
  onErrorRef.current = onError;

  // Handle incoming messages
  const handleMessage = useCallback((data: any) => {
    switch (data.type) {
      case 'settings_updated':
        onSettingsUpdateRef.current?.(data);
        break;
      
      case 'preferences_updated':
        onPreferencesUpdateRef.current?.(data);
        break;
        
      case 'notifications_updated':
        onNotificationsUpdateRef.current?.(data);
        break;
        
      case 'profile_updated':
        onProfileUpdateRef.current?.(data);
        break;
        
      case 'pong':
        // Handle ping/pong if needed
        break;
        
      case 'error':
        onErrorRef.current?.(data.message || 'Settings channel error');
        break;
    }
  }, []);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    console.error('❌ Settings channel error:', errorMessage);
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to notification channel (settings are delivered via notifications)
  const subscribeToSettings = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }
    
    unsubscribeRef.current = subscribe({
      channel: 'NotificationChannel',
      onMessage: handleMessage,
      onError: handleError
    });
    
  }, [subscribe, handleMessage, handleError]);

  // Request settings sync
  const requestSettingsSync = useCallback(async () => {
    if (!isConnected) {
      console.warn('Cannot sync settings: WebSocket not connected');
      return;
    }
    
    await sendMessage('NotificationChannel', 'sync_settings');
  }, [isConnected, sendMessage]);

  // Ping the connection
  const ping = useCallback(async () => {
    if (!isConnected) {
      console.warn('Cannot ping: WebSocket not connected');
      return;
    }
    
    await sendMessage('NotificationChannel', 'ping');
  }, [isConnected, sendMessage]);

  // Auto-subscribe when connected
  useEffect(() => {
    if (isConnected) {
      subscribeToSettings();
    }
    
    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [isConnected, subscribeToSettings]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    requestSettingsSync,
    ping,
    error: connectionError
  };
};