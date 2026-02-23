/**
 * Singleton WebSocket Connection Manager
 *
 * Provides a single shared WebSocket connection across the entire application.
 * All components use the same connection through the useWebSocket hook,
 * which internally uses this manager.
 *
 * Benefits:
 * - Single connection reduces resource usage
 * - Centralized connection state management
 * - Automatic reconnection handling
 * - Proper subscription routing to multiple components
 */

interface WebSocketConfig {
  getUrl: () => string;
  onConnect?: () => void;
  onDisconnect?: (code: number, reason: string) => void;
  onError?: (error: Event) => void;
}

interface ChannelSubscription {
  channel: string;
  params?: Record<string, unknown>;
  onMessage?: (data: unknown) => void;
  onError?: (error: string) => void;
}

export class WebSocketManager {
  private static instance: WebSocketManager | null = null;
  private ws: WebSocket | null = null;
  private config: WebSocketConfig | null = null;

  // Connection state
  private isConnected: boolean = false;
  private isConnecting: boolean = false;
  private isInitialized: boolean = false;
  private reconnectAttempts: number = 0;
  private lastConnectAttempt: number = 0;
  private maxReconnectAttempts: number = 10;

  // Subscription management
  private subscriptions: Map<string, Set<ChannelSubscription>> = new Map();
  private subscribedChannels: Set<string> = new Set();

  // Deferred unsubscribe timers — prevents React StrictMode double-mount from
  // sending unsubscribe→subscribe (the unsubscribe can arrive at the server
  // AFTER the resubscribe, killing the active subscription)
  private pendingUnsubscribes: Map<string, NodeJS.Timeout> = new Map();

  // Timeouts
  private reconnectTimeout: NodeJS.Timeout | null = null;
  private connectDebounceTimeout: NodeJS.Timeout | null = null;

  // State change listeners
  private stateListeners: Set<(isConnected: boolean, error: string | null) => void> = new Set();

  // Token refresh flag
  private isRefreshingToken: boolean = false;

  // Browser event handlers for auto-reconnect
  private boundOnlineHandler: (() => void) | null = null;
  private boundVisibilityHandler: (() => void) | null = null;

  private constructor() {
    // Private constructor for singleton
  }

  /**
   * Get the singleton instance
   */
  public static getInstance(): WebSocketManager {
    if (!WebSocketManager.instance) {
      WebSocketManager.instance = new WebSocketManager();
    }
    return WebSocketManager.instance;
  }

  /**
   * Initialize the WebSocket connection.
   * On first call, sets up the connection and browser listeners.
   * On subsequent calls, updates the config (e.g., new auth token) and
   * reconnects if the WebSocket URL has changed.
   */
  public initialize(config: WebSocketConfig): void {
    if (this.isInitialized) {
      // Config changed (e.g., token refresh) — update getUrl and reconnect if URL differs
      const oldUrl = this.config?.getUrl();
      this.config = config;
      const newUrl = config.getUrl();
      if (oldUrl !== newUrl && this.ws) {
        // URL changed (new token) — close old connection and reconnect
        // Subscriptions are preserved in the map and resubscribed on reconnect
        this.reconnectAttempts = 0;
        const oldWs = this.ws;
        // Detach handlers so stale close/error events don't interfere
        oldWs.onopen = null;
        oldWs.onmessage = null;
        oldWs.onclose = null;
        oldWs.onerror = null;
        this.ws = null;
        this.isConnecting = false;
        this.isConnected = false;
        if (oldWs.readyState === WebSocket.OPEN || oldWs.readyState === WebSocket.CONNECTING) {
          oldWs.close(1000, 'Token refresh');
        }
        this.connect();
      }
      return;
    }

    this.isInitialized = true;
    this.config = config;
    this.connect();
    this.registerBrowserListeners();
  }

  /**
   * Check if WebSocket is connected
   */
  public getIsConnected(): boolean {
    return this.isConnected;
  }

  /**
   * Add a state change listener
   */
  public addStateListener(listener: (isConnected: boolean, error: string | null) => void): () => void {
    this.stateListeners.add(listener);
    // Return unsubscribe function
    return () => {
      this.stateListeners.delete(listener);
    };
  }

  /**
   * Notify all state listeners
   */
  private notifyStateListeners(isConnected: boolean, error: string | null = null): void {
    this.stateListeners.forEach(listener => {
      try {
        listener(isConnected, error);
      } catch (_error) {
        // Prevent listener errors from affecting other listeners
      }
    });
  }

  /**
   * Connect to WebSocket server
   */
  private connect(): void {
    if (!this.config) {
      return;
    }

    // Prevent overlapping connection attempts
    if (this.isConnecting ||
        this.ws?.readyState === WebSocket.CONNECTING ||
        this.ws?.readyState === WebSocket.OPEN) {
      return;
    }

    // Implement exponential backoff
    const now = Date.now();
    const timeSinceLastAttempt = now - this.lastConnectAttempt;
    const minBackoffTime = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);

    if (timeSinceLastAttempt < minBackoffTime) {
      // Schedule retry after backoff period
      this.reconnectTimeout = setTimeout(() => {
        this.connect();
      }, minBackoffTime - timeSinceLastAttempt);
      return;
    }

    this.lastConnectAttempt = now;

    // Clear any existing debounce timeout
    if (this.connectDebounceTimeout) {
      clearTimeout(this.connectDebounceTimeout);
      this.connectDebounceTimeout = null;
    }

    // Debounce connection attempts
    this.connectDebounceTimeout = setTimeout(() => {
      this.executeConnect();
    }, 100);
  }

  /**
   * Execute the WebSocket connection
   */
  private executeConnect(): void {
    if (!this.config) return;

    this.isConnecting = true;

    // Clear any existing reconnect timeout
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }

    // Close any existing connection, detaching handlers to prevent stale events
    if (this.ws) {
      const oldWs = this.ws;
      oldWs.onopen = null;
      oldWs.onmessage = null;
      oldWs.onclose = null;
      oldWs.onerror = null;
      this.ws = null;
      oldWs.close();
    }

    try {
      const wsUrl = this.config.getUrl();
      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        this.isConnecting = false;
        this.isConnected = true;
        this.reconnectAttempts = 0;

        this.notifyStateListeners(true, null);
        this.config?.onConnect?.();

        // Resubscribe to all channels
        this.resubscribeAllChannels();
      };

      this.ws.onmessage = (event) => {
        this.handleMessage(event);
      };

      this.ws.onclose = (event) => {
        this.handleClose(event);
      };

      this.ws.onerror = (error) => {
        this.handleError(error);
      };

    } catch (error) {
      this.isConnecting = false;
      this.isConnected = false;
      this.notifyStateListeners(false, `Failed to create WebSocket: ${error}`);
    }
  }

  /**
   * Handle incoming WebSocket messages
   */
  private handleMessage(event: MessageEvent): void {
    try {
      const data = JSON.parse(event.data);

      // Handle system messages
      if (data.type === 'welcome' || data.type === 'ping') {
        return;
      }

      // Handle disconnect (authentication failure)
      if (data.type === 'disconnect' && data.reason === 'unauthorized') {
        // Token expired - emit event for token refresh
        if (!this.isRefreshingToken) {
          this.isRefreshingToken = true;
          this.notifyStateListeners(false, 'Session expired');

          // Close connection, detaching handlers to prevent reconnection loops
          if (this.ws) {
            const oldWs = this.ws;
            oldWs.onopen = null;
            oldWs.onmessage = null;
            oldWs.onclose = null;
            oldWs.onerror = null;
            this.ws = null;
            this.isConnected = false;
            this.isConnecting = false;
            oldWs.close();
          }
        }
        return;
      }

      // Handle subscription confirmation — track by full channelKey (channel + params)
      if (data.type === 'confirm_subscription') {
        const identifier = JSON.parse(data.identifier);
        const { channel, ...params } = identifier;
        const channelKey = this.getChannelKey(channel, params);
        this.subscribedChannels.add(channelKey);
        if (process.env.NODE_ENV === 'development') {
          console.debug(`[WebSocket] Subscription confirmed: ${channel} (key=${channelKey})`);
        }
        return;
      }

      // Handle subscription rejection — clean up local state
      if (data.type === 'reject_subscription') {
        try {
          const identifier = JSON.parse(data.identifier);
          const { channel, ...params } = identifier;
          const channelKey = this.getChannelKey(channel, params);
          const subs = this.subscriptions.get(channelKey);
          if (subs) {
            subs.forEach(sub => sub.onError?.('Subscription rejected by server'));
          }
        } catch (_e) {
          // Ignore parse errors
        }
        return;
      }

      // Route messages to channel handlers
      if (data.identifier) {
        const identifier = JSON.parse(data.identifier);

        // Extract channel and params separately
        // Backend includes "channel" in the identifier, but we need to exclude it from params
        // to match the key we created during subscription
        const { channel, ...params } = identifier;
        const channelKey = this.getChannelKey(channel, params);
        const subscriptions = this.subscriptions.get(channelKey);

        if (subscriptions && data.message) {
          subscriptions.forEach(sub => {
            try {
              sub.onMessage?.(data.message);
            } catch (error) {
              console.error('[WebSocket] Handler error:', error);
            }
          });
        }
      }

    } catch (error) {
      console.error('[WebSocket] Message parsing error:', error);
    }
  }

  /**
   * Handle WebSocket close
   */
  private handleClose(event: CloseEvent): void {
    this.isConnecting = false;
    this.isConnected = false;

    let errorMessage: string | null = null;
    if (event.code === 1006) {
      errorMessage = 'Connection lost unexpectedly';
    } else if (event.code === 1008) {
      errorMessage = 'Connection closed due to policy violation';
    } else if (event.code !== 1000) {
      errorMessage = event.reason || 'Connection lost';
    }

    this.notifyStateListeners(false, errorMessage);
    this.config?.onDisconnect?.(event.code, event.reason);

    // Auto-reconnect with exponential backoff if not a normal closure
    if (event.code !== 1000 && this.config) {
      this.reconnectAttempts += 1;
      const backoffTime = Math.min(3000 * Math.pow(1.5, this.reconnectAttempts - 1), 30000);

      if (process.env.NODE_ENV === 'development') {
        console.debug(`[WebSocket] Connection closed (code=${event.code}), reconnecting in ${backoffTime}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts}, subscriptions=${this.subscriptions.size})`);
      }

      if (this.reconnectAttempts <= this.maxReconnectAttempts) {
        this.reconnectTimeout = setTimeout(() => {
          this.connect();
        }, backoffTime);
      } else {
        this.notifyStateListeners(false, 'Connection failed repeatedly');
      }
    }
  }

  /**
   * Handle WebSocket error
   */
  private handleError(error: Event): void {
    this.isConnecting = false;
    this.isConnected = false;

    this.notifyStateListeners(false, 'WebSocket connection error');
    this.config?.onError?.(error);

    // Close the connection to prevent "closed before connection established" errors
    if (this.ws && this.ws.readyState !== WebSocket.CLOSED) {
      this.ws.close();
      this.ws = null;
    }
  }

  /**
   * Subscribe to a channel
   */
  public subscribe(subscription: ChannelSubscription): () => void {
    const { channel, params } = subscription;
    const channelKey = this.getChannelKey(channel, params);

    // Cancel any pending deferred unsubscribe for this channel key
    // (React StrictMode: mount1 cleanup schedules unsubscribe, mount2 cancels it)
    const pendingTimer = this.pendingUnsubscribes.get(channelKey);
    if (pendingTimer) {
      clearTimeout(pendingTimer);
      this.pendingUnsubscribes.delete(channelKey);
      if (process.env.NODE_ENV === 'development') {
        console.debug(`[WebSocket] Subscribe: cancelled pending unsubscribe for ${channel}`);
      }
    }

    // Add subscription to the set
    const isNew = !this.subscriptions.has(channelKey);
    if (isNew) {
      this.subscriptions.set(channelKey, new Set());
    }
    this.subscriptions.get(channelKey)!.add(subscription);

    // Send subscription message if connected and this is a genuinely new channel
    // (or if it was previously unsubscribed from the server)
    if (this.ws?.readyState === WebSocket.OPEN && !this.subscribedChannels.has(channelKey)) {
      this.sendSubscriptionMessage(channel, params);
    }

    if (process.env.NODE_ENV === 'development') {
      const count = this.subscriptions.get(channelKey)!.size;
      console.debug(`[WebSocket] Subscribe: ${channel} (${count} listeners, new=${isNew}, wsOpen=${this.ws?.readyState === WebSocket.OPEN})`);
    }

    // Return unsubscribe function
    return () => {
      this.unsubscribe(channelKey, subscription, channel, params);
    };
  }

  /**
   * Unsubscribe from a channel
   */
  private unsubscribe(
    channelKey: string,
    subscription: ChannelSubscription,
    channel: string,
    params?: Record<string, unknown>
  ): void {
    const subscriptions = this.subscriptions.get(channelKey);
    if (subscriptions) {
      subscriptions.delete(subscription);

      // If no more local listeners, defer the server-side unsubscribe.
      // This prevents React StrictMode's unmount→remount cycle from sending
      // an unsubscribe that races with (and kills) the subsequent resubscribe.
      if (subscriptions.size === 0) {
        this.subscriptions.delete(channelKey);

        if (process.env.NODE_ENV === 'development') {
          console.debug(`[WebSocket] Unsubscribe: ${channel} (last listener removed, deferring server unsubscribe 300ms)`);
        }

        // Defer server-side unsubscribe — if a new subscribe arrives within
        // 300ms (StrictMode remount), the timer is cancelled in subscribe()
        const timer = setTimeout(() => {
          this.pendingUnsubscribes.delete(channelKey);
          this.subscribedChannels.delete(channelKey);

          if (this.ws?.readyState === WebSocket.OPEN) {
            this.sendUnsubscriptionMessage(channel, params);
            if (process.env.NODE_ENV === 'development') {
              console.debug(`[WebSocket] Unsubscribe: ${channel} (deferred unsubscribe sent to server)`);
            }
          }
        }, 300);

        this.pendingUnsubscribes.set(channelKey, timer);
      } else if (process.env.NODE_ENV === 'development') {
        console.debug(`[WebSocket] Unsubscribe: ${channel} (${subscriptions.size} listeners remaining)`);
      }
    }
  }

  /**
   * Send a message to a channel
   */
  public sendMessage(channel: string, action: string, data?: Record<string, unknown>, params?: Record<string, unknown>): boolean {
    if (!this.ws) {
      return false;
    }

    if (this.ws.readyState !== WebSocket.OPEN) {
      return false;
    }

    const message = {
      command: 'message',
      identifier: JSON.stringify({
        channel,
        ...params
      }),
      data: JSON.stringify({ action, ...data })
    };

    try {
      this.ws.send(JSON.stringify(message));
      return true;
    } catch (_error) {
      return false;
    }
  }

  /**
   * Resubscribe to all channels after reconnection
   */
  private resubscribeAllChannels(): void {
    if (this.subscriptions.size === 0) return;

    // New connection — no channels are confirmed yet
    this.subscribedChannels.clear();

    // Cancel any pending deferred unsubscribes (stale from old connection)
    this.pendingUnsubscribes.forEach(timer => clearTimeout(timer));
    this.pendingUnsubscribes.clear();

    this.subscriptions.forEach((subs, channelKey) => {
      const separatorIdx = channelKey.indexOf('::');
      const channel = separatorIdx >= 0 ? channelKey.substring(0, separatorIdx) : channelKey;
      const paramsStr = separatorIdx >= 0 ? channelKey.substring(separatorIdx + 2) : undefined;
      const params = paramsStr ? JSON.parse(paramsStr) : undefined;
      this.sendSubscriptionMessage(channel, params);
      if (process.env.NODE_ENV === 'development') {
        console.debug(`[WebSocket] Resubscribed: ${channel} (${subs.size} listeners)`);
      }
    });
  }

  /**
   * Send subscription message to server
   */
  private sendSubscriptionMessage(channel: string, params?: Record<string, unknown>): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;

    const subscribeMessage = {
      command: 'subscribe',
      identifier: JSON.stringify({
        channel,
        ...params
      })
    };

    try {
      this.ws.send(JSON.stringify(subscribeMessage));
    } catch (_error) {
      // Ignore send errors
    }
  }

  /**
   * Send unsubscription message to server
   */
  private sendUnsubscriptionMessage(channel: string, params?: Record<string, unknown>): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;

    const unsubscribeMessage = {
      command: 'unsubscribe',
      identifier: JSON.stringify({
        channel,
        ...params
      })
    };

    try {
      this.ws.send(JSON.stringify(unsubscribeMessage));
    } catch (_error) {
      // Ignore send errors
    }
  }

  /**
   * Generate unique key for channel + params combination
   * Normalizes params by sorting keys to ensure consistent key generation
   */
  private getChannelKey(channel: string, params?: Record<string, unknown>): string {
    if (!params || Object.keys(params).length === 0) {
      return channel;
    }

    // Sort keys to ensure consistent stringification regardless of key order
    const sortedParams = Object.keys(params)
      .sort()
      .reduce((acc, key) => {
        acc[key] = params[key];
        return acc;
      }, {} as Record<string, unknown>);

    return `${channel}::${JSON.stringify(sortedParams)}`;
  }

  /**
   * Register browser event listeners for network recovery auto-reconnect
   */
  private registerBrowserListeners(): void {
    this.boundOnlineHandler = () => {
      if (!this.isConnected && this.config) {
        this.reconnectAttempts = 0;
        this.connect();
      }
    };

    this.boundVisibilityHandler = () => {
      if (document.visibilityState === 'visible' && !this.isConnected && this.config) {
        this.reconnectAttempts = 0;
        this.connect();
      }
    };

    window.addEventListener('online', this.boundOnlineHandler);
    document.addEventListener('visibilitychange', this.boundVisibilityHandler);
  }

  /**
   * Remove browser event listeners
   */
  private removeBrowserListeners(): void {
    if (this.boundOnlineHandler) {
      window.removeEventListener('online', this.boundOnlineHandler);
      this.boundOnlineHandler = null;
    }
    if (this.boundVisibilityHandler) {
      document.removeEventListener('visibilitychange', this.boundVisibilityHandler);
      this.boundVisibilityHandler = null;
    }
  }

  public disconnect(): void {
    this.removeBrowserListeners();
    this.isConnecting = false;
    this.isRefreshingToken = false;
    this.isInitialized = false;

    // Reset reconnection state
    this.reconnectAttempts = 0;
    this.lastConnectAttempt = 0;

    // Clear all timeouts
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }

    if (this.connectDebounceTimeout) {
      clearTimeout(this.connectDebounceTimeout);
      this.connectDebounceTimeout = null;
    }

    // Clear pending deferred unsubscribes
    this.pendingUnsubscribes.forEach(timer => clearTimeout(timer));
    this.pendingUnsubscribes.clear();

    // Close WebSocket connection
    if (this.ws) {
      this.ws.close(1000, 'User disconnect');
      this.ws = null;
    }

    this.isConnected = false;
    this.config = null;
    this.subscriptions.clear();
    this.subscribedChannels.clear();

    this.notifyStateListeners(false, null);
  }

  /**
   * Reset token refresh flag (called after token refresh succeeds)
   */
  public resetTokenRefreshFlag(): void {
    this.isRefreshingToken = false;
  }

  /**
   * Reconnect after token refresh
   */
  public reconnect(): void {
    this.isRefreshingToken = false;
    this.reconnectAttempts = 0;
    this.connect();
  }
}

// Export singleton instance
export const wsManager = WebSocketManager.getInstance();
