// WebSocket hook for real-time Ralph Loop execution monitoring
import { useEffect, useRef, useState, useCallback } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

// Ralph Loop event types
export type RalphLoopEventType =
  | 'loop_started'
  | 'loop_progress'
  | 'iteration_completed'
  | 'task_status_changed'
  | 'learning_added'
  | 'loop_completed'
  | 'loop_failed'
  | 'loop_paused'
  | 'loop_cancelled';

export interface RalphLoopExecutionUpdate {
  type: RalphLoopEventType;
  loop_id: string;
  status?: string;
  progress_percentage?: number;
  current_iteration?: number;
  completed_task_count?: number;
  task_count?: number;
  task_id?: string;
  task_status?: string;
  learning?: string;
  error_message?: string;
  timestamp: string;
  data?: Record<string, unknown>;
}

interface UseRalphLoopExecutionWebSocketOptions {
  loopId?: string;
  onUpdate?: (update: RalphLoopExecutionUpdate) => void;
  enabled?: boolean;
}

export const useRalphLoopExecutionWebSocket = (
  options: UseRalphLoopExecutionWebSocketOptions = {}
) => {
  const { loopId, onUpdate, enabled = true } = options;
  const { isConnected, subscribe, error: connectionError } = useWebSocket();
  const [lastUpdate, setLastUpdate] = useState<RalphLoopExecutionUpdate | null>(null);
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Store latest callback ref to avoid dependency issues
  const onUpdateRef = useRef(onUpdate);
  onUpdateRef.current = onUpdate;

  // Type guard for WebSocket message data
  const isRalphLoopMessage = (data: unknown): data is { message?: RalphLoopExecutionUpdate; type?: string; event?: string; payload?: Record<string, unknown> } => {
    return typeof data === 'object' && data !== null;
  };

  // Map backend event types to frontend event types
  const mapBackendEventType = (backendEvent: string): RalphLoopEventType => {
    const eventMap: Record<string, RalphLoopEventType> = {
      'ralph_loop.started': 'loop_started',
      'ralph_loop.progress': 'loop_progress',
      'ralph_loop.iteration_completed': 'iteration_completed',
      'ralph_loop.task_status_changed': 'task_status_changed',
      'ralph_loop.learning_added': 'learning_added',
      'ralph_loop.completed': 'loop_completed',
      'ralph_loop.failed': 'loop_failed',
      'ralph_loop.paused': 'loop_paused',
      'ralph_loop.cancelled': 'loop_cancelled',
      // Also handle generic ralph_loop_update from backend
      'ralph_loop_update': 'loop_progress',
    };
    return eventMap[backendEvent] || 'loop_progress';
  };

  // Handle incoming messages
  const handleMessage = useCallback((data: unknown) => {
    if (!isRalphLoopMessage(data)) return;

    let update: RalphLoopExecutionUpdate | null = null;

    // Handle direct message format from AiOrchestrationChannel
    if (data.message) {
      update = data.message as RalphLoopExecutionUpdate;
    }
    // Handle event-based format
    else if (data.event || data.type) {
      const eventType = data.event || data.type || '';
      const payload = data.payload || {};

      update = {
        type: mapBackendEventType(eventType),
        loop_id: (payload.loop_id || loopId || '') as string,
        status: payload.status as string | undefined,
        progress_percentage: payload.progress_percentage as number | undefined,
        current_iteration: payload.current_iteration as number | undefined,
        completed_task_count: payload.completed_task_count as number | undefined,
        task_count: payload.task_count as number | undefined,
        task_id: payload.task_id as string | undefined,
        task_status: payload.task_status as string | undefined,
        learning: payload.learning as string | undefined,
        error_message: payload.error_message as string | undefined,
        timestamp: (payload.timestamp as string) || new Date().toISOString(),
        data: payload,
      };
    }

    if (update) {
      setLastUpdate(update);
      onUpdateRef.current?.(update);
    }
  }, [loopId]);

  // Handle errors
  const handleError = useCallback((errorMessage: string) => {
    if (process.env.NODE_ENV === 'development') {
      console.warn('[RalphLoopExecutionWebSocket] Error:', errorMessage);
    }
  }, []);

  // Subscribe to Ralph Loop events
  useEffect(() => {
    if (!enabled || !loopId || !isConnected) {
      return;
    }

    // Unsubscribe from previous subscription
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
      unsubscribeRef.current = null;
    }

    // Subscribe to AiOrchestrationChannel with ralph_loop type
    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'ralph_loop', ralph_loop_id: loopId },
      onMessage: handleMessage,
      onError: handleError,
    });

    unsubscribeRef.current = unsubscribe;

    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [loopId, enabled, isConnected, subscribe, handleMessage, handleError]);

  return {
    isConnected: isConnected && enabled && !!loopId,
    lastUpdate,
    error: connectionError,
  };
};

export default useRalphLoopExecutionWebSocket;
