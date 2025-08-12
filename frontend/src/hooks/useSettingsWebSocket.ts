import { useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../store';
import { useWebSocketConnection } from './useWebSocketConnection';
import { UserSettings } from '../services/settingsApi';

interface SettingsWebSocketMessage {
  type: 'settings_updated' | 'preferences_updated' | 'notifications_updated' | 'profile_updated';
  data: Partial<UserSettings>;
  userId: string;
  timestamp: string;
}

interface UseSettingsWebSocketOptions {
  onSettingsUpdate?: (data: Partial<UserSettings>) => void;
  onPreferencesUpdate?: (data: any) => void;
  onNotificationsUpdate?: (data: any) => void;
  onProfileUpdate?: (data: any) => void;
  enabled?: boolean;
}

export const useSettingsWebSocket = ({
  onSettingsUpdate,
  onPreferencesUpdate,
  onNotificationsUpdate,
  onProfileUpdate,
  enabled = true
}: UseSettingsWebSocketOptions = {}) => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { isConnected } = useWebSocketConnection();

  // Broadcast settings update to other tabs/sessions (placeholder - actual broadcasting happens on server)
  const broadcastSettingsUpdate = useCallback((type: SettingsWebSocketMessage['type'], data: any) => {
    // The actual broadcasting happens server-side when settings are updated via API
    // This function is kept for compatibility but doesn't need to do anything
    // since the server will broadcast the change to all connected clients
    console.log(`Settings update broadcasted: ${type}`, data);
  }, []);

  // Listen for settings updates through a global event system
  useEffect(() => {
    if (!enabled || !user?.id) return;

    const handleSettingsMessage = (event: CustomEvent) => {
      const message = event.detail;
      
      // Only process messages for this user
      if (message.userId === user.id) {
        switch (message.type) {
          case 'settings_updated':
            onSettingsUpdate?.(message.data);
            break;
          case 'preferences_updated':
            onPreferencesUpdate?.(message.data);
            break;
          case 'notifications_updated':
            onNotificationsUpdate?.(message.data);
            break;
          case 'profile_updated':
            onProfileUpdate?.(message.data);
            break;
        }
      }
    };

    // Listen for custom settings events
    window.addEventListener('settings-websocket-message', handleSettingsMessage as EventListener);

    return () => {
      window.removeEventListener('settings-websocket-message', handleSettingsMessage as EventListener);
    };
  }, [enabled, user?.id, onSettingsUpdate, onPreferencesUpdate, onNotificationsUpdate, onProfileUpdate]);

  return {
    isConnected,
    broadcastSettingsUpdate
  };
};

// Convenience hooks for specific settings types
export const usePreferencesWebSocket = (
  onUpdate: (data: any) => void, 
  enabled = true
) => {
  return useSettingsWebSocket({
    onPreferencesUpdate: onUpdate,
    enabled
  });
};

export const useNotificationsWebSocket = (
  onUpdate: (data: any) => void, 
  enabled = true
) => {
  return useSettingsWebSocket({
    onNotificationsUpdate: onUpdate,
    enabled
  });
};

export const useProfileWebSocket = (
  onUpdate: (data: any) => void, 
  enabled = true
) => {
  return useSettingsWebSocket({
    onProfileUpdate: onUpdate,
    enabled
  });
};