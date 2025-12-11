import { useState, useEffect, useCallback, useRef } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { workflowsApi } from '@/shared/services/ai';
import type {
  StreamingMessage,
  StreamingExecutionState
} from '../components/streaming/StreamingExecutionPanel';

interface StreamingExecutionMessage {
  event: string;
  payload: {
    run_id?: string;
    workflow_id?: string;
    workflow_name?: string;
    message?: StreamingMessage;
    status?: StreamingExecutionState['status'];
    current_node?: StreamingExecutionState['current_node'];
    metrics?: StreamingExecutionState['metrics'];
    error?: string;
  };
}

interface UseStreamingExecutionOptions {
  onMessageReceived?: (message: StreamingMessage) => void;
  onStreamStarted?: (runId: string) => void;
  onStreamCompleted?: (runId: string) => void;
  onStreamFailed?: (runId: string, error: string) => void;
  maxMessages?: number; // Limit stored messages to prevent memory issues
}

interface UseStreamingExecutionReturn {
  // State
  executionState: StreamingExecutionState | null;
  isStreaming: boolean;
  error: string | null;
  isConnected: boolean;

  // Actions
  startStreaming: (workflowId: string, inputVariables?: Record<string, any>) => Promise<string>;
  pauseStreaming: () => Promise<void>;
  resumeStreaming: () => Promise<void>;
  stopStreaming: () => Promise<void>;
  retryStreaming: () => Promise<void>;
  clearStream: () => void;
}

/**
 * Custom hook for managing streaming workflow execution
 *
 * Provides real-time streaming execution with message accumulation,
 * metrics tracking, and lifecycle controls.
 *
 * @example
 * ```tsx
 * const {
 *   executionState,
 *   isStreaming,
 *   startStreaming,
 *   pauseStreaming,
 *   stopStreaming
 * } = useStreamingExecution({
 *   onMessageReceived: (message) => {
 *   },
 *   maxMessages: 1000
 * });
 *
 * // Start streaming execution
 * await startStreaming('workflow-id', { input: 'value' });
 * ```
 */
export const useStreamingExecution = (
  options: UseStreamingExecutionOptions = {}
): UseStreamingExecutionReturn => {
  const [executionState, setExecutionState] = useState<StreamingExecutionState | null>(null);
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastWorkflowId, setLastWorkflowId] = useState<string | null>(null);
  const [lastInputVariables, setLastInputVariables] = useState<Record<string, any> | undefined>(undefined);

  const { addNotification } = useNotifications();
  const { isConnected, subscribe } = useWebSocket();

  const optionsRef = useRef(options);
  optionsRef.current = options;

  const messageCountRef = useRef(0);

  /**
   * Handle streaming messages from WebSocket
   */
  const handleStreamingMessage = useCallback((data: unknown) => {
    const message = data as StreamingExecutionMessage;
    const { event, payload } = message;

    switch (event) {
      case 'streaming.execution.started':
      case 'stream_started': {
        const newState: StreamingExecutionState = {
          run_id: payload.run_id || '',
          workflow_id: payload.workflow_id || '',
          workflow_name: payload.workflow_name || 'Unknown Workflow',
          status: 'streaming',
          messages: [],
          started_at: new Date().toISOString(),
          metrics: {
            total_tokens: 0,
            total_cost: 0,
            avg_latency_ms: 0,
            message_count: 0
          }
        };

        setExecutionState(newState);
        setIsStreaming(true);
        setError(null);
        messageCountRef.current = 0;

        if (payload.run_id) {
          optionsRef.current.onStreamStarted?.(payload.run_id);
        }

        addNotification({
          type: 'info',
          title: 'Streaming Started',
          message: 'Real-time execution streaming initiated'
        });
        break;
      }

      case 'streaming.message.received':
      case 'stream_message': {
        if (!payload.message) break;

        setExecutionState(prev => {
          if (!prev) return null;

          const newMessage = payload.message!;
          const messages = [...prev.messages, newMessage];

          // Apply max message limit if specified
          const maxMessages = optionsRef.current.maxMessages || 10000;
          if (messages.length > maxMessages) {
            messages.shift(); // Remove oldest message
          }

          messageCountRef.current = messages.length;

          // Update metrics
          const metrics = { ...prev.metrics! };
          metrics.message_count = messages.length;

          if (newMessage.metadata?.tokens) {
            metrics.total_tokens += newMessage.metadata.tokens;
          }

          if (newMessage.metadata?.latency_ms) {
            // Calculate running average latency
            const totalLatency = metrics.avg_latency_ms * (messages.length - 1) + newMessage.metadata.latency_ms;
            metrics.avg_latency_ms = Math.round(totalLatency / messages.length);
          }

          // Estimate cost based on tokens (rough estimate: $0.002 per 1K tokens)
          metrics.total_cost = (metrics.total_tokens / 1000) * 0.002;

          optionsRef.current.onMessageReceived?.(newMessage);

          return {
            ...prev,
            messages,
            metrics
          };
        });
        break;
      }

      case 'streaming.node.changed':
      case 'stream_node_update': {
        if (payload.current_node) {
          setExecutionState(prev => {
            if (!prev) return null;
            return {
              ...prev,
              current_node: payload.current_node
            };
          });
        }
        break;
      }

      case 'streaming.execution.paused':
      case 'stream_paused': {
        setExecutionState(prev => {
          if (!prev) return null;
          return { ...prev, status: 'paused' };
        });
        setIsStreaming(false);

        addNotification({
          type: 'info',
          title: 'Streaming Paused',
          message: 'Execution streaming paused'
        });
        break;
      }

      case 'streaming.execution.resumed':
      case 'stream_resumed': {
        setExecutionState(prev => {
          if (!prev) return null;
          return { ...prev, status: 'streaming' };
        });
        setIsStreaming(true);

        addNotification({
          type: 'info',
          title: 'Streaming Resumed',
          message: 'Execution streaming resumed'
        });
        break;
      }

      case 'streaming.execution.completed':
      case 'stream_completed': {
        setExecutionState(prev => {
          if (!prev) return null;
          return {
            ...prev,
            status: 'completed',
            completed_at: new Date().toISOString()
          };
        });
        setIsStreaming(false);

        if (payload.run_id) {
          optionsRef.current.onStreamCompleted?.(payload.run_id);
        }

        addNotification({
          type: 'success',
          title: 'Streaming Completed',
          message: 'Execution streaming completed successfully'
        });
        break;
      }

      case 'streaming.execution.failed':
      case 'stream_failed': {
        const errorMessage = payload.error || 'Streaming execution failed';

        setExecutionState(prev => {
          if (!prev) return null;
          return {
            ...prev,
            status: 'failed',
            completed_at: new Date().toISOString()
          };
        });
        setIsStreaming(false);
        setError(errorMessage);

        if (payload.run_id) {
          optionsRef.current.onStreamFailed?.(payload.run_id, errorMessage);
        }

        addNotification({
          type: 'error',
          title: 'Streaming Failed',
          message: errorMessage
        });
        break;
      }

      case 'streaming.execution.cancelled':
      case 'stream_cancelled': {
        setExecutionState(prev => {
          if (!prev) return null;
          return {
            ...prev,
            status: 'cancelled',
            completed_at: new Date().toISOString()
          };
        });
        setIsStreaming(false);

        addNotification({
          type: 'warning',
          title: 'Streaming Cancelled',
          message: 'Execution streaming cancelled'
        });
        break;
      }

      default:
        if (process.env.NODE_ENV === 'development') {
          console.warn('[StreamingExecution] Unknown event:', event);
        }
    }
  }, [addNotification]);

  /**
   * Subscribe to streaming execution WebSocket updates
   */
  useEffect(() => {
    if (executionState?.run_id && isConnected) {
      const unsubscribe = subscribe({
        channel: 'AiOrchestrationChannel',
        params: { type: 'workflow_run', id: executionState.run_id },
        onMessage: handleStreamingMessage,
        onError: (wsError) => {
          // Log error (always visible for debugging production issues)
          console.error('[StreamingExecution] WebSocket error:', wsError);

          // Set error state
          const errorMessage = typeof wsError === 'string' ? wsError : 'Connection error occurred';
          setError(errorMessage);
          setIsStreaming(false);

          // Notify user of connection failure
          addNotification({
            type: 'error',
            title: 'Connection Error',
            message: 'Workflow streaming connection lost. Please try again.'
          });
        }
      });

      return () => {
        unsubscribe();
      };
    }
  }, [executionState?.run_id, isConnected, subscribe, handleStreamingMessage]);

  /**
   * Start streaming execution
   */
  const startStreaming = useCallback(async (
    workflowId: string,
    inputVariables?: Record<string, any>
  ): Promise<string> => {
    try {
      setError(null);
      setIsStreaming(true);
      setLastWorkflowId(workflowId);
      setLastInputVariables(inputVariables);

      const response = await workflowsApi.executeWorkflow(workflowId, {
        input_variables: inputVariables,
        execution_options: {
          streaming: true,
          real_time_updates: true
        }
      });

      const runId = response.run_id;

      if (!runId) {
        throw new Error('No run ID returned from server');
      }

      return runId;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to start streaming execution';
      setError(errorMessage);
      setIsStreaming(false);

      addNotification({
        type: 'error',
        title: 'Streaming Start Failed',
        message: errorMessage
      });

      throw error;
    }
  }, [addNotification]);

  /**
   * Pause streaming execution
   */
  const pauseStreaming = useCallback(async (): Promise<void> => {
    if (!executionState?.run_id || !executionState?.workflow_id) return;

    try {
      await workflowsApi.pauseRun(executionState.workflow_id, executionState.run_id);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to pause streaming';
      setError(errorMessage);

      addNotification({
        type: 'error',
        title: 'Pause Failed',
        message: errorMessage
      });

      throw error;
    }
  }, [executionState, addNotification]);

  /**
   * Resume streaming execution
   */
  const resumeStreaming = useCallback(async (): Promise<void> => {
    if (!executionState?.run_id || !executionState?.workflow_id) return;

    try {
      await workflowsApi.resumeRun(executionState.workflow_id, executionState.run_id);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to resume streaming';
      setError(errorMessage);

      addNotification({
        type: 'error',
        title: 'Resume Failed',
        message: errorMessage
      });

      throw error;
    }
  }, [executionState, addNotification]);

  /**
   * Stop streaming execution
   */
  const stopStreaming = useCallback(async (): Promise<void> => {
    if (!executionState?.run_id || !executionState?.workflow_id) return;

    try {
      await workflowsApi.cancelRun(executionState.workflow_id, executionState.run_id);
      setIsStreaming(false);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to stop streaming';
      setError(errorMessage);

      addNotification({
        type: 'error',
        title: 'Stop Failed',
        message: errorMessage
      });

      throw error;
    }
  }, [executionState, addNotification]);

  /**
   * Retry streaming execution with same parameters
   */
  const retryStreaming = useCallback(async (): Promise<void> => {
    if (!lastWorkflowId) {
      throw new Error('No previous execution to retry');
    }

    await startStreaming(lastWorkflowId, lastInputVariables);
  }, [lastWorkflowId, lastInputVariables, startStreaming]);

  /**
   * Clear streaming state
   */
  const clearStream = useCallback(() => {
    setExecutionState(null);
    setIsStreaming(false);
    setError(null);
    messageCountRef.current = 0;
  }, []);

  return {
    // State
    executionState,
    isStreaming,
    error,
    isConnected,

    // Actions
    startStreaming,
    pauseStreaming,
    resumeStreaming,
    stopStreaming,
    retryStreaming,
    clearStream
  };
};
