import { useCallback, useRef, useEffect, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import type { SystemOperation } from '@/features/system/types/system.types';

// WebSocket event types for System channel
type SystemEventType =
  | 'connection_established'
  | 'operation_updated'
  | 'operation_progress'
  | 'operations_list'
  | 'operation_status'
  | 'node_updated'
  | 'instance_updated'
  | 'stats_updated'
  | 'system_stats'
  | 'pong'
  | 'error';

// Operation update payload
export interface OperationUpdatePayload {
  id: string;
  command: string;
  status: SystemOperation['status'];
  progress: number;
  description?: string;
  error_message?: string;
  scheduled_at?: string;
  started_at?: string;
  completed_at?: string;
  operable_type?: string;
  operable_id?: string;
  created_at: string;
  updated_at: string;
}

// Operation progress payload (lightweight)
export interface OperationProgressPayload {
  operation_id: string;
  status: SystemOperation['status'];
  progress: number;
  description?: string;
}

// Node update payload
export interface NodeUpdatePayload {
  id: string;
  name: string;
  enabled: boolean;
  public_address?: string;
  instances_count: number;
  created_at: string;
  updated_at: string;
}

// Instance update payload
export interface InstanceUpdatePayload {
  id: string;
  name: string;
  status: string;
  variety: string;
  private_ip_address?: string;
  public_ip_address?: string;
  node_id: string;
  created_at: string;
  updated_at: string;
}

// System stats payload
interface SystemStatsPayload {
  nodes: { total: number; enabled: number };
  instances: { total: number; running: number; stopped: number };
  operations: { total: number; pending: number; running: number };
}

interface UseSystemWebSocketOptions {
  /** Called when an operation is created or updated */
  onOperationUpdate?: (operation: OperationUpdatePayload) => void;
  /** Called when an operation progress changes (lightweight update) */
  onOperationProgress?: (progress: OperationProgressPayload) => void;
  /** Called when a full operations list is received */
  onOperationsList?: (operations: OperationUpdatePayload[]) => void;
  /** Called when a node is created or updated */
  onNodeUpdate?: (node: NodeUpdatePayload) => void;
  /** Called when an instance is created or updated */
  onInstanceUpdate?: (instance: InstanceUpdatePayload) => void;
  /** Called when stats should be refreshed (stats_updated signal) */
  onStatsUpdate?: () => void;
  /** Called when full stats are received */
  onStatsReceived?: (stats: SystemStatsPayload) => void;
  /** Called when connection is established */
  onConnected?: () => void;
  /** Called on error */
  onError?: (error: string) => void;
}

interface UseSystemWebSocketReturn {
  /** Whether WebSocket is connected */
  isConnected: boolean;
  /** Any connection error */
  error: string | null;
  /** Request a refresh of operations list */
  refreshOperations: () => Promise<boolean>;
  /** Request a specific operation's status */
  getOperation: (operationId: string) => Promise<boolean>;
  /** Request system statistics */
  refreshStats: () => Promise<boolean>;
  /** Ping the server */
  ping: () => Promise<boolean>;
}

/**
 * useSystemWebSocket - WebSocket hook for real-time System updates
 *
 * Subscribes to the SystemChannel for real-time updates on:
 * - Operation status and progress changes
 * - Node updates
 * - Instance updates
 * - System statistics
 *
 * @example
 * ```tsx
 * const {
 *   isConnected,
 *   refreshOperations,
 *   refreshStats
 * } = useSystemWebSocket({
 *   onOperationUpdate: (op) => {
 *     // Update operations list in state
 *     setOperations(prev => prev.map(o => o.id === op.id ? op : o));
 *   },
 *   onOperationProgress: (progress) => {
 *     // Update just the progress of an operation
 *     setOperations(prev => prev.map(o =>
 *       o.id === progress.operation_id
 *         ? { ...o, status: progress.status, progress: progress.progress }
 *         : o
 *     ));
 *   },
 *   onStatsUpdate: () => {
 *     // Trigger stats refresh via API
 *     fetchStats();
 *   }
 * });
 * ```
 */
export const useSystemWebSocket = ({
  onOperationUpdate,
  onOperationProgress,
  onOperationsList,
  onNodeUpdate,
  onInstanceUpdate,
  onStatsUpdate,
  onStatsReceived,
  onConnected,
  onError
}: UseSystemWebSocketOptions = {}): UseSystemWebSocketReturn => {
  const { isConnected, subscribe, sendMessage, error: connectionError } = useWebSocket();
  const user = useSelector((state: RootState) => state.auth.user);
  const unsubscribeRef = useRef<(() => void) | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Store latest callback refs to avoid dependency issues
  const callbackRefs = useRef({
    onOperationUpdate,
    onOperationProgress,
    onOperationsList,
    onNodeUpdate,
    onInstanceUpdate,
    onStatsUpdate,
    onStatsReceived,
    onConnected,
    onError
  });

  // Update refs when callbacks change
  useEffect(() => {
    callbackRefs.current = {
      onOperationUpdate,
      onOperationProgress,
      onOperationsList,
      onNodeUpdate,
      onInstanceUpdate,
      onStatsUpdate,
      onStatsReceived,
      onConnected,
      onError
    };
  }, [
    onOperationUpdate,
    onOperationProgress,
    onOperationsList,
    onNodeUpdate,
    onInstanceUpdate,
    onStatsUpdate,
    onStatsReceived,
    onConnected,
    onError
  ]);

  // Type guard for WebSocket message data
  const isWebSocketMessage = (data: unknown): data is { type: SystemEventType; [key: string]: unknown } => {
    return typeof data === 'object' && data !== null && 'type' in data;
  };

  // Handle incoming messages
  const handleMessage = useCallback((data: unknown) => {
    if (!isWebSocketMessage(data)) return;

    const refs = callbackRefs.current;

    switch (data.type) {
      case 'connection_established':
        refs.onConnected?.();
        break;

      case 'operation_updated':
        if (data.operation) {
          refs.onOperationUpdate?.(data.operation as OperationUpdatePayload);
        }
        break;

      case 'operation_progress':
        refs.onOperationProgress?.({
          operation_id: data.operation_id as string,
          status: data.status as SystemOperation['status'],
          progress: data.progress as number,
          description: data.description as string | undefined
        });
        break;

      case 'operations_list':
        if (data.operations) {
          refs.onOperationsList?.(data.operations as OperationUpdatePayload[]);
        }
        break;

      case 'operation_status':
        if (data.operation) {
          refs.onOperationUpdate?.(data.operation as OperationUpdatePayload);
        }
        break;

      case 'node_updated':
        if (data.node) {
          refs.onNodeUpdate?.(data.node as NodeUpdatePayload);
        }
        break;

      case 'instance_updated':
        if (data.instance) {
          refs.onInstanceUpdate?.(data.instance as InstanceUpdatePayload);
        }
        break;

      case 'stats_updated':
        refs.onStatsUpdate?.();
        break;

      case 'system_stats':
        if (data.stats) {
          refs.onStatsReceived?.(data.stats as SystemStatsPayload);
        }
        break;

      case 'pong':
        // Connection test response - no action needed
        break;

      case 'error':
        const errorMessage = (data.message as string) || 'System channel error';
        setError(errorMessage);
        refs.onError?.(errorMessage);
        break;
    }
  }, []);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    setError(errorMessage);
    callbackRefs.current.onError?.(errorMessage);
  }, []);

  // Subscribe to System channel
  const subscribeToSystem = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }

    // Only subscribe if user has an account
    if (!user?.account?.id) {
      if (process.env.NODE_ENV === 'development') {
        // eslint-disable-next-line no-console
        console.warn('[SystemWebSocket] Cannot subscribe: user account not available');
      }
      return;
    }

    unsubscribeRef.current = subscribe({
      channel: 'SystemChannel',
      params: { account_id: user.account.id },
      onMessage: handleMessage,
      onError: handleError
    });
  }, [subscribe, handleMessage, handleError, user?.account?.id]);

  // Request operations list
  const refreshOperations = useCallback(async (): Promise<boolean> => {
    if (!isConnected || !user?.account?.id) {
      return false;
    }
    return sendMessage('SystemChannel', 'refresh_operations', {}, { account_id: user.account.id });
  }, [isConnected, sendMessage, user?.account?.id]);

  // Request specific operation status
  const getOperation = useCallback(async (operationId: string): Promise<boolean> => {
    if (!isConnected || !user?.account?.id) {
      return false;
    }
    return sendMessage('SystemChannel', 'get_operation', { operation_id: operationId }, { account_id: user.account.id });
  }, [isConnected, sendMessage, user?.account?.id]);

  // Request stats refresh
  const refreshStats = useCallback(async (): Promise<boolean> => {
    if (!isConnected || !user?.account?.id) {
      return false;
    }
    return sendMessage('SystemChannel', 'refresh_stats', {}, { account_id: user.account.id });
  }, [isConnected, sendMessage, user?.account?.id]);

  // Ping the server
  const ping = useCallback(async (): Promise<boolean> => {
    if (!isConnected || !user?.account?.id) {
      return false;
    }
    return sendMessage('SystemChannel', 'ping', {}, { account_id: user.account.id });
  }, [isConnected, sendMessage, user?.account?.id]);

  // Auto-subscribe when connected
  useEffect(() => {
    if (isConnected) {
      subscribeToSystem();
    }

    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [isConnected, subscribeToSystem]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      setError(connectionError);
      callbackRefs.current.onError?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    error: error || connectionError,
    refreshOperations,
    getOperation,
    refreshStats,
    ping
  };
};

export default useSystemWebSocket;
