import { useState, useEffect, useCallback, useRef } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { workflowsApi } from '@/shared/services/ai';
import type {
  BatchExecutionStatus,
  BatchWorkflowStatus
} from '../components/batch/BatchProgressPanel';
import type { BatchExecutionConfig } from '../components/batch/BatchExecutionModal';

interface BatchExecutionMessage {
  event: string;
  payload: {
    batch_execution?: BatchExecutionStatus;
    batch_id?: string;
    workflow_id?: string;
    workflow_status?: BatchWorkflowStatus;
    error?: string;
    message?: string;
  };
}

interface UseBatchExecutionOptions {
  onBatchStarted?: (batchId: string) => void;
  onBatchCompleted?: (batchId: string, status: BatchExecutionStatus) => void;
  onBatchFailed?: (batchId: string, error: string) => void;
  onWorkflowCompleted?: (workflowId: string, status: BatchWorkflowStatus) => void;
}

interface UseBatchExecutionReturn {
  // State
  batchStatus: BatchExecutionStatus | null;
  isExecuting: boolean;
  error: string | null;
  isConnected: boolean;

  // Actions
  startBatch: (config: BatchExecutionConfig) => Promise<string>;
  pauseBatch: (batchId: string) => Promise<void>;
  resumeBatch: (batchId: string) => Promise<void>;
  cancelBatch: (batchId: string) => Promise<void>;
  clearBatch: () => void;

  // Queries
  getBatchStatus: (batchId: string) => Promise<BatchExecutionStatus>;
  getBatchResults: (batchId: string) => Promise<BatchWorkflowStatus[]>;
}

/**
 * Custom hook for managing batch workflow execution
 *
 * Provides real-time batch execution tracking via WebSocket and
 * API methods for controlling batch execution lifecycle.
 *
 * @example
 * ```tsx
 * const {
 *   batchStatus,
 *   isExecuting,
 *   startBatch,
 *   pauseBatch,
 *   cancelBatch
 * } = useBatchExecution({
 *   onBatchCompleted: (batchId) => {
 *   }
 * });
 *
 * // Start batch execution
 * const batchId = await startBatch({
 *   workflow_ids: ['wf1', 'wf2', 'wf3'],
 *   concurrency: 3,
 *   execution_mode: 'parallel',
 *   stop_on_error: false
 * });
 * ```
 */
export const useBatchExecution = (
  options: UseBatchExecutionOptions = {}
): UseBatchExecutionReturn => {
  const [batchStatus, setBatchStatus] = useState<BatchExecutionStatus | null>(null);
  const [isExecuting, setIsExecuting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeBatchId, setActiveBatchId] = useState<string | null>(null);

  const { addNotification } = useNotifications();
  const { isConnected, subscribe } = useWebSocket();

  const optionsRef = useRef(options);
  optionsRef.current = options;

  /**
   * Handle batch execution messages from WebSocket
   */
  const handleBatchMessage = useCallback((data: unknown) => {
    const message = data as BatchExecutionMessage;
    const { event, payload } = message;

    switch (event) {
      case 'batch.execution.started':
      case 'batch_started': {
        const batchId = payload.batch_id || payload.batch_execution?.batch_id;
        if (batchId) {
          setIsExecuting(true);
          setError(null);

          if (payload.batch_execution) {
            setBatchStatus(payload.batch_execution);
          }

          optionsRef.current.onBatchStarted?.(batchId);

          addNotification({
            type: 'info',
            title: 'Batch Started',
            message: `Batch execution ${batchId.slice(0, 8)} started`
          });
        }
        break;
      }

      case 'batch.execution.progress':
      case 'batch_progress': {
        if (payload.batch_execution) {
          setBatchStatus(payload.batch_execution);
        }
        break;
      }

      case 'batch.workflow.completed':
      case 'batch_item_completed': {
        if (payload.batch_execution) {
          setBatchStatus(payload.batch_execution);
        }

        if (payload.workflow_id && payload.workflow_status) {
          optionsRef.current.onWorkflowCompleted?.(
            payload.workflow_id,
            payload.workflow_status
          );
        }
        break;
      }

      case 'batch.execution.completed':
      case 'batch_completed': {
        const batchId = payload.batch_id || payload.batch_execution?.batch_id;

        if (payload.batch_execution) {
          setBatchStatus(payload.batch_execution);
        }

        setIsExecuting(false);

        if (batchId) {
          optionsRef.current.onBatchCompleted?.(batchId, payload.batch_execution!);

          addNotification({
            type: 'success',
            title: 'Batch Completed',
            message: `Batch execution completed successfully`
          });
        }
        break;
      }

      case 'batch.execution.failed':
      case 'batch_failed': {
        const batchId = payload.batch_id || payload.batch_execution?.batch_id;
        const errorMessage = payload.error || payload.message || 'Batch execution failed';

        if (payload.batch_execution) {
          setBatchStatus(payload.batch_execution);
        }

        setIsExecuting(false);
        setError(errorMessage);

        if (batchId) {
          optionsRef.current.onBatchFailed?.(batchId, errorMessage);

          addNotification({
            type: 'error',
            title: 'Batch Failed',
            message: errorMessage
          });
        }
        break;
      }

      case 'batch.execution.paused':
      case 'batch_paused': {
        if (payload.batch_execution) {
          setBatchStatus(payload.batch_execution);
        }

        addNotification({
          type: 'info',
          title: 'Batch Paused',
          message: 'Batch execution paused'
        });
        break;
      }

      case 'batch.execution.resumed':
      case 'batch_resumed': {
        if (payload.batch_execution) {
          setBatchStatus(payload.batch_execution);
        }

        addNotification({
          type: 'info',
          title: 'Batch Resumed',
          message: 'Batch execution resumed'
        });
        break;
      }

      case 'batch.execution.cancelled':
      case 'batch_cancelled': {
        if (payload.batch_execution) {
          setBatchStatus(payload.batch_execution);
        }

        setIsExecuting(false);

        addNotification({
          type: 'warning',
          title: 'Batch Cancelled',
          message: 'Batch execution cancelled'
        });
        break;
      }

      default:
        if (process.env.NODE_ENV === 'development') {
          console.warn('[BatchExecution] Unknown event:', event);
        }
    }
  }, [addNotification]);

  /**
   * Subscribe to batch execution WebSocket updates
   */
  useEffect(() => {
    if (activeBatchId && isConnected) {
      const unsubscribe = subscribe({
        channel: 'AiOrchestrationChannel',
        params: { type: 'batch_execution', id: activeBatchId },
        onMessage: handleBatchMessage,
        onError: (error) => {
          if (process.env.NODE_ENV === 'development') {
            console.error('[BatchExecution] WebSocket error:', error);
          }
          setError(error);
        }
      });

      return () => {
        unsubscribe();
      };
    }
  }, [activeBatchId, isConnected, subscribe, handleBatchMessage]);

  /**
   * Start batch execution
   */
  const startBatch = useCallback(async (config: BatchExecutionConfig): Promise<string> => {
    try {
      setError(null);
      setIsExecuting(true);

      const response = await workflowsApi.executeBatch(config);
      const batchId = response.batch_id;

      if (!batchId) {
        throw new Error('No batch ID returned from server');
      }

      setActiveBatchId(batchId);

      return batchId;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to start batch execution';
      setError(errorMessage);
      setIsExecuting(false);

      addNotification({
        type: 'error',
        title: 'Batch Start Failed',
        message: errorMessage
      });

      throw error;
    }
  }, [addNotification]);

  /**
   * Pause batch execution
   */
  const pauseBatch = useCallback(async (batchId: string): Promise<void> => {
    try {
      await workflowsApi.pauseBatch(batchId);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to pause batch';
      setError(errorMessage);

      addNotification({
        type: 'error',
        title: 'Pause Failed',
        message: errorMessage
      });

      throw error;
    }
  }, [addNotification]);

  /**
   * Resume batch execution
   */
  const resumeBatch = useCallback(async (batchId: string): Promise<void> => {
    try {
      await workflowsApi.resumeBatch(batchId);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to resume batch';
      setError(errorMessage);

      addNotification({
        type: 'error',
        title: 'Resume Failed',
        message: errorMessage
      });

      throw error;
    }
  }, [addNotification]);

  /**
   * Cancel batch execution
   */
  const cancelBatch = useCallback(async (batchId: string): Promise<void> => {
    try {
      await workflowsApi.cancelBatch(batchId);
      setIsExecuting(false);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to cancel batch';
      setError(errorMessage);

      addNotification({
        type: 'error',
        title: 'Cancel Failed',
        message: errorMessage
      });

      throw error;
    }
  }, [addNotification]);

  /**
   * Get current batch status
   */
  const getBatchStatus = useCallback(async (batchId: string): Promise<BatchExecutionStatus> => {
    try {
      const response = await workflowsApi.getBatchStatus(batchId);
      const status = response.batch_execution;

      if (status) {
        setBatchStatus(status);
      }

      return status;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to get batch status';
      setError(errorMessage);
      throw error;
    }
  }, []);

  /**
   * Get batch results
   */
  const getBatchResults = useCallback(async (batchId: string): Promise<BatchWorkflowStatus[]> => {
    try {
      const response = await workflowsApi.getBatchResults(batchId);
      return response.workflows || [];
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to get batch results';
      setError(errorMessage);
      throw error;
    }
  }, []);

  /**
   * Clear batch state
   */
  const clearBatch = useCallback(() => {
    setBatchStatus(null);
    setIsExecuting(false);
    setError(null);
    setActiveBatchId(null);
  }, []);

  return {
    // State
    batchStatus,
    isExecuting,
    error,
    isConnected,

    // Actions
    startBatch,
    pauseBatch,
    resumeBatch,
    cancelBatch,
    clearBatch,

    // Queries
    getBatchStatus,
    getBatchResults
  };
};
