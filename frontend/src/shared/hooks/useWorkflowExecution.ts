import { useState, useEffect, useCallback } from 'react';
import { useWebSocket } from './useWebSocket';
import { type NodeExecutionState } from '@/shared/components/workflow/ExecutionOverlay';

interface WorkflowExecutionMessage {
  event?: string;  // AiOrchestrationChannel uses 'event' field
  type?: string;   // Legacy support
  payload?: {
    node_execution?: any;
    workflow_run?: any;
  };
  // Legacy fields
  node_id?: string;
  workflow_run_id?: string;
  status?: string;
  duration?: number;
  error?: string;
  output?: any;
  timestamp?: string;
}

/**
 * Hook for tracking workflow execution state via WebSocket
 * Uses AiOrchestrationChannel for real-time updates
 */
export const useWorkflowExecution = (_workflowId?: string, workflowRunId?: string) => {
  const [executionState, setExecutionState] = useState<Record<string, NodeExecutionState>>({});
  const [isExecuting, setIsExecuting] = useState(false);
  const [executionError, setExecutionError] = useState<string | null>(null);

  // Subscribe to workflow execution channel
  const { isConnected, subscribe } = useWebSocket();

  // Handle execution messages from AiOrchestrationChannel
  const handleExecutionMessage = useCallback((data: unknown) => {
    const message = data as WorkflowExecutionMessage;
    const eventType = message.event || message.type;

    // Handle node execution updates
    // Backend sends 'node.execution.updated' event
    if (eventType === 'node.execution.updated' || eventType === 'workflow.node.execution.updated') {
      const nodeExecution = message.payload?.node_execution;

      if (!nodeExecution) {
        if (process.env.NODE_ENV === 'development') {
          console.warn('[WorkflowExecution] No node_execution in payload');
        }
        return;
      }

      const nodeId = nodeExecution.node?.node_id || nodeExecution.node_id;
      if (!nodeId) {
        if (process.env.NODE_ENV === 'development') {
          console.warn('[WorkflowExecution] No node_id found');
        }
        return;
      }

      // Map status to ExecutionOverlay states
      let overlayStatus: 'running' | 'success' | 'error' = 'running';
      if (nodeExecution.status === 'completed') overlayStatus = 'success';
      else if (nodeExecution.status === 'failed') overlayStatus = 'error';
      else if (nodeExecution.status === 'running') overlayStatus = 'running';

      setExecutionState(prev => ({
        ...prev,
        [nodeId]: {
          nodeId: nodeId,
          status: overlayStatus,
          startTime: nodeExecution.started_at ? new Date(nodeExecution.started_at).getTime() : Date.now(),
          endTime: nodeExecution.completed_at ? new Date(nodeExecution.completed_at).getTime() : undefined,
          duration: nodeExecution.execution_time_ms,
          output: nodeExecution.output_data,
          error: nodeExecution.error_details?.message || nodeExecution.error_details
        }
      }));
    }

    // Handle workflow run events
    // Backend sends:
    // - workflow.run.status.changed (status updates)
    // - workflow.run.progress.changed (node completion updates)
    // - workflow.run.duration.updated (timing updates)
    // - workflow.execution.started/completed/failed (lifecycle events)
    if (eventType?.startsWith('workflow.run.') || eventType?.startsWith('workflow.execution.')) {
      const workflowRun = message.payload?.workflow_run;

      if (!workflowRun) {
        return;
      }

      // Update execution state based on workflow run status
      if (workflowRun.status === 'completed' || workflowRun.status === 'failed' || workflowRun.status === 'cancelled') {
        setIsExecuting(false);
        if (workflowRun.status === 'failed') {
          setExecutionError(workflowRun.error_details?.error_message || 'Workflow execution failed');
        }
      } else if (workflowRun.status === 'running' || workflowRun.status === 'initializing') {
        setIsExecuting(true);
      }
    }
  }, []);

  // Subscribe to execution updates when workflowRunId changes
  useEffect(() => {
    if (workflowRunId && isConnected) {
      // Use AiOrchestrationChannel with proper params
      const unsubscribe = subscribe({
        channel: 'AiOrchestrationChannel',
        params: { type: 'workflow_run', id: workflowRunId },
        onMessage: handleExecutionMessage
      });

      return () => {
        unsubscribe();
      };
    }
  }, [workflowRunId, isConnected, subscribe, handleExecutionMessage]);

  // Clear execution state when starting new run
  const startExecution = useCallback(() => {
    setExecutionState({});
    setIsExecuting(true);
    setExecutionError(null);
  }, []);

  // Reset execution state
  const resetExecution = useCallback(() => {
    setExecutionState({});
    setIsExecuting(false);
    setExecutionError(null);
  }, []);

  return {
    executionState,
    isExecuting,
    executionError,
    startExecution,
    resetExecution,
    isConnected
  };
};
