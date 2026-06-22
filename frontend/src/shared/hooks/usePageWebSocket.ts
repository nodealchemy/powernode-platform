import { useCallback, useRef, useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { logger } from '@/shared/utils/logger';

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

// Channel keys available for subscription. Core channels are enumerated in
// CORE_CHANNEL_NAMES below; extensions contribute additional channel keys via
// featureRegistry.registerChannels, so the runtime set is open — hence `string`.
export type ChannelType = string;

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

  // Override default subscriptions for CORE channels
  subscribeToNotifications?: boolean;
  subscribeToSettings?: boolean;
  subscribeToAiOrchestration?: boolean;
  subscribeToAiMonitoring?: boolean;
  subscribeToDevops?: boolean;

  // Generic add/remove for ANY channel key — core or extension-registered.
  // (Extension channels, e.g. the business subscriptions/customers/analytics
  // channels, have no per-channel boolean; use these instead.)
  subscribeTo?: ChannelType[];
  unsubscribeFrom?: ChannelType[];

  // Callbacks for data updates. onDataUpdate fires for EVERY channel (core and
  // extension), so extension pages route their channel's messages through it.
  onDataUpdate?: (update: WebSocketDataUpdate) => void;
  onNotification?: (data: unknown) => void;
  onSettingsUpdate?: (data: unknown) => void;
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

// Default CORE channel subscriptions per page type. Extensions add their channels
// to page types at runtime via FeatureChannel.defaultPageTypes (merged below).
const CORE_DEFAULT_SUBSCRIPTIONS: Record<PageType, ChannelType[]> = {
  dashboard: ['notifications'],
  ai: ['notifications', 'aiOrchestration', 'aiMonitoring'],
  business: ['notifications'],
  devops: ['notifications', 'devops'],
  admin: ['notifications', 'settings'],
  content: ['notifications'],
  system: ['notifications', 'settings'],
  marketplace: ['notifications'],
  privacy: ['notifications'],
  account: ['notifications', 'settings']
};

// CORE channel key → ActionCable channel name. Extension channels are merged in at
// runtime from featureRegistry.getChannels(), so core never names an extension channel.
const CORE_CHANNEL_NAMES: Record<string, string> = {
  notifications: 'NotificationChannel',
  settings: 'NotificationChannel', // Settings use NotificationChannel
  aiOrchestration: 'AiOrchestrationChannel',
  aiMonitoring: 'AiOrchestrationChannel',
  devops: 'DevopsPipelineChannel'
};

/**
 * Unified WebSocket hook for page-level subscriptions
 *
 * Provides automatic channel subscriptions based on page type with optional
 * overrides. Core channels are built in; extensions contribute channels (name +
 * default page types) through featureRegistry.registerChannels, which this hook
 * merges in — so core stays channel-agnostic and gains channels with zero edits.
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
 * // Opt into an extra channel (core or extension-registered)
 * const { isConnected } = usePageWebSocket({
 *   pageType: 'business',
 *   subscribeTo: ['subscriptions'],
 *   onDataUpdate: (update) => handleUpdate(update)
 * });
 * ```
 */
export const usePageWebSocket = ({
  pageType,
  subscribeToNotifications,
  subscribeToSettings,
  subscribeToAiOrchestration,
  subscribeToAiMonitoring,
  subscribeToDevops,
  subscribeTo,
  unsubscribeFrom,
  onDataUpdate,
  onNotification,
  onSettingsUpdate,
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

  // Channel name map + per-page defaults = CORE merged with whatever extensions
  // registered (resolved once at mount — registrations happen at app bootstrap).
  const channelNames = useMemo<Record<string, string>>(() => {
    const merged: Record<string, string> = { ...CORE_CHANNEL_NAMES };
    for (const ch of featureRegistry.getChannels()) {
      merged[ch.key] = ch.channelName;
    }
    return merged;
  }, []);

  const defaultSubscriptions = useMemo<Record<PageType, ChannelType[]>>(() => {
    const merged = Object.fromEntries(
      Object.entries(CORE_DEFAULT_SUBSCRIPTIONS).map(([pt, channels]) => [pt, [...channels]])
    ) as Record<PageType, ChannelType[]>;
    for (const ch of featureRegistry.getChannels()) {
      for (const pt of ch.defaultPageTypes || []) {
        const list = merged[pt as PageType];
        if (list && !list.includes(ch.key)) list.push(ch.key);
      }
    }
    return merged;
  }, []);

  // Track active subscriptions
  const [activeChannels, setActiveChannels] = useState<ChannelType[]>([]);
  const unsubscribeRefs = useRef<Map<ChannelType, () => void>>(new Map());

  // Store callback refs to avoid re-subscriptions
  const onDataUpdateRef = useRef(onDataUpdate);
  const onNotificationRef = useRef(onNotification);
  const onSettingsUpdateRef = useRef(onSettingsUpdate);
  const onAiOrchestrationUpdateRef = useRef(onAiOrchestrationUpdate);
  const onAiMonitoringUpdateRef = useRef(onAiMonitoringUpdate);
  const onDevopsUpdateRef = useRef(onDevopsUpdate);
  const onErrorRef = useRef(onError);
  const onConnectionChangeRef = useRef(onConnectionChange);

  // Update refs on change
  onDataUpdateRef.current = onDataUpdate;
  onNotificationRef.current = onNotification;
  onSettingsUpdateRef.current = onSettingsUpdate;
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

      // Generic handler — fires for every channel, including extension-registered ones
      onDataUpdateRef.current?.(update);

      // Core channel-specific handlers
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
        logger.warn(`[PageWebSocket] Cannot subscribe to ${channel}: not connected or no account`);
      }
      return;
    }

    const channelName = channelNames[channel];
    if (!channelName) {
      // No core or extension channel registered under this key — skip gracefully
      // (e.g. an extension channel requested while its extension isn't loaded).
      if (process.env.NODE_ENV === 'development') {
        logger.warn(`[PageWebSocket] No channel registered for '${channel}' — skipping`);
      }
      return;
    }

    // Unsubscribe if already subscribed
    if (unsubscribeRefs.current.has(channel)) {
      unsubscribeRefs.current.get(channel)?.();
      unsubscribeRefs.current.delete(channel);
    }

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

  }, [isConnected, accountId, subscribe, channelNames, createMessageHandler, handleError]);

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
    const defaults = defaultSubscriptions[pageType] || ['notifications'];
    const channels = new Set<ChannelType>(defaults);

    // Apply explicit core-channel overrides
    const overrides: [ChannelType, boolean | undefined][] = [
      ['notifications', subscribeToNotifications],
      ['settings', subscribeToSettings],
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

    // Generic add/remove for any channel key (core or extension-registered)
    subscribeTo?.forEach(channel => channels.add(channel));
    unsubscribeFrom?.forEach(channel => channels.delete(channel));

    return Array.from(channels);
  }, [
    pageType,
    defaultSubscriptions,
    subscribeToNotifications,
    subscribeToSettings,
    subscribeToAiOrchestration,
    subscribeToAiMonitoring,
    subscribeToDevops,
    subscribeTo,
    unsubscribeFrom
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
