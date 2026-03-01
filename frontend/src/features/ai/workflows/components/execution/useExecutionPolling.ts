import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { workflowsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import {
  AiWorkflow,
  AiWorkflowRun,
  AiWorkflowNodeExecution,
  AiWorkflowNode,
  AiWorkflowEdge,
  WorkflowRunStatus
} from '@/shared/types/workflow';
import { sortNodesInExecutionOrder } from '@/shared/utils/workflow';
import { getErrorMessage } from '@/shared/utils/typeGuards';

interface UseExecutionPollingOptions {
  run: AiWorkflowRun;
  workflowId: string;
  isExpanded: boolean;
  onRegisterReloadCallback?: (runId: string, callback: () => void) => () => void;
}

interface UseExecutionPollingResult {
  nodeExecutions: AiWorkflowNodeExecution[];
  mergedNodes: AiWorkflowNodeExecution[];
  loading: boolean;
  error: string | null;
  runStatus: WorkflowRunStatus;
  currentRun: AiWorkflowRun;
  setCurrentRun: React.Dispatch<React.SetStateAction<AiWorkflowRun>>;
  lastUpdateReceived: number | null;
  liveNodeDurations: Record<string, number>;
  loadExecutionDetails: () => Promise<void>;
  isConnected: boolean;
}

export function useExecutionPolling({
  run,
  workflowId,
  isExpanded,
  onRegisterReloadCallback
}: UseExecutionPollingOptions): UseExecutionPollingResult {
  const { addNotification } = useNotifications();
  const { isConnected, subscribe } = useWebSocket();

  // Core state
  const [nodeExecutions, setNodeExecutions] = useState<AiWorkflowNodeExecution[]>([]);
  const [workflowNodes, setWorkflowNodes] = useState<AiWorkflowNode[]>([]);
  const [workflowEdges, setWorkflowEdges] = useState<AiWorkflowEdge[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [runStatus, setRunStatus] = useState(run.status);
  const [currentRun, setCurrentRun] = useState(run);
  const [lastUpdateReceived, setLastUpdateReceived] = useState<number | null>(null);
  const [liveNodeDurations, setLiveNodeDurations] = useState<Record<string, number>>({});

  // Refs for state tracking
  const runStatusRef = useRef(runStatus);
  runStatusRef.current = runStatus;
  const hasReceivedWebSocketStatusRef = useRef(false);
  const expansionProcessedRef = useRef<string | null>(null);
  const loadingTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const isLoadingRef = useRef<boolean>(false);

  // Sync run status from props
  useEffect(() => {
    const finalStatuses = ['completed', 'failed', 'cancelled'];
    const isPropFinalStatus = finalStatuses.includes(run.status);
    const shouldSyncFromProp = !hasReceivedWebSocketStatusRef.current || isPropFinalStatus;

    if (run.status !== runStatus && shouldSyncFromProp) {
      setRunStatus(run.status);
      if (isPropFinalStatus) {
        hasReceivedWebSocketStatusRef.current = false;
      }
    }
  }, [run.status, runStatus]);

  useEffect(() => {
    setCurrentRun(run);
  }, [run]);

  // Load execution details
  const loadExecutionDetails = useCallback(async () => {
    if (loading || isLoadingRef.current) return;
    isLoadingRef.current = true;

    const runId = run.run_id || run.id;

    try {
      if (nodeExecutions.length === 0) {
        setLoading(true);
      }
      setError(null);

      if (!runId) {
        throw new Error('No run ID available');
      }

      const loadPromises = [
        workflowsApi.getWorkflow(workflowId),
        workflowsApi.getWorkflowRunDetails(runId, workflowId)
      ];

      const timeoutPromise = new Promise((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), 30000);
      });

      const [workflowResponse, executionResponse] = await Promise.allSettled([
        Promise.race([loadPromises[0], timeoutPromise]),
        Promise.race([loadPromises[1], timeoutPromise])
      ]);

      if (workflowResponse.status === 'fulfilled') {
        const workflow = workflowResponse.value as AiWorkflow;
        if (workflow?.nodes) setWorkflowNodes(workflow.nodes);
        if (workflow?.edges) setWorkflowEdges(workflow.edges);
      }

      if (executionResponse.status === 'fulfilled') {
        type RunDetailsResponse = { workflow_run: AiWorkflowRun; node_executions: AiWorkflowNodeExecution[] };
        const runDetails = executionResponse.value as RunDetailsResponse;
        const nodeExecs = runDetails.node_executions || [];
        setNodeExecutions(nodeExecs);
      } else if (executionResponse.status === 'rejected') {
        const executionError = executionResponse.reason;
        if (executionError?.response?.status !== 404) {
          throw executionError;
        }
        setNodeExecutions([]);
      }
    } catch (err) {
      const errorMessage = getErrorMessage(err);
      setError(errorMessage);

      const is404 = typeof err === 'object' && err !== null && 'response' in err &&
                    typeof (err as { response?: { status?: number } }).response === 'object' &&
                    (err as { response?: { status?: number } }).response?.status === 404;

      if (!is404) {
        addNotification({ type: 'error', title: 'Error', message: errorMessage });
      }
    } finally {
      isLoadingRef.current = false;
      setTimeout(() => setLoading(false), 50);
    }
  }, [run.run_id, run.id, workflowId, addNotification, loading, nodeExecutions.length]);

  // Load on expansion
  useEffect(() => {
    if (isExpanded && run.id) {
      const expansionKey = `${run.id}-${isExpanded}`;

      if (loadingTimeoutRef.current) {
        clearTimeout(loadingTimeoutRef.current);
        loadingTimeoutRef.current = null;
      }

      if (expansionProcessedRef.current !== expansionKey && !isLoadingRef.current) {
        expansionProcessedRef.current = expansionKey;
        loadingTimeoutRef.current = setTimeout(() => {
          loadingTimeoutRef.current = null;
          if (!isLoadingRef.current) {
            loadExecutionDetails();
          }
        }, 100);
      }
    } else if (!isExpanded) {
      if (loadingTimeoutRef.current) {
        clearTimeout(loadingTimeoutRef.current);
        loadingTimeoutRef.current = null;
      }
      expansionProcessedRef.current = null;
    }
  }, [isExpanded, run.id, loadExecutionDetails]);

  // Cleanup
  useEffect(() => {
    return () => {
      if (loadingTimeoutRef.current) {
        clearTimeout(loadingTimeoutRef.current);
      }
    };
  }, []);

  // Live duration clock
  useEffect(() => {
    const runningNodes = nodeExecutions.filter(n => n.status === 'running');

    if (runningNodes.length === 0) {
      setLiveNodeDurations({});
      return;
    }

    const interval = setInterval(() => {
      const now = Date.now();
      const newDurations: Record<string, number> = {};

      runningNodes.forEach(node => {
        if (node.started_at) {
          const startTime = new Date(node.started_at).getTime();
          newDurations[node.execution_id] = now - startTime;
        }
      });

      setLiveNodeDurations(newDurations);
    }, 1000);

    // Initial update
    const now = Date.now();
    const initialDurations: Record<string, number> = {};
    runningNodes.forEach(node => {
      if (node.started_at) {
        initialDurations[node.execution_id] = now - new Date(node.started_at).getTime();
      }
    });
    setLiveNodeDurations(initialDurations);

    return () => clearInterval(interval);
  }, [nodeExecutions]);

  // Register reload callback
  useEffect(() => {
    if (!onRegisterReloadCallback || !run.id) return;

    const runId = run.id;
    const handleReload = () => {
      if (isExpanded && expansionProcessedRef.current === `${runId}-${isExpanded}` && !isLoadingRef.current) {
        if (loadingTimeoutRef.current) {
          clearTimeout(loadingTimeoutRef.current);
          loadingTimeoutRef.current = null;
        }
        loadExecutionDetails();
      }
    };

    return onRegisterReloadCallback(runId, handleReload);
  }, [onRegisterReloadCallback, run.id, isExpanded, loadExecutionDetails]);

  // Recalculate progress
  useEffect(() => {
    if (nodeExecutions.length === 0) return;

    const realExecutions = nodeExecutions.filter(n =>
      n.execution_id && !n.execution_id.startsWith('placeholder')
    );

    if (realExecutions.length === 0) return;

    const completedCount = realExecutions.filter(n =>
      n.status === 'completed' || n.status === 'skipped'
    ).length;

    const failedCount = realExecutions.filter(n => n.status === 'failed').length;

    setCurrentRun(prev => {
      if (prev.completed_nodes === completedCount && prev.failed_nodes === failedCount) {
        return prev;
      }
      return { ...prev, completed_nodes: completedCount, failed_nodes: failedCount };
    });
  }, [nodeExecutions]);

  // Merge workflow nodes with execution status
  const mergedNodes = useMemo(() => {
    const safeNodeExecutions = Array.isArray(nodeExecutions) ? nodeExecutions : [];

    if (workflowNodes.length === 0) {
      return [...safeNodeExecutions].sort((a, b) => {
        if (!a.started_at && !b.started_at) return 0;
        if (!a.started_at) return 1;
        if (!b.started_at) return -1;
        return new Date(a.started_at).getTime() - new Date(b.started_at).getTime();
      });
    }

    const executionMap = new Map<string, AiWorkflowNodeExecution>();
    safeNodeExecutions.forEach(execution => {
      const nodeId = execution.node?.node_id || (execution as { node_id?: string }).node_id;
      if (nodeId) executionMap.set(nodeId, execution);
    });

    const sortedNodes = sortNodesInExecutionOrder(workflowNodes, workflowEdges);

    const merged = sortedNodes.map(node => {
      const execution = executionMap.get(node.node_id);

      if (execution) {
        return {
          ...execution,
          node: { node_id: node.node_id, node_type: node.node_type, name: node.name }
        };
      } else {
        return {
          execution_id: `placeholder-${node.node_id}`,
          status: 'pending' as const,
          started_at: undefined,
          completed_at: undefined,
          execution_time_ms: undefined,
          duration_ms: undefined,
          cost: undefined,
          cost_usd: undefined,
          retry_count: 0,
          node: { node_id: node.node_id, node_type: node.node_type, name: node.name },
          input_data: undefined,
          output_data: undefined,
          error_details: undefined,
          metadata: undefined
        } as AiWorkflowNodeExecution;
      }
    });

    return merged.sort((a, b) => {
      if (a.started_at && b.started_at) {
        return new Date(a.started_at).getTime() - new Date(b.started_at).getTime();
      }
      if (a.started_at && !b.started_at) return -1;
      if (!a.started_at && b.started_at) return 1;
      return 0;
    });
  }, [workflowNodes, workflowEdges, nodeExecutions]);

  const runId = useMemo(() => run.run_id || run.id, [run.run_id, run.id]);

  // WebSocket subscription
  useEffect(() => {
    if (!isConnected || !runId) return;

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'workflow_run', id: runId },

      onMessage: (data: unknown) => {
        const message = data as Record<string, unknown>;
        const payload = message.payload as Record<string, unknown> | undefined;
        const eventType = message.event || message.type;

        if (eventType === 'node.execution.updated') {
          const nodeExecution = (payload?.node_execution || message.node_execution) as (AiWorkflowNodeExecution & Record<string, unknown>) | undefined;
          if (!nodeExecution) return;

          setLastUpdateReceived(Date.now());

          setNodeExecutions(prev => {
            const existingIndex = prev.findIndex(n =>
              n.execution_id === nodeExecution.execution_id ||
              n.id === nodeExecution.execution_id ||
              n.execution_id === nodeExecution.id ||
              n.id === nodeExecution.id
            );

            if (existingIndex !== -1) {
              const existing = prev[existingIndex];
              const statusChanged = existing.status !== nodeExecution.status;
              const timingChanged = existing.completed_at !== nodeExecution.completed_at ||
                                  existing.execution_time_ms !== nodeExecution.execution_time_ms;
              const outputChanged = JSON.stringify(existing.output_data) !== JSON.stringify(nodeExecution.output_data);

              const isBackwardsTransition =
                (existing.status === 'completed' || existing.status === 'failed') &&
                (nodeExecution.status === 'running' || nodeExecution.status === 'pending');

              if (isBackwardsTransition || (!statusChanged && !timingChanged && !outputChanged)) {
                return prev;
              }

              const updated = [...prev];
              updated[existingIndex] = {
                ...existing,
                ...nodeExecution,
                node: existing.node || nodeExecution.node || {
                  node_id: String(nodeExecution.node_id || ''),
                  name: String(nodeExecution.node_name || ''),
                  node_type: String(nodeExecution.node_type || '')
                }
              } as AiWorkflowNodeExecution;
              return updated;
            } else {
              const newExecution = {
                ...nodeExecution,
                node: nodeExecution.node || {
                  node_id: String(nodeExecution.node_id || ''),
                  name: String(nodeExecution.node_name || ''),
                  node_type: String(nodeExecution.node_type || '')
                }
              } as AiWorkflowNodeExecution;
              return [...prev, newExecution];
            }
          });
        }

        if (eventType === 'workflow.execution.completed' || eventType === 'workflow.execution.failed' ||
            eventType === 'workflow.status.changed' || eventType === 'workflow.run.status.changed' ||
            eventType === 'workflow.run.progress.changed') {
          const workflowRun = (payload?.workflow_run || message.workflow_run) as Record<string, unknown> | undefined;
          if (workflowRun?.status && workflowRun.status !== runStatus) {
            hasReceivedWebSocketStatusRef.current = true;
            setRunStatus(workflowRun.status as WorkflowRunStatus);

            if (workflowRun) {
              setCurrentRun(prev => ({
                ...prev,
                status: workflowRun.status as WorkflowRunStatus,
                completed_at: (workflowRun.completed_at as string) || prev.completed_at,
                duration_seconds: (workflowRun.duration_seconds as number) ?? prev.duration_seconds,
                cost_usd: (workflowRun.cost_usd as number) ?? prev.cost_usd,
                completed_nodes: (workflowRun.completed_nodes as number) ?? prev.completed_nodes,
                failed_nodes: (workflowRun.failed_nodes as number) ?? prev.failed_nodes,
                total_nodes: (workflowRun.total_nodes as number) || prev.total_nodes,
                output: workflowRun.output || prev.output,
                output_variables: (workflowRun.output_variables as Record<string, unknown>) || prev.output_variables
              }));
            }
          }
        }

        if (eventType === 'workflow.execution.started') {
          const workflowRun = (payload?.workflow_run || message.workflow_run) as Record<string, unknown> | undefined;
          if (workflowRun?.status && workflowRun.status !== runStatus) {
            hasReceivedWebSocketStatusRef.current = true;
            setRunStatus(workflowRun.status as WorkflowRunStatus);
          }
          if (workflowRun) {
            setCurrentRun(prev => ({
              ...prev,
              status: (workflowRun.status as WorkflowRunStatus) || prev.status,
              completed_at: (workflowRun.completed_at as string) || prev.completed_at,
              duration_seconds: (workflowRun.duration_seconds as number) || prev.duration_seconds,
              cost_usd: (workflowRun.cost_usd as number) || prev.cost_usd,
              completed_nodes: (workflowRun.completed_nodes as number) ?? prev.completed_nodes,
              failed_nodes: (workflowRun.failed_nodes as number) ?? prev.failed_nodes,
              total_nodes: (workflowRun.total_nodes as number) || prev.total_nodes,
              output: workflowRun.output || prev.output,
              output_variables: (workflowRun.output_variables as Record<string, unknown>) || prev.output_variables
            }));
          } else if (message.status) {
            hasReceivedWebSocketStatusRef.current = true;
            setRunStatus(message.status as WorkflowRunStatus);
          }
        }
      }
    });

    return () => unsubscribe();
  }, [isConnected, runId, subscribe, runStatus]);

  return {
    nodeExecutions,
    mergedNodes,
    loading,
    error,
    runStatus,
    currentRun,
    setCurrentRun,
    lastUpdateReceived,
    liveNodeDurations,
    loadExecutionDetails,
    isConnected
  };
}
