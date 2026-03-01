# WebSocket Integration Guide

**Real-time communication patterns and hook architecture**

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Base WebSocket Hook](#base-websocket-hook)
4. [Domain-Specific Hooks](#domain-specific-hooks)
5. [Connection Management](#connection-management)
6. [Error Handling](#error-handling)
7. [Best Practices](#best-practices)

---

## Overview

Powernode uses ActionCable (Rails WebSocket) for real-time updates. The frontend implements a singleton WebSocket manager with domain-specific hooks for type-safe channel subscriptions.

### Key Features

- **Singleton Connection**: Single WebSocket shared across all components
- **Auto-Reconnection**: Exponential backoff on connection loss
- **Token Refresh**: Automatic token refresh on auth errors
- **Type-Safe Hooks**: Domain-specific hooks with typed payloads
- **Cleanup**: Proper subscription cleanup on unmount

---

## Architecture

### WebSocket Layer

```
┌─────────────────────────────────────────────────────────────┐
│                     React Components                         │
├─────────────────────────────────────────────────────────────┤
│  useAiMonitoringWebSocket  │  useMcpWebSocket  │  useXxxWS  │
├─────────────────────────────────────────────────────────────┤
│                      useWebSocket (Base Hook)                │
├─────────────────────────────────────────────────────────────┤
│                    WebSocketManager (Singleton)              │
├─────────────────────────────────────────────────────────────┤
│                    Browser WebSocket API                     │
├─────────────────────────────────────────────────────────────┤
│                   Rails ActionCable Server                   │
└─────────────────────────────────────────────────────────────┘
```

### Hook Directory

```
frontend/src/shared/hooks/
├── useWebSocket.ts                    # Base WebSocket hook
├── useWebSocket.test.ts
│
├── # AI/Orchestration
├── useAiMonitoringWebSocket.ts        # AI execution monitoring
├── useAiMonitoringWebSocket.test.ts
├── useAiOrchestrationWebSocket.ts     # Workflow orchestration
├── useAiStreamingWebSocket.ts         # AI streaming responses
├── useAiStreamingWebSocket.test.ts
│
├── # MCP/Workflows
├── useMcpWebSocket.ts                 # MCP channel updates
│
├── # Business
├── useSubscriptionWebSocket.ts        # Subscription changes
├── useCustomerWebSocket.ts            # Customer updates
├── useCustomerWebSocket.test.ts
│
├── # System
├── useAnalyticsWebSocket.ts           # Analytics updates
├── useAnalyticsWebSocket.test.ts
├── useNotificationWebSocket.ts        # User notifications
├── useNotificationWebSocket.test.ts
├── useSettingsWebSocket.ts            # Settings changes
└── usePageWebSocket.ts                # CMS page updates
```

---

## Base WebSocket Hook

**File**: `frontend/src/shared/hooks/useWebSocket.ts`

### Interface

```typescript
interface WebSocketState {
  isConnected: boolean;
  error: string | null;
  lastConnected: Date | null;
}

interface ChannelSubscription {
  channel: string;
  params?: Record<string, unknown>;
  onMessage?: (data: unknown) => void;
  onError?: (error: string) => void;
}

interface UseWebSocketReturn {
  isConnected: boolean;
  error: string | null;
  lastConnected: Date | null;
  subscribe: (subscription: ChannelSubscription) => () => void;
  sendMessage: (
    channel: string,
    action: string,
    data?: Record<string, unknown>,
    params?: Record<string, unknown>
  ) => Promise<boolean>;
}
```

### Usage

```typescript
import { useWebSocket } from '@/shared/hooks/useWebSocket';

const MyComponent = () => {
  const { isConnected, error, subscribe, sendMessage } = useWebSocket();

  useEffect(() => {
    if (!isConnected) return;

    const unsubscribe = subscribe({
      channel: 'MyChannel',
      params: { id: '123' },
      onMessage: (data) => {
        console.log('Received:', data);
      },
      onError: (error) => {
        console.error('Channel error:', error);
      },
    });

    return unsubscribe;
  }, [isConnected, subscribe]);

  const handleSend = async () => {
    await sendMessage('MyChannel', 'custom_action', { data: 'value' });
  };

  return (
    <div>
      <p>Connected: {isConnected ? 'Yes' : 'No'}</p>
      {error && <p>Error: {error}</p>}
      <button onClick={handleSend}>Send Message</button>
    </div>
  );
};
```

### Implementation Details

```typescript
export const useWebSocket = (): UseWebSocketReturn => {
  const { user, access_token } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch<AppDispatch>();
  const mountedRef = useRef<boolean>(true);

  const [state, setState] = useState<WebSocketState>({
    isConnected: false,
    error: null,
    lastConnected: null,
  });

  // Build WebSocket URL with auth token
  const getWebSocketUrl = useCallback(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.hostname;
    const port = host === 'localhost' ? ':3000' : '';
    const baseUrl = `${protocol}//${host}${port}/cable`;
    return access_token ? `${baseUrl}?token=${encodeURIComponent(access_token)}` : baseUrl;
  }, [access_token]);

  // Initialize WebSocket manager
  useEffect(() => {
    if (user?.account?.id && access_token) {
      wsManager.initialize({
        getUrl: getWebSocketUrl,
        onConnect: () => setState({ isConnected: true, error: null, lastConnected: new Date() }),
        onDisconnect: (code, reason) => {
          setState(prev => ({ ...prev, isConnected: false, error: reason }));
        },
        onError: () => {
          setState(prev => ({ ...prev, isConnected: false, error: 'WebSocket error' }));
        },
      });
    }
  }, [user?.account?.id, access_token, getWebSocketUrl]);

  // Subscribe to channel
  const subscribe = useCallback((subscription: ChannelSubscription) => {
    return wsManager.subscribe(subscription);
  }, []);

  // Send message to channel
  const sendMessage = useCallback(async (
    channel: string,
    action: string,
    data?: Record<string, unknown>,
    params?: Record<string, unknown>
  ): Promise<boolean> => {
    return wsManager.sendMessage(channel, action, data, params);
  }, []);

  return { ...state, subscribe, sendMessage };
};
```

---

## Domain-Specific Hooks

### AI Monitoring WebSocket

**File**: `useAiMonitoringWebSocket.ts`

Monitors AI agent executions in real-time.

```typescript
interface AiExecutionUpdate {
  execution_id: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  progress?: number;
  output?: string;
  error?: string;
  cost?: number;
  tokens_used?: number;
}

interface UseAiMonitoringWebSocketReturn {
  isConnected: boolean;
  currentExecution: AiExecutionUpdate | null;
  subscribeToExecution: (executionId: string) => () => void;
}

export const useAiMonitoringWebSocket = (): UseAiMonitoringWebSocketReturn => {
  const { isConnected, subscribe } = useWebSocket();
  const [currentExecution, setCurrentExecution] = useState<AiExecutionUpdate | null>(null);

  const subscribeToExecution = useCallback((executionId: string) => {
    return subscribe({
      channel: 'AiMonitoringChannel',
      params: { execution_id: executionId },
      onMessage: (data) => {
        const update = data as AiExecutionUpdate;
        setCurrentExecution(update);
      },
    });
  }, [subscribe]);

  return { isConnected, currentExecution, subscribeToExecution };
};
```

### AI Orchestration WebSocket

**File**: `useAiOrchestrationWebSocket.ts`

Handles workflow execution updates.

```typescript
interface WorkflowRunUpdate {
  run_id: string;
  workflow_id: string;
  status: 'initializing' | 'running' | 'completed' | 'failed';
  current_node?: string;
  progress?: number;
  node_statuses?: Record<string, string>;
}

export const useAiOrchestrationWebSocket = () => {
  const { isConnected, subscribe } = useWebSocket();

  const subscribeToWorkflowRun = useCallback((runId: string, onUpdate: (update: WorkflowRunUpdate) => void) => {
    return subscribe({
      channel: 'AiOrchestrationChannel',
      params: { run_id: runId },
      onMessage: (data) => {
        onUpdate(data as WorkflowRunUpdate);
      },
    });
  }, [subscribe]);

  return { isConnected, subscribeToWorkflowRun };
};
```

### MCP WebSocket

**File**: `useMcpWebSocket.ts`

MCP protocol channel for workflow nodes.

```typescript
interface McpNodeUpdate {
  event: string;
  params: {
    workflow_id: string;
    node_id: string;
    status: string;
    output?: unknown;
  };
}

export const useMcpWebSocket = () => {
  const { isConnected, subscribe } = useWebSocket();

  const subscribeToWorkflow = useCallback((
    workflowId: string,
    onNodeUpdate: (update: McpNodeUpdate) => void
  ) => {
    return subscribe({
      channel: 'McpChannel',
      params: { workflow_id: workflowId },
      onMessage: (data) => {
        const update = data as McpNodeUpdate;
        if (update.params?.workflow_id === workflowId) {
          onNodeUpdate(update);
        }
      },
    });
  }, [subscribe]);

  return { isConnected, subscribeToWorkflow };
};
```

### Notification WebSocket

**File**: `useNotificationWebSocket.ts`

User notification updates.

```typescript
interface NotificationUpdate {
  id: string;
  type: 'info' | 'success' | 'warning' | 'error';
  title: string;
  message: string;
  read: boolean;
  created_at: string;
}

export const useNotificationWebSocket = () => {
  const { isConnected, subscribe } = useWebSocket();
  const dispatch = useDispatch();

  useEffect(() => {
    if (!isConnected) return;

    const unsubscribe = subscribe({
      channel: 'NotificationChannel',
      onMessage: (data) => {
        const notification = data as NotificationUpdate;
        dispatch(addNotification({
          type: notification.type,
          message: notification.message,
        }));
      },
    });

    return unsubscribe;
  }, [isConnected, subscribe, dispatch]);

  return { isConnected };
};
```

### Subscription WebSocket

**File**: `useSubscriptionWebSocket.ts`

Subscription status changes.

```typescript
interface SubscriptionUpdate {
  subscription_id: string;
  event: 'created' | 'updated' | 'cancelled' | 'renewed';
  subscription: Subscription;
}

export const useSubscriptionWebSocket = (onUpdate?: (update: SubscriptionUpdate) => void) => {
  const { isConnected, subscribe } = useWebSocket();

  useEffect(() => {
    if (!isConnected || !onUpdate) return;

    const unsubscribe = subscribe({
      channel: 'SubscriptionChannel',
      onMessage: (data) => {
        onUpdate(data as SubscriptionUpdate);
      },
    });

    return unsubscribe;
  }, [isConnected, subscribe, onUpdate]);

  return { isConnected };
};
```

---

## Connection Management

### WebSocket Manager

The singleton manager handles connection lifecycle:

```typescript
class WebSocketManager {
  private ws: WebSocket | null = null;
  private subscriptions: Map<string, ChannelSubscription> = new Map();
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;

  initialize(config: WebSocketConfig) {
    // Connect and setup handlers
  }

  subscribe(subscription: ChannelSubscription): () => void {
    // Add subscription and return cleanup function
  }

  sendMessage(channel: string, action: string, data?: unknown): Promise<boolean> {
    // Send message through WebSocket
  }

  reconnect() {
    // Reconnect with exponential backoff
  }

  disconnect() {
    // Clean disconnect
  }
}
```

### Reconnection Strategy

```typescript
private handleDisconnect(code: number, reason: string) {
  if (this.reconnectAttempts >= this.maxReconnectAttempts) {
    this.notifyListeners(false, 'Max reconnection attempts reached');
    return;
  }

  const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);
  this.reconnectAttempts++;

  setTimeout(() => {
    this.connect();
  }, delay);
}
```

### Token Refresh

```typescript
private handleUnauthorized() {
  if (this.isRefreshingToken) return;

  this.isRefreshingToken = true;

  store.dispatch(refreshAccessToken())
    .unwrap()
    .then(() => {
      this.isRefreshingToken = false;
      this.reconnect();
    })
    .catch(() => {
      this.isRefreshingToken = false;
      this.notifyListeners(false, 'Session expired');
    });
}
```

---

## Error Handling

### Connection Errors

```typescript
useEffect(() => {
  const unsubscribe = subscribe({
    channel: 'MyChannel',
    onMessage: handleMessage,
    onError: (error) => {
      console.error('Channel error:', error);

      // Retry logic
      if (retryCount < 3) {
        setRetryCount(prev => prev + 1);
        setTimeout(() => {
          // Re-subscribe
        }, 2000 * retryCount);
      } else {
        showNotification('Connection lost. Please refresh.', 'error');
      }
    },
  });

  return unsubscribe;
}, [subscribe, retryCount]);
```

### Fallback to Polling

```typescript
const useFallbackPolling = (channel: string, fetchData: () => void) => {
  const { isConnected, subscribe } = useWebSocket();
  const [isPolling, setIsPolling] = useState(false);

  useEffect(() => {
    if (isConnected) {
      setIsPolling(false);
      return subscribe({ channel, onMessage: () => fetchData() });
    } else {
      // Fall back to polling
      setIsPolling(true);
      const interval = setInterval(fetchData, 10000);
      return () => clearInterval(interval);
    }
  }, [isConnected, subscribe, channel, fetchData]);

  return { isPolling };
};
```

---

## Best Practices

### 1. Clean Subscription Management

```typescript
useEffect(() => {
  // Don't subscribe if not connected
  if (!isConnected) return;

  const unsubscribe = subscribe({
    channel: 'MyChannel',
    onMessage: handleMessage,
  });

  // Always return cleanup
  return unsubscribe;
}, [isConnected, subscribe]);
```

### 2. Debounce High-Frequency Updates

```typescript
const useDebouncedWebSocket = (channel: string, delay: number = 100) => {
  const [data, setData] = useState<unknown>(null);
  const { isConnected, subscribe } = useWebSocket();

  useEffect(() => {
    if (!isConnected) return;

    let timeoutId: NodeJS.Timeout;

    const unsubscribe = subscribe({
      channel,
      onMessage: (newData) => {
        clearTimeout(timeoutId);
        timeoutId = setTimeout(() => setData(newData), delay);
      },
    });

    return () => {
      unsubscribe();
      clearTimeout(timeoutId);
    };
  }, [isConnected, subscribe, channel, delay]);

  return data;
};
```

### 3. Type-Safe Message Handlers

```typescript
interface TypedMessage<T> {
  event: string;
  payload: T;
}

const handleMessage = <T>(data: unknown, handler: (payload: T) => void) => {
  const message = data as TypedMessage<T>;
  if (message.event && message.payload) {
    handler(message.payload);
  }
};
```

### 4. Conditional Subscriptions

```typescript
const useConditionalSubscription = (
  shouldSubscribe: boolean,
  channel: string,
  onMessage: (data: unknown) => void
) => {
  const { isConnected, subscribe } = useWebSocket();

  useEffect(() => {
    if (!isConnected || !shouldSubscribe) return;

    return subscribe({ channel, onMessage });
  }, [isConnected, shouldSubscribe, subscribe, channel, onMessage]);
};
```

### 5. Status Indicators

```typescript
const ConnectionStatus = () => {
  const { isConnected, error, lastConnected } = useWebSocket();

  return (
    <div className="flex items-center gap-2">
      <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-green-500' : 'bg-red-500'}`} />
      <span>{isConnected ? 'Connected' : 'Disconnected'}</span>
      {error && <span className="text-red-500">{error}</span>}
      {lastConnected && (
        <span className="text-gray-500">
          Last: {lastConnected.toLocaleTimeString()}
        </span>
      )}
    </div>
  );
};
```

---

## Testing

### Mock WebSocket

```typescript
// __mocks__/useWebSocket.ts
export const mockSubscribe = jest.fn(() => jest.fn());
export const mockSendMessage = jest.fn(() => Promise.resolve(true));

export const useWebSocket = () => ({
  isConnected: true,
  error: null,
  lastConnected: new Date(),
  subscribe: mockSubscribe,
  sendMessage: mockSendMessage,
});
```

### Hook Testing

```typescript
import { renderHook, act } from '@testing-library/react-hooks';
import { useAiMonitoringWebSocket } from './useAiMonitoringWebSocket';
import { mockSubscribe } from './__mocks__/useWebSocket';

jest.mock('./useWebSocket');

describe('useAiMonitoringWebSocket', () => {
  it('should subscribe to execution', () => {
    const { result } = renderHook(() => useAiMonitoringWebSocket());

    act(() => {
      result.current.subscribeToExecution('exec-123');
    });

    expect(mockSubscribe).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: 'AiMonitoringChannel',
        params: { execution_id: 'exec-123' },
      })
    );
  });
});
```

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `frontend/src/shared/hooks/use*WebSocket*.ts`
