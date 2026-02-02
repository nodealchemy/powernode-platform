import { useEffect, useCallback, useRef } from 'react';

export interface AISystemEvent {
  type: 'agent_executed' | 'workflow_completed' | 'workflow_failed' | 'provider_health_changed' | 'conversation_started' | 'conversation_ended';
  timestamp: string;
  data: {
    id: string;
    name?: string;
    status?: string;
    message?: string;
    metadata?: Record<string, unknown>;
  };
}

export interface AISystemMetrics {
  providers: {
    total: number;
    active: number;
    health_status: 'healthy' | 'degraded' | 'critical';
  };
  agents: {
    total: number;
    active: number;
    executing: number;
    success_rate: number;
  };
  workflows: {
    total: number;
    active: number;
    executing: number;
    success_rate: number;
  };
  executions: {
    total_today: number;
    success_rate: number;
    avg_response_time: number;
  };
}

type EventHandler = (event: AISystemEvent) => void;
type MetricsHandler = (metrics: AISystemMetrics) => void;

class AIOrchestrationMonitor {
  private ws: WebSocket | null = null;
  private eventHandlers: Set<EventHandler> = new Set();
  private metricsHandlers: Set<MetricsHandler> = new Set();
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 1000;
  private heartbeatInterval: NodeJS.Timeout | null = null;
  private isIntentionallyClosed = false;

  constructor() {
    this.connect();
  }

  private connect() {
    if (this.ws?.readyState === WebSocket.OPEN) return;

    try {
      // Get authentication token and account info
      const token = localStorage.getItem('access_token') || sessionStorage.getItem('access_token');
      const userStr = localStorage.getItem('currentUser') || sessionStorage.getItem('currentUser');
      
      if (!token || !userStr) {
        // Continue without WebSocket but still allow the component to function
        return;
      }

      let user: { account?: { id?: string } } | null = null;
      try {
        user = JSON.parse(userStr);
      } catch {
        return;
      }

      if (!user?.account?.id) {
        return;
      }

      // Use environment-based WebSocket URL - connect to ActionCable endpoint with token
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const host = window.location.host;
      // Add timestamp to force new connection and prevent caching
      const timestamp = Date.now();
      const wsUrl = `${protocol}//${host}/cable?token=${encodeURIComponent(token)}&t=${timestamp}`;
      
      // WebSocket connection initiated (token hidden for security)
      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        // AI Orchestration monitor connected
        this.reconnectAttempts = 0;
        this.startHeartbeat();
        
        // Subscribe to AI system events with type and id parameters
        // The channel expects: type (subscription type) and id (resource id)
        this.send({
          command: 'subscribe',
          identifier: JSON.stringify({
            channel: 'AiOrchestrationChannel',
            type: 'account',
            id: user!.account!.id
          })
        });
      };

      this.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          this.handleMessage(data);
        } catch {
          // Error parsing WebSocket message - handled silently
        }
      };

      this.ws.onclose = () => {
        // AI Orchestration monitor disconnected
        this.stopHeartbeat();
        
        if (!this.isIntentionallyClosed && this.reconnectAttempts < this.maxReconnectAttempts) {
          this.scheduleReconnect();
        }
      };

      this.ws.onerror = () => {
        // WebSocket connection error - reconnect will be attempted
      };

    } catch {
      this.scheduleReconnect();
    }
  }

  private handleMessage(data: { type?: string; message?: { type?: string; event_type?: AISystemEvent['type']; timestamp?: string; data?: AISystemEvent['data'] | AISystemMetrics } }) {
    if (data.type === 'ping') {
      // Respond to ping with pong
      this.send({ type: 'pong' });
      return;
    }

    if (data.message) {
      const message = data.message;

      // Handle system events
      if (message.type === 'event' && message.event_type && message.timestamp && message.data) {
        const event: AISystemEvent = {
          type: message.event_type,
          timestamp: message.timestamp,
          data: message.data as AISystemEvent['data']
        };
        this.notifyEventHandlers(event);
      }

      // Handle metrics updates
      if (message.type === 'metrics' && message.data) {
        const metrics = message.data as AISystemMetrics;
        this.notifyMetricsHandlers(metrics);
      }
    }
  }

  private send(message: Record<string, unknown>) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  private startHeartbeat() {
    this.heartbeatInterval = setInterval(() => {
      this.send({ type: 'ping' });
    }, 30000); // 30 seconds
  }

  private stopHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }

  private scheduleReconnect() {
    setTimeout(() => {
      this.reconnectAttempts++;
      this.connect();
    }, this.reconnectDelay * Math.pow(2, this.reconnectAttempts)); // Exponential backoff
  }

  private notifyEventHandlers(event: AISystemEvent) {
    this.eventHandlers.forEach(handler => {
      try {
        handler(event);
      } catch {
        // Error in event handler - handled silently
      }
    });
  }

  private notifyMetricsHandlers(metrics: AISystemMetrics) {
    this.metricsHandlers.forEach(handler => {
      try {
        handler(metrics);
      } catch {
        // Error in metrics handler - handled silently
      }
    });
  }

  public onEvent(handler: EventHandler): () => void {
    this.eventHandlers.add(handler);
    return () => this.eventHandlers.delete(handler);
  }

  public onMetrics(handler: MetricsHandler): () => void {
    this.metricsHandlers.add(handler);
    return () => this.metricsHandlers.delete(handler);
  }

  public disconnect() {
    this.isIntentionallyClosed = true;
    this.stopHeartbeat();
    if (this.ws) {
      this.ws.close(1000, 'Intentional disconnect');
      this.ws = null;
    }
    // AI Orchestration monitor manually disconnected
  }

  public forceReconnect() {
    // AI Orchestration monitor forcing reconnect
    this.disconnect();
    this.isIntentionallyClosed = false;
    this.reconnectAttempts = 0;
    // Add small delay to ensure clean disconnect
    setTimeout(() => {
      this.connect();
    }, 100);
  }

  public isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }
}

// Singleton instance
let monitorInstance: AIOrchestrationMonitor | null = null;

export function getAIOrchestrationMonitor(): AIOrchestrationMonitor {
  if (!monitorInstance) {
    monitorInstance = new AIOrchestrationMonitor();
  }
  return monitorInstance;
}

// Force reset the monitor instance (for development/debugging)
export function resetAIOrchestrationMonitor(): void {
  if (monitorInstance) {
    monitorInstance.disconnect();
    monitorInstance = null;
  }
}

// React hook for using the monitor
export function useAIOrchestrationMonitor() {
  const monitorRef = useRef<AIOrchestrationMonitor | null>(null);

  useEffect(() => {
    // Reset monitor if authentication changes
    const currentToken = localStorage.getItem('access_token') || sessionStorage.getItem('access_token');
    const currentUser = localStorage.getItem('currentUser') || sessionStorage.getItem('currentUser');
    
    // If no auth, don't create monitor
    if (!currentToken || !currentUser) {
      if (monitorRef.current) {
        monitorRef.current.disconnect();
        monitorRef.current = null;
      }
      return;
    }
    
    // Get or create monitor instance
    monitorRef.current = getAIOrchestrationMonitor();
    
    return () => {
      // Don't disconnect on unmount as other components might be using it
      // monitorRef.current?.disconnect();
    };
  }, []);

  const subscribe = useCallback((
    eventHandler?: EventHandler,
    metricsHandler?: MetricsHandler
  ) => {
    const monitor = monitorRef.current;
    if (!monitor) return () => {};

    const unsubscribers: Array<() => void> = [];

    if (eventHandler) {
      unsubscribers.push(monitor.onEvent(eventHandler));
    }

    if (metricsHandler) {
      unsubscribers.push(monitor.onMetrics(metricsHandler));
    }

    return () => {
      unsubscribers.forEach(unsub => unsub());
    };
  }, []);

  const isConnected = useCallback(() => {
    return monitorRef.current?.isConnected() ?? false;
  }, []);

  return {
    subscribe,
    isConnected,
    monitor: monitorRef.current
  };
}

// Cleanup function for app shutdown
export function disconnectAIOrchestrationMonitor() {
  if (monitorInstance) {
    monitorInstance.disconnect();
    monitorInstance = null;
  }
}