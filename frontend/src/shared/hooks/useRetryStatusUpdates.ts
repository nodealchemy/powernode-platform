import { useEffect, useState, useCallback } from 'react';
import { useWebSocket } from './useWebSocket';

export interface RetryStatusUpdate {
  type: 'node_retry_scheduled' | 'node_retry_started' | 'node_retry_completed' | 'node_retry_failed' | 'retries_exhausted';
  node_id: string;
  node_execution_id: string;
  retry_attempt: number;
  max_retries: number;
  delay_ms: number;
  scheduled_at: string;
  error_type?: string;
  retry_stats?: {
    current_attempt: number;
    retries_remaining: number;
    total_retry_time_ms: number;
    last_retry_at: string;
    next_retry_delay_ms: number;
    retryable: boolean;
  };
  timestamp: string;
}

export interface CheckpointEvent {
  type: 'checkpoint_created' | 'checkpoint_restored';
  checkpoint_id: string;
  checkpoint_type: 'node_completed' | 'batch_completed' | 'manual' | 'error_handler' | 'conditional_branch';
  node_id?: string;
  sequence_number: number;
  progress_percentage: number;
  timestamp: string;
  metadata?: Record<string, any>;
}

export interface CircuitBreakerEvent {
  type: 'circuit_breaker_state_change' | 'circuit_breaker_alert' | 'circuit_breaker_warning';
  service: string;
  old_state?: 'closed' | 'open' | 'half_open';
  new_state?: 'closed' | 'open' | 'half_open';
  severity?: 'high' | 'medium' | 'low';
  message?: string;
  timestamp: string;
  stats?: Record<string, any>;
}

export interface UseRetryStatusUpdatesOptions {
  workflowRunId?: string;
  onRetryUpdate?: (update: RetryStatusUpdate) => void;
  onCheckpointEvent?: (event: CheckpointEvent) => void;
  onCircuitBreakerEvent?: (event: CircuitBreakerEvent) => void;
  enabled?: boolean;
}

export const useRetryStatusUpdates = ({
  workflowRunId,
  onRetryUpdate,
  onCheckpointEvent,
  onCircuitBreakerEvent,
  enabled = true
}: UseRetryStatusUpdatesOptions = {}) => {
  const [retryUpdates, setRetryUpdates] = useState<RetryStatusUpdate[]>([]);
  const [checkpointEvents, setCheckpointEvents] = useState<CheckpointEvent[]>([]);
  const [circuitBreakerEvents, setCircuitBreakerEvents] = useState<CircuitBreakerEvent[]>([]);
  const [latestUpdate, setLatestUpdate] = useState<RetryStatusUpdate | null>(null);

  // Get WebSocket connection
  const { isConnected, subscribe } = useWebSocket();

  // Subscribe to workflow-specific channel for retry and checkpoint events
  useEffect(() => {
    if (!enabled || !workflowRunId) return;

    const unsubscribe = subscribe({
      channel: `ai_workflow_run_${workflowRunId}`,
      onMessage: (message: any) => {
        // Handle retry status updates (including exhausted retries)
        if (message.type?.includes('retry') || message.type === 'retries_exhausted') {
          const update: RetryStatusUpdate = {
            type: message.type,
            node_id: message.node_id,
            node_execution_id: message.node_execution_id,
            retry_attempt: message.retry_attempt,
            max_retries: message.max_retries,
            delay_ms: message.delay_ms,
            scheduled_at: message.scheduled_at,
            error_type: message.error_type,
            retry_stats: message.retry_stats,
            timestamp: message.timestamp || new Date().toISOString()
          };

          setRetryUpdates(prev => [...prev, update]);
          setLatestUpdate(update);
          onRetryUpdate?.(update);
        }

        // Handle checkpoint events
        if (message.type?.includes('checkpoint')) {
          const event: CheckpointEvent = {
            type: message.type,
            checkpoint_id: message.checkpoint_id,
            checkpoint_type: message.checkpoint_type,
            node_id: message.node_id,
            sequence_number: message.sequence_number,
            progress_percentage: message.progress_percentage,
            timestamp: message.timestamp || new Date().toISOString(),
            metadata: message.metadata
          };

          setCheckpointEvents(prev => [...prev, event]);
          onCheckpointEvent?.(event);
        }
      }
    });

    return unsubscribe;
  }, [enabled, workflowRunId, subscribe, onRetryUpdate, onCheckpointEvent]);

  // Subscribe to global monitoring channel for circuit breaker events
  useEffect(() => {
    if (!enabled) return;

    const unsubscribe = subscribe({
      channel: 'ai_monitoring_channel',
      onMessage: (message: any) => {
        if (message.type?.includes('circuit_breaker')) {
          const event: CircuitBreakerEvent = {
            type: message.type,
            service: message.service || message.services?.[0],
            old_state: message.old_state,
            new_state: message.new_state,
            severity: message.severity,
            message: message.message,
            timestamp: message.timestamp || new Date().toISOString(),
            stats: message.stats
          };

          setCircuitBreakerEvents(prev => [...prev, event]);
          onCircuitBreakerEvent?.(event);
        }
      }
    });

    return unsubscribe;
  }, [enabled, subscribe, onCircuitBreakerEvent]);

  // Get retry status for specific node
  const getNodeRetryStatus = useCallback((nodeId: string) => {
    return retryUpdates
      .filter(update => update.node_id === nodeId)
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())[0];
  }, [retryUpdates]);

  // Get latest checkpoint event
  const getLatestCheckpoint = useCallback(() => {
    return checkpointEvents
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())[0];
  }, [checkpointEvents]);

  // Get circuit breaker status for service
  const getServiceCircuitStatus = useCallback((serviceName: string) => {
    return circuitBreakerEvents
      .filter(event => event.service === serviceName)
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())[0];
  }, [circuitBreakerEvents]);

  // Clear retry updates (useful for cleanup)
  const clearRetryUpdates = useCallback(() => {
    setRetryUpdates([]);
    setLatestUpdate(null);
  }, []);

  // Clear checkpoint events
  const clearCheckpointEvents = useCallback(() => {
    setCheckpointEvents([]);
  }, []);

  // Clear circuit breaker events
  const clearCircuitBreakerEvents = useCallback(() => {
    setCircuitBreakerEvents([]);
  }, []);

  // Get retry statistics
  const retryStats = {
    total_retries: retryUpdates.length,
    successful_retries: retryUpdates.filter(u => u.type === 'node_retry_completed').length,
    failed_retries: retryUpdates.filter(u => u.type === 'node_retry_failed').length,
    exhausted_retries: retryUpdates.filter(u => u.type === 'retries_exhausted').length,
    active_retries: retryUpdates.filter(u =>
      u.type === 'node_retry_scheduled' || u.type === 'node_retry_started'
    ).length
  };

  return {
    // Connection status
    isConnected,

    // Retry updates
    retryUpdates,
    latestUpdate,
    retryStats,
    getNodeRetryStatus,
    clearRetryUpdates,

    // Checkpoint events
    checkpointEvents,
    getLatestCheckpoint,
    clearCheckpointEvents,

    // Circuit breaker events
    circuitBreakerEvents,
    getServiceCircuitStatus,
    clearCircuitBreakerEvents
  };
};

// Hook for monitoring specific node retry status
export const useNodeRetryStatus = (workflowRunId: string, nodeId: string) => {
  const [status, setStatus] = useState<RetryStatusUpdate | null>(null);

  const { getNodeRetryStatus } = useRetryStatusUpdates({
    workflowRunId,
    onRetryUpdate: (update) => {
      if (update.node_id === nodeId) {
        setStatus(update);
      }
    },
    enabled: !!workflowRunId && !!nodeId
  });

  useEffect(() => {
    const currentStatus = getNodeRetryStatus(nodeId);
    if (currentStatus) {
      setStatus(currentStatus);
    }
  }, [nodeId, getNodeRetryStatus]);

  return status;
};

// Hook for monitoring checkpoint creation
export const useCheckpointMonitor = (workflowRunId: string) => {
  const [checkpoints, setCheckpoints] = useState<CheckpointEvent[]>([]);
  const [latestCheckpoint, setLatestCheckpoint] = useState<CheckpointEvent | null>(null);

  useRetryStatusUpdates({
    workflowRunId,
    onCheckpointEvent: (event) => {
      setCheckpoints(prev => [...prev, event]);
      setLatestCheckpoint(event);
    },
    enabled: !!workflowRunId
  });

  return {
    checkpoints,
    latestCheckpoint,
    checkpointCount: checkpoints.length
  };
};

// Hook for monitoring circuit breaker health
export const useCircuitBreakerMonitor = () => {
  const [serviceStates, setServiceStates] = useState<Map<string, CircuitBreakerEvent>>(new Map());
  const [alerts, setAlerts] = useState<CircuitBreakerEvent[]>([]);

  useRetryStatusUpdates({
    onCircuitBreakerEvent: (event) => {
      // Update service state
      if (event.type === 'circuit_breaker_state_change') {
        setServiceStates(prev => new Map(prev).set(event.service, event));
      }

      // Track alerts
      if (event.type === 'circuit_breaker_alert' || event.type === 'circuit_breaker_warning') {
        setAlerts(prev => [...prev, event]);
      }
    }
  });

  const getServiceState = (serviceName: string) => {
    return serviceStates.get(serviceName);
  };

  const clearAlerts = () => {
    setAlerts([]);
  };

  return {
    serviceStates: Array.from(serviceStates.values()),
    alerts,
    getServiceState,
    clearAlerts,
    unhealthyServices: Array.from(serviceStates.values())
      .filter(state => state.new_state === 'open').length,
    degradedServices: Array.from(serviceStates.values())
      .filter(state => state.new_state === 'half_open').length
  };
};
