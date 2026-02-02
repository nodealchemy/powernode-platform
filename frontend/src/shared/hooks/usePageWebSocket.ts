import { useCallback, useRef, useEffect, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from './useWebSocket';

// Page types that determine auto-subscription behavior
export type PageType =
  | 'dashboard'
  | 'ai'
  | 'business'
  | 'devops'
  | 'admin'
  | 'content'
  | 'system'
  | 'marketplace'
  | 'privacy'
  | 'account';

// Channel types available for subscription
export type ChannelType =
  | 'notifications'
  | 'settings'
  | 'analytics'
  | 'subscriptions'
  | 'customers'
  | 'aiOrchestration'
  | 'aiMonitoring'
  | 'devops';

// WebSocket data update event
export interface WebSocketDataUpdate {
  channel: ChannelType;
  type: string;
  data: unknown;
  timestamp: Date;
}

// Hook options
export interface PageWebSocketOptions {
  // Page type determines default subscriptions
  pageType: PageType;

  // Override default subscriptions
  subscribeToNotifications?: boolean;
  subscribeToSettings?: boolean;
  subscribeToAnalytics?: boolean;
  subscribeToSubscriptions?: boolean;
  subscribeToCustomers?: boolean;
  subscribeToAiOrchestration?: boolean;
  subscribeToAiMonitoring?: boolean;
  subscribeToDevops?: boolean;

  // Callbacks for data updates
  onDataUpdate?: (update: WebSocketDataUpdate) => void;
  onNotification?: (data: unknown) => void;
  onSettingsUpdate?: (data: unknown) => void;
  onAnalyticsUpdate?: (data: unknown) => void;
  onSubscriptionUpdate?: (data: unknown) => void;
  onCustomerUpdate?: (data: unknown) => void;
  onAiOrchestrationUpdate?: (data: unknown) => void;
  onAiMonitoringUpdate?: (data: unknown) => void;
  onDevopsUpdate?: (data: unknown) => void;
  onError?: (error: string) => void;
  onConnectionChange?: (isConnected: boolean) => void;

  // Account ID for subscriptions (auto-detected from auth if not provided)
  accountId?: string;
}

// Return type for the hook
export interface PageWebSocketReturn {
  isConnected: boolean;
  error: string | null;
  activeChannels: ChannelType[];
  // Manual channel control
  subscribeToChannel: (channel: ChannelType) => void;
  unsubscribeFromChannel: (channel: ChannelType) => void;
}

// Default channel subscriptions per page type
const DEFAULT_SUBSCRIPTIONS: Record<PageType, ChannelType[]> = {
  dashboard: ['notifications', 'subscriptions', 'analytics'],
  ai: ['notifications', 'aiOrchestration', 'aiMonitoring'],
  business: ['notifications', 'analytics', 'subscriptions', 'customers'],
  devops: ['notifications', 'devops'],
  admin: ['notifications', 'settings'],
  content: ['notifications'],
  system: ['notifications', 'settings'],
  marketplace: ['notifications', 'subscriptions'],
  privacy: ['notifications'],
  account: ['notifications', 'settings']
};

// Channel to ActionCable channel name mapping
const CHANNEL_NAMES: Record<ChannelType, string> = {
  notifications: 'NotificationChannel',
  settings: 'NotificationChannel', // Settings use NotificationChannel
  analytics: 'AnalyticsChannel',
  subscriptions: 'SubscriptionChannel',
  customers: 'CustomerChannel',
  aiOrchestration: 'AiOrchestrationChannel',
  aiMonitoring: 'AiWorkflowMonitoringChannel',
  devops: 'DevopsPipelineChannel'
};

/**
 * Unified WebSocket hook for page-level subscriptions
 *
 * Provides automatic channel subscriptions based on page type with
 * optional overrides for custom subscription needs.
 *
 * @example
 * ```tsx
 * // Basic usage with auto-subscriptions
 * const { isConnected, error } = usePageWebSocket({
 *   pageType: 'dashboard',
 *   onDataUpdate: (update) => {
 *     console.log('Received update:', update);
 *     refetchData();
 *   }
 * });
 *
 * // Custom subscriptions
 * const { isConnected } = usePageWebSocket({
 *   pageType: 'ai',
 *   subscribeToAnalytics: true, // Override to also get analytics
 *   onAiOrchestrationUpdate: (data) => handleWorkflowUpdate(data)
 * });
 * ```
 */
export const usePageWebSocket = ({
  pageType,
  subscribeToNotifications,
  subscribeToSettings,
  subscribeToAnalytics,
  subscribeToSubscriptions,
  subscribeToCustomers,
  subscribeToAiOrchestration,
  subscribeToAiMonitoring,
  subscribeToDevops,
  onDataUpdate,
  onNotification,
  onSettingsUpdate,
  onAnalyticsUpdate,
  onSubscriptionUpdate,
  onCustomerUpdate,
  onAiOrchestrationUpdate,
  onAiMonitoringUpdate,
  onDevopsUpdate,
  onError,
  onConnectionChange,
  accountId: providedAccountId
}: PageWebSocketOptions): PageWebSocketReturn => {
  const { isConnected, subscribe, error: connectionError } = useWebSocket();
  const user = useSelector((state: RootState) => state.auth.user);
  const accountId = providedAccountId || user?.account?.id;

  // Track active subscriptions
  const [activeChannels, setActiveChannels] = useState<ChannelType[]>([]);
  const unsubscribeRefs = useRef<Map<ChannelType, () => void>>(new Map());

  // Store callback refs to avoid re-subscriptions
  const onDataUpdateRef = useRef(onDataUpdate);
  const onNotificationRef = useRef(onNotification);
  const onSettingsUpdateRef = useRef(onSettingsUpdate);
  const onAnalyticsUpdateRef = useRef(onAnalyticsUpdate);
  const onSubscriptionUpdateRef = useRef(onSubscriptionUpdate);
  const onCustomerUpdateRef = useRef(onCustomerUpdate);
  const onAiOrchestrationUpdateRef = useRef(onAiOrchestrationUpdate);
  const onAiMonitoringUpdateRef = useRef(onAiMonitoringUpdate);
  const onDevopsUpdateRef = useRef(onDevopsUpdate);
  const onErrorRef = useRef(onError);
  const onConnectionChangeRef = useRef(onConnectionChange);

  // Update refs on change
  onDataUpdateRef.current = onDataUpdate;
  onNotificationRef.current = onNotification;
  onSettingsUpdateRef.current = onSettingsUpdate;
  onAnalyticsUpdateRef.current = onAnalyticsUpdate;
  onSubscriptionUpdateRef.current = onSubscriptionUpdate;
  onCustomerUpdateRef.current = onCustomerUpdate;
  onAiOrchestrationUpdateRef.current = onAiOrchestrationUpdate;
  onAiMonitoringUpdateRef.current = onAiMonitoringUpdate;
  onDevopsUpdateRef.current = onDevopsUpdate;
  onErrorRef.current = onError;
  onConnectionChangeRef.current = onConnectionChange;

  // Type guard for WebSocket message data
  const isWebSocketMessage = (data: unknown): data is { type: string; [key: string]: unknown } => {
    return typeof data === 'object' && data !== null && 'type' in data;
  };

  // Create message handler for a specific channel
  const createMessageHandler = useCallback((channel: ChannelType) => {
    return (data: unknown) => {
      if (!isWebSocketMessage(data)) return;

      const update: WebSocketDataUpdate = {
        channel,
        type: data.type,
        data,
        timestamp: new Date()
      };

      // Call generic handler
      onDataUpdateRef.current?.(update);

      // Call channel-specific handlers
      switch (channel) {
        case 'notifications':
          if (data.type === 'new_notification' || data.type === 'notification_read') {
            onNotificationRef.current?.(data);
          }
          break;
        case 'settings':
          if (data.type === 'settings_updated' || data.type === 'preferences_updated' ||
              data.type === 'notifications_updated' || data.type === 'profile_updated') {
            onSettingsUpdateRef.current?.(data);
          }
          break;
        case 'analytics':
          if (data.type === 'analytics_update') {
            onAnalyticsUpdateRef.current?.(data);
          }
          break;
        case 'subscriptions':
          if (data.type === 'subscription_updated' || data.type === 'subscription_cancelled' ||
              data.type === 'payment_processed' || data.type === 'trial_ending') {
            onSubscriptionUpdateRef.current?.(data);
          }
          break;
        case 'customers':
          if (data.type === 'customer_updated' || data.type === 'customer_created' ||
              data.type === 'customer_status_changed' || data.type === 'search_results') {
            onCustomerUpdateRef.current?.(data);
          }
          break;
        case 'aiOrchestration':
          onAiOrchestrationUpdateRef.current?.(data);
          break;
        case 'aiMonitoring':
          if (data.type === 'dashboard_stats' || data.type === 'active_executions' ||
              data.type === 'system_alert' || data.type === 'cost_alert') {
            onAiMonitoringUpdateRef.current?.(data);
          }
          break;
        case 'devops':
          onDevopsUpdateRef.current?.(data);
          break;
      }
    };
  }, []);

  // Create error handler
  const handleError = useCallback((errorMessage: string) => {
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to a specific channel
  const subscribeToChannel = useCallback((channel: ChannelType) => {
    if (!isConnected || !accountId) {
      if (process.env.NODE_ENV === 'development') {
        console.warn(`[PageWebSocket] Cannot subscribe to ${channel}: not connected or no account`);
      }
      return;
    }

    // Unsubscribe if already subscribed
    if (unsubscribeRefs.current.has(channel)) {
      unsubscribeRefs.current.get(channel)?.();
      unsubscribeRefs.current.delete(channel);
    }

    const channelName = CHANNEL_NAMES[channel];
    const unsubscribe = subscribe({
      channel: channelName,
      params: { account_id: accountId },
      onMessage: createMessageHandler(channel),
      onError: handleError
    });

    unsubscribeRefs.current.set(channel, unsubscribe);
    setActiveChannels(prev => {
      if (prev.includes(channel)) return prev;
      return [...prev, channel];
    });

  }, [isConnected, accountId, subscribe, createMessageHandler, handleError]);

  // Unsubscribe from a specific channel
  const unsubscribeFromChannel = useCallback((channel: ChannelType) => {
    if (unsubscribeRefs.current.has(channel)) {
      unsubscribeRefs.current.get(channel)?.();
      unsubscribeRefs.current.delete(channel);
      setActiveChannels(prev => prev.filter(c => c !== channel));
    }
  }, []);

  // Determine which channels to subscribe to
  const getChannelsToSubscribe = useCallback((): ChannelType[] => {
    const defaults = DEFAULT_SUBSCRIPTIONS[pageType] || ['notifications'];
    const channels = new Set<ChannelType>(defaults);

    // Apply explicit overrides
    const overrides: [ChannelType, boolean | undefined][] = [
      ['notifications', subscribeToNotifications],
      ['settings', subscribeToSettings],
      ['analytics', subscribeToAnalytics],
      ['subscriptions', subscribeToSubscriptions],
      ['customers', subscribeToCustomers],
      ['aiOrchestration', subscribeToAiOrchestration],
      ['aiMonitoring', subscribeToAiMonitoring],
      ['devops', subscribeToDevops]
    ];

    for (const [channel, override] of overrides) {
      if (override === true) {
        channels.add(channel);
      } else if (override === false) {
        channels.delete(channel);
      }
    }

    return Array.from(channels);
  }, [
    pageType,
    subscribeToNotifications,
    subscribeToSettings,
    subscribeToAnalytics,
    subscribeToSubscriptions,
    subscribeToCustomers,
    subscribeToAiOrchestration,
    subscribeToAiMonitoring,
    subscribeToDevops
  ]);

  // Auto-subscribe when connected
  useEffect(() => {
    if (isConnected && accountId) {
      const channels = getChannelsToSubscribe();
      channels.forEach(channel => subscribeToChannel(channel));
    }

    return () => {
      unsubscribeRefs.current.forEach((unsubscribe) => unsubscribe());
      unsubscribeRefs.current.clear();
      setActiveChannels([]);
    };
  }, [isConnected, accountId, getChannelsToSubscribe, subscribeToChannel]);

  // Notify connection changes
  useEffect(() => {
    onConnectionChangeRef.current?.(isConnected);
  }, [isConnected]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    error: connectionError,
    activeChannels,
    subscribeToChannel,
    unsubscribeFromChannel
  };
};

export default usePageWebSocket;
