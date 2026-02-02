import { useEffect, useRef, useState } from 'react';
import type { DevopsPipelineRun } from '@/types/devops-pipelines';

export interface DevopsPipelineEvent {
  type: 'run_created' | 'run_updated' | 'run_completed' | 'step_updated' | 'subscribed';
  pipeline_run?: Partial<DevopsPipelineRun>;
  pipeline_run_id?: string;
  step_execution?: {
    id: string;
    step_name: string;
    step_type: string;
    status: string;
    started_at: string | null;
    completed_at: string | null;
    error_message: string | null;
  };
  progress_percentage?: number;
  timestamp: string;
  message?: string;
}

type EventHandler = (event: DevopsPipelineEvent) => void;

class DevopsWebSocketManager {
  private ws: WebSocket | null = null;
  private eventHandlers: Map<string, Set<EventHandler>> = new Map();
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 1000;
  private heartbeatInterval: ReturnType<typeof setInterval> | null = null;
  private isIntentionallyClosed = false;
  private currentSubscription: { accountId?: string; pipelineId?: string } = {};

  connect(accountId: string, pipelineId?: string) {
    // If already connected with same subscription, skip
    if (
      this.ws?.readyState === WebSocket.OPEN &&
      this.currentSubscription.accountId === accountId &&
      this.currentSubscription.pipelineId === pipelineId
    ) {
      return;
    }

    // Close existing connection if params changed
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.close();
    }

    this.currentSubscription = { accountId, pipelineId };
    this.isIntentionallyClosed = false;

    try {
      const token = localStorage.getItem('access_token') || sessionStorage.getItem('access_token');
      if (!token) return;

      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const host = window.location.host;
      const timestamp = Date.now();
      const wsUrl = `${protocol}//${host}/cable?token=${encodeURIComponent(token)}&t=${timestamp}`;

      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        this.reconnectAttempts = 0;
        this.startHeartbeat();

        // Subscribe to DevOps pipeline channel
        const identifier: Record<string, string> = {
          channel: 'DevopsPipelineChannel',
          account_id: accountId,
        };
        if (pipelineId) {
          identifier.pipeline_id = pipelineId;
        }

        this.send({
          command: 'subscribe',
          identifier: JSON.stringify(identifier),
        });
      };

      this.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          this.handleMessage(data);
        } catch {
          // Ignore parse errors
        }
      };

      this.ws.onclose = () => {
        this.stopHeartbeat();
        if (!this.isIntentionallyClosed && this.reconnectAttempts < this.maxReconnectAttempts) {
          this.scheduleReconnect();
        }
      };

      this.ws.onerror = () => {
        // Error handled by onclose
      };
    } catch {
      this.scheduleReconnect();
    }
  }

  private handleMessage(data: { type?: string; message?: DevopsPipelineEvent }) {
    if (data.type === 'ping') {
      this.send({ type: 'pong' });
      return;
    }

    if (data.message && data.message.type) {
      this.notifyHandlers(data.message);
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
    }, 30000);
  }

  private stopHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }

  private scheduleReconnect() {
    const { accountId, pipelineId } = this.currentSubscription;
    if (!accountId) return;

    setTimeout(() => {
      this.reconnectAttempts++;
      this.connect(accountId, pipelineId);
    }, this.reconnectDelay * Math.pow(2, this.reconnectAttempts));
  }

  private notifyHandlers(event: DevopsPipelineEvent) {
    // Notify all handlers - both global and pipeline-specific
    // The backend already filters by pipeline_id on subscription
    this.eventHandlers.forEach((handlers) => {
      handlers.forEach((handler) => {
        try {
          handler(event);
        } catch {
          // Ignore handler errors
        }
      });
    });
  }

  subscribe(handler: EventHandler, pipelineId?: string): () => void {
    const key = pipelineId || 'global';
    if (!this.eventHandlers.has(key)) {
      this.eventHandlers.set(key, new Set());
    }
    this.eventHandlers.get(key)!.add(handler);

    return () => {
      this.eventHandlers.get(key)?.delete(handler);
    };
  }

  disconnect() {
    this.isIntentionallyClosed = true;
    this.stopHeartbeat();
    if (this.ws) {
      this.ws.close(1000, 'Intentional disconnect');
      this.ws = null;
    }
    this.eventHandlers.clear();
  }

  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }
}

// Singleton instance
let wsManager: DevopsWebSocketManager | null = null;

function getWsManager(): DevopsWebSocketManager {
  if (!wsManager) {
    wsManager = new DevopsWebSocketManager();
  }
  return wsManager;
}

/**
 * Hook for subscribing to DevOps pipeline WebSocket updates
 * @param pipelineId - Optional pipeline ID to subscribe to specific pipeline updates
 * @param onEvent - Callback for handling events
 */
export function useDevopsWebSocket(
  pipelineId?: string,
  onEvent?: (event: DevopsPipelineEvent) => void
) {
  const [isConnected, setIsConnected] = useState(false);
  const onEventRef = useRef(onEvent);
  onEventRef.current = onEvent;

  useEffect(() => {
    const userStr = localStorage.getItem('currentUser') || sessionStorage.getItem('currentUser');
    if (!userStr) return;

    let user: { account?: { id?: string } } | null = null;
    try {
      user = JSON.parse(userStr);
    } catch {
      return;
    }

    if (!user?.account?.id) return;

    const manager = getWsManager();
    manager.connect(user.account.id, pipelineId);

    // Check connection status periodically
    const statusCheck = setInterval(() => {
      setIsConnected(manager.isConnected());
    }, 1000);

    // Subscribe to events
    const unsubscribe = manager.subscribe((event) => {
      onEventRef.current?.(event);
    }, pipelineId);

    return () => {
      clearInterval(statusCheck);
      unsubscribe();
    };
  }, [pipelineId]);

  return { isConnected };
}

/**
 * Hook specifically for pipeline runs list with automatic refresh
 */
export function useDevopsRunsWebSocket(
  pipelineId: string | undefined,
  onRunCreated?: (run: Partial<DevopsPipelineRun>) => void,
  onRunUpdated?: (run: Partial<DevopsPipelineRun>) => void
) {
  const { isConnected } = useDevopsWebSocket(pipelineId, (event) => {
    if (event.type === 'run_created' && event.pipeline_run) {
      onRunCreated?.(event.pipeline_run);
    } else if ((event.type === 'run_updated' || event.type === 'run_completed') && event.pipeline_run) {
      onRunUpdated?.(event.pipeline_run);
    }
  });

  return { isConnected };
}

export function disconnectDevopsWebSocket() {
  if (wsManager) {
    wsManager.disconnect();
    wsManager = null;
  }
}
