import { useCallback, useRef, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { logger } from '@/shared/utils/logger';

// Notification event types
type NotificationEventType =
  | 'connection_established'
  | 'new_notification'
  | 'notification_read'
  | 'notification_dismissed'
  | 'pong'
  | 'error';

// Notification payload interface
export interface WebSocketNotification {
  id: string;
  notification_type: string;
  title: string;
  message: string;
  severity: 'info' | 'warning' | 'error' | 'success';
  action_url?: string;
  action_label?: string;
  icon?: string;
  category?: string;
  metadata?: Record<string, unknown>;
  created_at: string;
}

interface NotificationWebSocketOptions {
  onNewNotification?: (notification: WebSocketNotification) => void;
  onNotificationRead?: (notificationId: string) => void;
  onNotificationDismissed?: (notificationId: string) => void;
  onConnected?: () => void;
  onError?: (error: string) => void;
}

export const useNotificationWebSocket = ({
  onNewNotification,
  onNotificationRead,
  onNotificationDismissed,
  onConnected,
  onError
}: NotificationWebSocketOptions) => {
  const { isConnected, subscribe, sendMessage, error: connectionError } = useWebSocket();
  const user = useSelector((state: RootState) => state.auth.user);
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Store latest callback refs to avoid dependency issues
  const onNewNotificationRef = useRef(onNewNotification);
  const onNotificationReadRef = useRef(onNotificationRead);
  const onNotificationDismissedRef = useRef(onNotificationDismissed);
  const onConnectedRef = useRef(onConnected);
  const onErrorRef = useRef(onError);

  onNewNotificationRef.current = onNewNotification;
  onNotificationReadRef.current = onNotificationRead;
  onNotificationDismissedRef.current = onNotificationDismissed;
  onConnectedRef.current = onConnected;
  onErrorRef.current = onError;

  // Type guard for WebSocket message data
  const isWebSocketMessage = (data: unknown): data is { type: NotificationEventType; [key: string]: unknown } => {
    return typeof data === 'object' && data !== null && 'type' in data;
  };

  // Handle incoming messages
  const handleMessage = useCallback((data: unknown) => {
    if (!isWebSocketMessage(data)) return;

    switch (data.type) {
      case 'connection_established':
        onConnectedRef.current?.();
        break;

      case 'new_notification':
        if (data.notification) {
          onNewNotificationRef.current?.(data.notification as WebSocketNotification);
        }
        break;

      case 'notification_read':
        if (data.notification_id) {
          onNotificationReadRef.current?.(data.notification_id as string);
        }
        break;

      case 'notification_dismissed':
        if (data.notification_id) {
          onNotificationDismissedRef.current?.(data.notification_id as string);
        }
        break;

      case 'pong':
        // Connection test response - no action needed
        break;

      case 'error':
        onErrorRef.current?.((data.message as string) || 'Notification channel error');
        break;
    }
  }, []);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to notification channel
  const subscribeToNotifications = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }

    // Only subscribe if user has an account
    if (!user?.account?.id) {
      if (process.env.NODE_ENV === 'development') {
        logger.warn('[NotificationWebSocket] Cannot subscribe: user account not available');
      }
      return;
    }

    unsubscribeRef.current = subscribe({
      channel: 'NotificationChannel',
      params: { account_id: user.account.id },
      onMessage: handleMessage,
      onError: handleError
    });
  }, [subscribe, handleMessage, handleError, user?.account?.id]);

  // Ping the server to test connection
  const ping = useCallback(async () => {
    if (!isConnected) {
      return false;
    }

    return sendMessage('NotificationChannel', 'ping', {});
  }, [isConnected, sendMessage]);

  // Auto-subscribe when connected
  useEffect(() => {
    if (isConnected) {
      subscribeToNotifications();
    }

    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [isConnected, subscribeToNotifications]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    ping,
    error: connectionError
  };
};
