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

  // Timeouts
  private reconnectTimeout: NodeJS.Timeout | null = null;
  private connectDebounceTimeout: NodeJS.Timeout | null = null;

  // State change listeners
  private stateListeners: Set<(isConnected: boolean, error: string | null) => void> = new Set();

  // Token refresh flag
  private isRefreshingToken: boolean = false;

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
   * Initialize the WebSocket connection
   * Only initializes once, subsequent calls are ignored
   */
  public initialize(config: WebSocketConfig): void {
    if (this.isInitialized) {
      return;
    }

    this.isInitialized = true;
    this.config = config;
    this.connect();
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
      } catch {
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

    // Close any existing connection
    if (this.ws) {
      this.ws.close();
      this.ws = null;
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

    } catch {
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

          // Close connection to prevent reconnection loops
          if (this.ws) {
            this.ws.close();
            this.ws = null;
          }
        }
        return;
      }

      // Handle subscription confirmation
      if (data.type === 'confirm_subscription') {
        const identifier = JSON.parse(data.identifier);
        this.subscribedChannels.add(identifier.channel);
        return;
      }

      // Handle subscription rejection
      if (data.type === 'reject_subscription') {
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
            } catch {
              console.error('[WebSocket] Handler error:', error);
            }
          });
        }
      }

    } catch {
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

    // Add subscription to the set
    if (!this.subscriptions.has(channelKey)) {
      this.subscriptions.set(channelKey, new Set());
    }
    this.subscriptions.get(channelKey)!.add(subscription);

    // Send subscription message if connected
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.sendSubscriptionMessage(channel, params);
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

      // If no more subscriptions for this channel, unsubscribe from server
      if (subscriptions.size === 0) {
        this.subscriptions.delete(channelKey);

        if (this.ws?.readyState === WebSocket.OPEN) {
          this.sendUnsubscriptionMessage(channel, params);
        }

        this.subscribedChannels.delete(channel);
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
    } catch {
      return false;
    }
  }

  /**
   * Resubscribe to all channels after reconnection
   */
  private resubscribeAllChannels(): void {
    this.subscriptions.forEach((_, channelKey) => {
      const [channel, paramsStr] = channelKey.split('::');
      const params = paramsStr ? JSON.parse(paramsStr) : undefined;
      this.sendSubscriptionMessage(channel, params);
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
    } catch {
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
    } catch {
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
   * Disconnect from WebSocket server
   */
  public disconnect(): void {
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
