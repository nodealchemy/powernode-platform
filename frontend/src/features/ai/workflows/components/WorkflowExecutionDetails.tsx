import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { createPortal } from 'react-dom';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkBreaks from 'remark-breaks';
import {
  ChevronRight,
  ChevronDown,
  Clock,
  CheckCircle,
  AlertCircle,
  Activity,
  Terminal,
  FileText,
  Download,
  Copy,
  Eye,
  Code,
  GitBranch,
  DollarSign,
  Timer,
  Loader2,
  Trash2
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { Modal } from '@/shared/components/ui/Modal';
import { workflowsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { AiWorkflow, AiWorkflowRun, AiWorkflowNodeExecution, AiWorkflowNode, AiWorkflowEdge } from '@/shared/types/workflow';
import { sortNodesInExecutionOrder } from '@/shared/utils/workflow';
import { getErrorMessage } from '@/shared/utils/typeGuards';
import {
  formatDuration,
  getFormattedOutput,
  createExportData,
  downloadBlob
} from './execution/executionUtils';
import { EnhancedCopyButton } from './execution/EnhancedCopyButton';
import { NodeExecutionCard } from './execution/NodeExecutionCard';

interface WorkflowExecutionDetailsProps {
  run: AiWorkflowRun;
  workflowId: string;
  isExpanded: boolean;
  onToggle: () => void;
  onDelete?: () => void;
  onRegisterReloadCallback?: (runId: string, callback: () => void) => () => void;
}

export const WorkflowExecutionDetails: React.FC<WorkflowExecutionDetailsProps> = ({
  run,
  workflowId,
  isExpanded,
  onToggle,
  onDelete,
  onRegisterReloadCallback
}) => {
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

  // UI state
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set());
  const [expandedInputs, setExpandedInputs] = useState<Set<string>>(new Set());
  const [expandedOutputs, setExpandedOutputs] = useState<Set<string>>(new Set());
  const [expandedMetadata, setExpandedMetadata] = useState<Set<string>>(new Set());
  const [showFullOutput, setShowFullOutput] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [lastUpdateReceived, setLastUpdateReceived] = useState<number | null>(null);
  const [showDownloadMenu, setShowDownloadMenu] = useState(false);
  const [liveNodeDurations, setLiveNodeDurations] = useState<Record<string, number>>({});
  const [showPreviewModal, setShowPreviewModal] = useState(false);
  const [previewFormat, setPreviewFormat] = useState<'json' | 'markdown' | 'text'>('json');

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
    } catch (error) {
      const errorMessage = getErrorMessage(error);
      setError(errorMessage);

      const is404 = typeof error === 'object' && error !== null && 'response' in error &&
                    typeof (error as { response?: { status?: number } }).response === 'object' &&
                    (error as { response?: { status?: number } }).response?.status === 404;

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

  // Close download menu on click outside
  useEffect(() => {
    const handleClickOutside = () => {
      if (showDownloadMenu) setShowDownloadMenu(false);
    };

    if (showDownloadMenu) {
      document.addEventListener('click', handleClickOutside);
      return () => document.removeEventListener('click', handleClickOutside);
    }
  }, [showDownloadMenu]);

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
       
      onMessage: (data: any) => {
        const eventType = data.event || data.type;

        if (eventType === 'node.execution.updated') {
          const nodeExecution = data.payload?.node_execution || data.node_execution;
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
                node: existing.node || {
                  node_id: nodeExecution.node_id,
                  name: nodeExecution.node_name,
                  node_type: nodeExecution.node_type
                }
              };
              return updated;
            } else {
              const newExecution = {
                ...nodeExecution,
                node: nodeExecution.node || {
                  node_id: nodeExecution.node_id,
                  name: nodeExecution.node_name,
                  node_type: nodeExecution.node_type
                }
              };
              return [...prev, newExecution];
            }
          });
        }

        if (eventType === 'workflow.execution.completed' || eventType === 'workflow.execution.failed' ||
            eventType === 'workflow.status.changed' || eventType === 'workflow.run.status.changed' ||
            eventType === 'workflow.run.progress.changed') {
          const workflowRun = data.payload?.workflow_run || data.workflow_run;
          if (workflowRun?.status && workflowRun.status !== runStatus) {
            hasReceivedWebSocketStatusRef.current = true;
            setRunStatus(workflowRun.status);

            if (workflowRun) {
              setCurrentRun(prev => ({
                ...prev,
                status: workflowRun.status,
                completed_at: workflowRun.completed_at || prev.completed_at,
                duration_seconds: workflowRun.duration_seconds ?? prev.duration_seconds,
                cost_usd: workflowRun.cost_usd ?? prev.cost_usd,
                completed_nodes: workflowRun.completed_nodes ?? prev.completed_nodes,
                failed_nodes: workflowRun.failed_nodes ?? prev.failed_nodes,
                total_nodes: workflowRun.total_nodes || prev.total_nodes,
                output: workflowRun.output || prev.output,
                output_variables: workflowRun.output_variables || prev.output_variables
              }));
            }
          }
        }

        if (eventType === 'workflow.execution.started') {
          const workflowRun = data.payload?.workflow_run || data.workflow_run;
          if (workflowRun?.status && workflowRun.status !== runStatus) {
            hasReceivedWebSocketStatusRef.current = true;
            setRunStatus(workflowRun.status);
          }
          if (workflowRun) {
            setCurrentRun(prev => ({
              ...prev,
              status: workflowRun.status || prev.status,
              completed_at: workflowRun.completed_at || prev.completed_at,
              duration_seconds: workflowRun.duration_seconds || prev.duration_seconds,
              cost_usd: workflowRun.cost_usd || prev.cost_usd,
              completed_nodes: workflowRun.completed_nodes ?? prev.completed_nodes,
              failed_nodes: workflowRun.failed_nodes ?? prev.failed_nodes,
              total_nodes: workflowRun.total_nodes || prev.total_nodes,
              output: workflowRun.output || prev.output,
              output_variables: workflowRun.output_variables || prev.output_variables
            }));
          } else if (data.status) {
            hasReceivedWebSocketStatusRef.current = true;
            setRunStatus(data.status);
          }
        }
      }
    });

    return () => unsubscribe();
  }, [isConnected, runId, subscribe, runStatus]);

  // Toggle functions
  const toggleNodeExpansion = useCallback((executionId: string) => {
    setExpandedNodes(prev => {
      const newSet = new Set(prev);
      if (newSet.has(executionId)) newSet.delete(executionId);
      else newSet.add(executionId);
      return newSet;
    });
  }, []);

  const toggleInputExpansion = useCallback((executionId: string) => {
    setExpandedInputs(prev => {
      const newSet = new Set(prev);
      if (newSet.has(executionId)) newSet.delete(executionId);
      else newSet.add(executionId);
      return newSet;
    });
  }, []);

  const toggleOutputExpansion = useCallback((executionId: string) => {
    setExpandedOutputs(prev => {
      const newSet = new Set(prev);
      if (newSet.has(executionId)) newSet.delete(executionId);
      else newSet.add(executionId);
      return newSet;
    });
  }, []);

  const toggleMetadataExpansion = useCallback((executionId: string) => {
    setExpandedMetadata(prev => {
      const newSet = new Set(prev);
      if (newSet.has(executionId)) newSet.delete(executionId);
      else newSet.add(executionId);
      return newSet;
    });
  }, []);

  const copyToClipboard = useCallback((text: string, format?: string) => {
    navigator.clipboard.writeText(text);
    addNotification({
      type: 'success',
      title: 'Copied',
      message: format ? `${format} copied to clipboard` : 'Content copied to clipboard'
    });
  }, [addNotification]);

  const exportExecution = useCallback(() => {
    const exportData = createExportData(workflowId, currentRun, nodeExecutions);
    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    downloadBlob(blob, `workflow-execution-${currentRun.run_id || currentRun.id}.json`);
    addNotification({ type: 'success', title: 'Exported', message: 'Execution details exported successfully' });
  }, [workflowId, currentRun, nodeExecutions, addNotification]);

  const downloadFromServer = useCallback(async (format: 'json' | 'txt' | 'markdown') => {
    try {
      const rid = currentRun.run_id || currentRun.id;
      if (!rid) throw new Error('Run ID not found');
      await workflowsApi.downloadWorkflowRun(rid, workflowId, format);
      addNotification({ type: 'success', title: 'Downloaded', message: `Workflow output downloaded as ${format.toUpperCase()}` });
    } catch (error) {
      addNotification({ type: 'error', title: 'Download Failed', message: getErrorMessage(error) });
    }
  }, [currentRun.run_id, currentRun.id, workflowId, addNotification]);

  const handleDelete = useCallback(async () => {
    if (runStatus === 'running' || runStatus === 'initializing') {
      addNotification({ type: 'error', title: 'Cannot Delete', message: 'Cannot delete a workflow execution while it is running' });
      return;
    }

    setIsDeleting(true);
    try {
      const rid = run.run_id || run.id;
      if (!rid) throw new Error('Run ID not found');
      await workflowsApi.deleteWorkflowRun(rid, workflowId);
      addNotification({ type: 'success', title: 'Deleted', message: `Workflow run #${rid.slice(-8)} deleted successfully` });
      setShowDeleteConfirm(false);
      if (onDelete) onDelete();
    } catch (error) {
      addNotification({ type: 'error', title: 'Delete Failed', message: getErrorMessage(error) });
    } finally {
      setIsDeleting(false);
    }
  }, [runStatus, run.run_id, run.id, workflowId, addNotification, onDelete]);

  // Handle Enter key in delete confirmation
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Enter' && showDeleteConfirm && !isDeleting) {
        event.preventDefault();
        handleDelete();
      }
    };

    if (showDeleteConfirm) {
      document.addEventListener('keydown', handleKeyDown);
      return () => document.removeEventListener('keydown', handleKeyDown);
    }
  }, [showDeleteConfirm, isDeleting, handleDelete]);

  // Get formatted output for preview
  const getPreviewOutput = useCallback((format: 'json' | 'markdown' | 'text'): string => {
    const output = currentRun.output || currentRun.output_variables || run.output || run.output_variables;
    return getFormattedOutput(output, format);
  }, [currentRun, run]);

  // Render node output
  const renderNodeOutput = (output: unknown) => {
    if (!output || (typeof output === 'object' && output !== null && Object.keys(output).length === 0)) {
      return <span className="text-theme-muted">No output</span>;
    }

    if (typeof output === 'object' && output !== null) {
      const obj = output as Record<string, unknown>;

      if ('error' in obj || 'error_message' in obj) {
        return (
          <div className="relative bg-theme-error/10 border border-theme-error/20 rounded p-3">
            <div className="absolute top-2 right-2">
              <EnhancedCopyButton data={output} onCopy={copyToClipboard} />
            </div>
            <p className="text-sm text-theme-error font-medium mb-1">Error Output:</p>
            <pre className="text-xs overflow-x-auto pr-8">
              <code className="text-theme-error">{JSON.stringify(output, null, 2)}</code>
            </pre>
          </div>
        );
      }

      if ('result' in obj || 'data' in obj || 'response' in obj) {
        const mainContent = obj.result || obj.data || obj.response;
        return (
          <div className="space-y-2">
            {'message' in obj && obj.message ? (
              <div className="text-sm text-theme-primary">
                <span className="font-medium">Message:</span> {String(obj.message)}
              </div>
            ) : null}
            <div className="relative bg-theme-code p-3 rounded border border-theme">
              <div className="absolute top-2 right-2">
                <EnhancedCopyButton data={mainContent} onCopy={copyToClipboard} />
              </div>
              <pre className="text-xs overflow-x-auto pr-8">
                <code className="text-theme-code-text">
                  {typeof mainContent === 'string' ? mainContent : JSON.stringify(mainContent, null, 2)}
                </code>
              </pre>
            </div>
          </div>
        );
      }

      if (Array.isArray(output)) {
        return (
          <div>
            <p className="text-xs text-theme-muted mb-2">
              Array with {output.length} item{output.length !== 1 ? 's' : ''}
            </p>
            <RenderJsonOutput data={output} showFullOutput={showFullOutput} setShowFullOutput={setShowFullOutput} onCopy={copyToClipboard} />
          </div>
        );
      }
    }

    return (
      <div>
        <p className="text-xs text-theme-muted mb-2 flex items-center gap-1">
          <span>Output:</span>
        </p>
        <RenderJsonOutput data={output} showFullOutput={showFullOutput} setShowFullOutput={setShowFullOutput} onCopy={copyToClipboard} />
      </div>
    );
  };

  return (
    <div className="border-l-2 border-theme ml-8">
      {/* Execution Header */}
      <div className="flex items-start justify-between p-4 hover:bg-theme-surface/50 transition-colors">
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <button
              onClick={(e) => { e.stopPropagation(); onToggle(); }}
              className="cursor-pointer hover:bg-theme-surface rounded p-0.5 transition-colors"
              aria-label={isExpanded ? "Collapse execution details" : "Expand execution details"}
            >
              {isExpanded ? (
                <ChevronDown className="h-4 w-4 text-theme-muted transition-transform duration-200" />
              ) : (
                <ChevronRight className="h-4 w-4 text-theme-muted transition-transform duration-200" />
              )}
            </button>
            <h4 className="font-medium text-theme-primary">
              Run #{(currentRun.run_id || currentRun.id)?.slice(-8)}
            </h4>
            <Badge
              variant={
                runStatus === 'completed' ? 'success' :
                runStatus === 'failed' ? 'danger' :
                runStatus === 'cancelled' ? 'secondary' :
                runStatus === 'running' ? 'info' :
                runStatus === 'initializing' ? 'warning' :
                runStatus === 'waiting_approval' ? 'warning' :
                'secondary'
              }
              size="sm"
            >
              {runStatus}
            </Badge>
            {(runStatus === 'running' || runStatus === 'initializing') && (
              <Loader2 className="h-3 w-3 animate-spin text-theme-info" />
            )}
            {isConnected && (runStatus === 'running' || runStatus === 'initializing') && (
              <div className="flex items-center gap-1 text-theme-success text-xs">
                <div className="animate-pulse h-2 w-2 bg-theme-success rounded-full" />
                Live
                {lastUpdateReceived && (
                  <span className="text-theme-muted ml-1">
                    (Updated {new Date(lastUpdateReceived).toLocaleTimeString()})
                  </span>
                )}
              </div>
            )}
          </div>

          <div className="flex items-center gap-4 mt-1 text-sm text-theme-muted">
            <span className="flex items-center gap-1">
              <Clock className="h-3 w-3" />
              {new Date(currentRun.started_at || currentRun.created_at).toLocaleString()}
            </span>
            <span className="flex items-center gap-1">
              <Timer className="h-3 w-3" />
              {formatDuration((currentRun.duration_seconds || 0) * 1000)}
            </span>
            <span className="flex items-center gap-1">
              <GitBranch className="h-3 w-3" />
              Progress: {currentRun.completed_nodes || 0}/{currentRun.total_nodes || 0}
            </span>
            {currentRun.cost_usd && currentRun.cost_usd > 0 && (
              <span className="flex items-center gap-1">
                <DollarSign className="h-3 w-3" />
                ${currentRun.cost_usd.toFixed(4)}
              </span>
            )}
          </div>
        </div>

        <div className="flex items-center gap-2">
          {/* Download Menu */}
          <div className="relative">
            <Button
              size="sm"
              variant="ghost"
              onClick={(e) => { e.stopPropagation(); setShowDownloadMenu(!showDownloadMenu); }}
              className="p-2"
              title="Download workflow output"
            >
              <Download className="h-4 w-4" />
            </Button>
            {showDownloadMenu && (
              <div className="absolute top-full left-0 mt-1 bg-theme-surface border border-theme rounded-md shadow-lg z-50 min-w-[160px]">
                <div className="p-2">
                  <p className="text-xs text-theme-muted mb-2 font-medium">Download Format:</p>
                  <div className="space-y-1">
                    <button onClick={(e) => { e.stopPropagation(); setShowDownloadMenu(false); downloadFromServer('json'); }}
                      className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary">
                      JSON (structured data)
                    </button>
                    <button onClick={(e) => { e.stopPropagation(); setShowDownloadMenu(false); downloadFromServer('txt'); }}
                      className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary">
                      Text (readable format)
                    </button>
                    <button onClick={(e) => { e.stopPropagation(); setShowDownloadMenu(false); downloadFromServer('markdown'); }}
                      className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary">
                      Markdown (formatted)
                    </button>
                    <hr className="my-1 border-theme" />
                    <button onClick={(e) => { e.stopPropagation(); setShowDownloadMenu(false); exportExecution(); }}
                      className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-muted">
                      Export Execution Details
                    </button>
                  </div>
                </div>
              </div>
            )}
          </div>

          <Button
            size="sm"
            variant="ghost"
            onClick={async (e) => {
              e.stopPropagation();
              try {
                const rid = run.run_id || run.id;
                if (rid && workflowId) {
                  const executionResponse = await workflowsApi.getWorkflowRunDetails(rid, workflowId);
                  if (executionResponse.workflow_run) {
                    setCurrentRun(prev => ({
                      ...prev,
                      ...executionResponse.workflow_run,
                      output: executionResponse.workflow_run.output || prev.output,
                      output_variables: executionResponse.workflow_run.output_variables || prev.output_variables
                    }));
                  }
                }
              } catch (_error) {
                // Continue anyway
              }
              setShowPreviewModal(true);
            }}
            className="p-2"
            title="Preview workflow output"
          >
            <Eye className="h-4 w-4" />
          </Button>

          <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); loadExecutionDetails(); }} className="p-2" title="Refresh execution details">
            <Activity className="h-4 w-4" />
          </Button>

          <Button
            size="sm"
            variant="ghost"
            onClick={(e) => {
              e.stopPropagation();
              if (runStatus === 'running' || runStatus === 'initializing') {
                addNotification({ type: 'warning', title: 'Cannot Delete', message: 'Cannot delete a workflow execution while it is running' });
                return;
              }
              setShowDeleteConfirm(true);
            }}
            className={`p-2 ${runStatus === 'running' || runStatus === 'initializing' ? 'text-theme-muted opacity-50 cursor-not-allowed' : 'text-theme-destructive hover:bg-theme-destructive/10'}`}
            title={runStatus === 'running' || runStatus === 'initializing' ? 'Cannot delete while execution is running' : 'Delete execution'}
            disabled={runStatus === 'running' || runStatus === 'initializing'}
          >
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Expanded Execution Details */}
      {isExpanded && (
        <div className="px-4 pb-3 space-y-2 animate-in slide-in-from-top-2 duration-200">
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-theme-interactive-primary" />
            </div>
          ) : error ? (
            <Card>
              <CardContent className="p-4">
                <div className="flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-theme-warning mt-0.5" />
                  <div className="flex-1">
                    <p className="text-sm text-theme-primary font-medium">Unable to load detailed execution logs</p>
                    <p className="text-xs text-theme-muted mt-1">The execution summary is shown above.</p>
                    <Button size="sm" variant="outline" onClick={loadExecutionDetails} className="mt-3">Try Again</Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ) : (
            <>
              {/* Execution Summary */}
              <Card>
                <CardTitle className="text-sm">Execution Summary</CardTitle>
                <CardContent className="space-y-1">
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                    <div>
                      <span className="text-theme-muted">Trigger:</span>
                      <p className="font-medium text-theme-primary capitalize">{run.trigger_type || 'manual'}</p>
                    </div>
                    <div>
                      <span className="text-theme-muted">Started:</span>
                      <p className="font-medium text-theme-primary">{new Date(run.started_at || run.created_at).toLocaleTimeString()}</p>
                    </div>
                    {run.completed_at && (
                      <div>
                        <span className="text-theme-muted">Completed:</span>
                        <p className="font-medium text-theme-primary">{new Date(run.completed_at).toLocaleTimeString()}</p>
                      </div>
                    )}
                    <div>
                      <span className="text-theme-muted">Total Duration:</span>
                      <p className="font-medium text-theme-primary">{formatDuration((currentRun.duration_seconds || 0) * 1000)}</p>
                    </div>
                  </div>

                  {run.input_variables && Object.keys(run.input_variables).length > 0 && (
                    <div className="mt-2 pt-2 border-t border-theme">
                      <p className="text-sm text-theme-muted mb-1">Input Variables:</p>
                      <pre className="text-xs bg-theme-code p-2 rounded border border-theme overflow-x-auto">
                        <code className="text-theme-code-text">{JSON.stringify(run.input_variables, null, 2)}</code>
                      </pre>
                    </div>
                  )}

                  {run.error_details && Object.keys(run.error_details).length > 0 && runStatus === 'failed' && (
                    <div className="mt-2 pt-2 border-t border-theme-error/20">
                      <p className="text-sm text-theme-error font-medium mb-1">Error Details:</p>
                      <div className="bg-theme-error/10 border border-theme-error/20 rounded p-3">
                        <p className="text-sm text-theme-error">{run.error_details.error_message || 'An error occurred during execution'}</p>
                        {run.error_details.stack_trace && (
                          <pre className="text-xs mt-2 overflow-x-auto"><code>{run.error_details.stack_trace}</code></pre>
                        )}
                      </div>
                    </div>
                  )}
                </CardContent>
              </Card>

              {/* Node Execution Timeline */}
              {mergedNodes.length > 0 ? (
                <Card>
                  <CardTitle className="text-sm flex items-center gap-2">
                    <GitBranch className="h-4 w-4" />
                    Node Execution Timeline
                  </CardTitle>
                  <CardContent className="space-y-1">
                    {mergedNodes.map((node, index) => (
                      <NodeExecutionCard
                        key={`${node.execution_id || `fallback-${index}`}-${node.node?.node_id || index}`}
                        node={node}
                        index={index}
                        isLast={index === mergedNodes.length - 1}
                        isExpanded={expandedNodes.has(node.execution_id)}
                        isInputExpanded={expandedInputs.has(node.execution_id)}
                        isOutputExpanded={expandedOutputs.has(node.execution_id)}
                        isMetadataExpanded={expandedMetadata.has(node.execution_id)}
                        liveDuration={liveNodeDurations[node.execution_id]}
                        onToggle={() => toggleNodeExpansion(node.execution_id)}
                        onToggleInput={() => toggleInputExpansion(node.execution_id)}
                        onToggleOutput={() => toggleOutputExpansion(node.execution_id)}
                        onToggleMetadata={() => toggleMetadataExpansion(node.execution_id)}
                        onCopy={copyToClipboard}
                      />
                    ))}
                  </CardContent>
                </Card>
              ) : (
                <Card>
                  <CardTitle className="text-sm flex items-center gap-2">
                    <GitBranch className="h-4 w-4" />
                    Node Execution Timeline
                  </CardTitle>
                  <CardContent>
                    <div className="text-center py-8 text-theme-muted">
                      <Terminal className="h-8 w-8 mx-auto mb-2 opacity-50" />
                      <p className="text-sm">No workflow nodes found.</p>
                      <p className="text-xs mt-2">{loading ? 'Loading workflow structure...' : 'This workflow may not have any defined nodes.'}</p>
                    </div>
                  </CardContent>
                </Card>
              )}

              {/* Final Workflow Output */}
              {(() => {
                const output = run.output || run.output_variables;
                const hasOutput = output && typeof output === 'object' && Object.keys(output).length > 0;
                return hasOutput;
              })() && (
                <Card className="border-theme-success/30 bg-theme-success/5">
                  <div className="flex items-center justify-between">
                    <CardTitle className="text-sm flex items-center gap-2">
                      <CheckCircle className="h-4 w-4 text-theme-success" />
                      Final Workflow Output
                    </CardTitle>
                    <div className="flex items-center gap-2">
                      <Badge variant="success" size="sm">
                        {Object.keys(run.output_variables || run.output || {}).length} variables
                      </Badge>
                      <EnhancedCopyButton data={run.output || run.output_variables} showLabel={false} onCopy={copyToClipboard} />
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => {
                          const output = run.output || run.output_variables;
                          const blob = new Blob([typeof output === 'string' ? output : JSON.stringify(output, null, 2)], { type: 'application/json' });
                          downloadBlob(blob, `workflow-output-${run.run_id || run.id}.json`);
                        }}
                        className="p-1"
                      >
                        <Download className="h-3 w-3" />
                      </Button>
                    </div>
                  </div>
                  <CardContent>
                    {renderNodeOutput(run.output || run.output_variables)}
                  </CardContent>
                </Card>
              )}
            </>
          )}
        </div>
      )}

      {/* Delete Confirmation Modal */}
      {showDeleteConfirm && createPortal(
        <Modal isOpen={showDeleteConfirm} onClose={() => setShowDeleteConfirm(false)} title="Delete Workflow Execution" maxWidth="md" variant="centered">
          <div className="space-y-4">
            <div className="flex items-start gap-3">
              <AlertCircle className="h-5 w-5 text-theme-warning mt-0.5" />
              <div className="flex-1">
                <p className="text-sm text-theme-primary font-medium">Are you sure you want to delete this workflow execution?</p>
                <p className="text-xs text-theme-muted mt-1">This will permanently delete run #{run.run_id?.slice(-8) || run.id?.slice(-8)} and all associated execution logs. This action cannot be undone.</p>
              </div>
            </div>

            <div className="p-3 bg-theme-surface rounded-lg border border-theme">
              <dl className="space-y-1 text-xs">
                <div className="flex justify-between">
                  <dt className="text-theme-muted">Status:</dt>
                  <dd className="text-theme-primary font-medium">{runStatus || 'Unknown'}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-theme-muted">Started:</dt>
                  <dd className="text-theme-primary">{(run.started_at || run.created_at) ? new Date(run.started_at || run.created_at).toLocaleString() : 'Unknown'}</dd>
                </div>
                {currentRun.duration_seconds && (
                  <div className="flex justify-between">
                    <dt className="text-theme-muted">Duration:</dt>
                    <dd className="text-theme-primary">{formatDuration(currentRun.duration_seconds * 1000)}</dd>
                  </div>
                )}
                <div className="flex justify-between">
                  <dt className="text-theme-muted">Nodes Executed:</dt>
                  <dd className="text-theme-primary">{currentRun.completed_nodes || 0}/{currentRun.total_nodes || 0}</dd>
                </div>
              </dl>
            </div>

            <div className="flex justify-end gap-3 pt-2">
              <Button variant="outline" onClick={() => setShowDeleteConfirm(false)} disabled={isDeleting}>Cancel</Button>
              <Button variant="danger" onClick={handleDelete} disabled={isDeleting} title="Press Enter to delete">
                {isDeleting ? (
                  <><Loader2 className="h-4 w-4 animate-spin mr-2" />Deleting...</>
                ) : (
                  <><Trash2 className="h-4 w-4 mr-2" />Delete Execution<span className="ml-2 text-xs opacity-70">(Enter)</span></>
                )}
              </Button>
            </div>
          </div>
        </Modal>,
        document.body
      )}

      {/* Preview Modal */}
      {showPreviewModal && createPortal(
        <Modal isOpen={showPreviewModal} onClose={() => setShowPreviewModal(false)} title="Preview Workflow Output" maxWidth="4xl" variant="centered" disableContentScroll={true}>
          <div className="space-y-4">
            <div className="flex items-center gap-2 pb-3 border-b border-theme">
              <span className="text-sm text-theme-muted font-medium">Format:</span>
              <div className="flex gap-1">
                <Button size="sm" variant={previewFormat === 'json' ? 'primary' : 'outline'} onClick={() => setPreviewFormat('json')} className="px-3 py-1 text-xs">
                  <Code className="h-3 w-3 mr-1" />JSON
                </Button>
                <Button size="sm" variant={previewFormat === 'text' ? 'primary' : 'outline'} onClick={() => setPreviewFormat('text')} className="px-3 py-1 text-xs">
                  <Terminal className="h-3 w-3 mr-1" />Text
                </Button>
                <Button size="sm" variant={previewFormat === 'markdown' ? 'primary' : 'outline'} onClick={() => setPreviewFormat('markdown')} className="px-3 py-1 text-xs">
                  <FileText className="h-3 w-3 mr-1" />Markdown
                </Button>
              </div>
              <div className="flex-1" />
              <Button size="sm" variant="ghost" onClick={() => copyToClipboard(getPreviewOutput(previewFormat), `${previewFormat.toUpperCase()} content`)} className="px-3 py-1 text-xs">
                <Copy className="h-3 w-3 mr-1" />Copy
              </Button>
            </div>

            <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden" style={{ height: '60vh', minHeight: '400px' }}>
              {previewFormat === 'json' && (
                <div className="relative h-full flex flex-col">
                  <div className="bg-theme-surface/95 backdrop-blur-sm border-b border-theme px-4 py-2 text-xs text-theme-muted flex-shrink-0">
                    <span className="flex items-center gap-2"><Code className="h-3 w-3" />Complete JSON output - scroll to view all content</span>
                  </div>
                  <div className="flex-1 overflow-auto custom-scrollbar">
                    <pre className="p-4 text-sm"><code className="text-theme-code-text">{getPreviewOutput('json')}</code></pre>
                  </div>
                </div>
              )}

              {previewFormat === 'text' && (
                <div className="relative h-full flex flex-col">
                  <div className="bg-theme-surface/95 backdrop-blur-sm border-b border-theme px-4 py-2 text-xs text-theme-muted flex-shrink-0">
                    <span className="flex items-center gap-2"><Terminal className="h-3 w-3" />Complete text output - scroll to view all content</span>
                  </div>
                  <div className="flex-1 overflow-auto custom-scrollbar">
                    <pre className="p-4 text-sm whitespace-pre-wrap"><code className="text-theme-primary">{getPreviewOutput('text')}</code></pre>
                  </div>
                </div>
              )}

              {previewFormat === 'markdown' && (
                <div className="relative h-full flex flex-col">
                  <div className="bg-theme-surface/95 backdrop-blur-sm border-b border-theme px-4 py-2 text-xs text-theme-muted flex-shrink-0">
                    <span className="flex items-center gap-2"><FileText className="h-3 w-3" />Complete markdown document - scroll to view all content</span>
                  </div>
                  <div className="flex-1 overflow-auto custom-scrollbar p-6">
                    <div className="markdown-content text-theme-primary">
                      <ReactMarkdown
                        remarkPlugins={[remarkGfm, remarkBreaks]}
                        components={{
                          h1: ({ children, ...props }) => <h1 className="text-3xl font-bold text-theme-primary mt-6 mb-4 first:mt-0" {...props}>{children}</h1>,
                          h2: ({ children, ...props }) => <h2 className="text-2xl font-bold text-theme-primary mt-5 mb-3" {...props}>{children}</h2>,
                          h3: ({ children, ...props }) => <h3 className="text-xl font-bold text-theme-primary mt-4 mb-2" {...props}>{children}</h3>,
                          p: ({ children, ...props }) => <p className="text-theme-primary mb-4 leading-7" {...props}>{children}</p>,
                          ul: ({ children, ...props }) => <ul className="list-disc list-inside mb-4 space-y-2 text-theme-primary" {...props}>{children}</ul>,
                          ol: ({ children, ...props }) => <ol className="list-decimal list-inside mb-4 space-y-2 text-theme-primary" {...props}>{children}</ol>,
                          li: ({ children, ...props }) => <li className="text-theme-primary ml-4" {...props}>{children}</li>,
                          strong: ({ children, ...props }) => <strong className="font-bold text-theme-primary" {...props}>{children}</strong>,
                          em: ({ children, ...props }) => <em className="italic text-theme-primary" {...props}>{children}</em>,
                          a: ({ children, ...props }) => <a className="text-theme-interactive-primary hover:underline" target="_blank" rel="noopener noreferrer" {...props}>{children}</a>,
                          code: ({ node, ...props }) => {
                            const isInline = node && 'properties' in node && node.properties && 'inline' in node.properties;
                            return isInline ? (
                              <code className="px-1.5 py-0.5 bg-theme-code text-theme-code-text rounded text-sm font-mono" {...props} />
                            ) : (
                              <code className="block bg-theme-code text-theme-code-text rounded p-4 overflow-x-auto font-mono text-sm" {...props} />
                            );
                          },
                          pre: ({ children, ...props }) => <pre className="bg-theme-code rounded p-4 mb-4 overflow-x-auto" {...props}>{children}</pre>,
                          blockquote: ({ children, ...props }) => <blockquote className="border-l-4 border-theme-interactive-primary pl-4 py-2 mb-4 italic text-theme-muted" {...props}>{children}</blockquote>,
                          hr: ({ ...props }) => <hr className="border-theme my-6" {...props} />,
                          img: ({ alt, ...props }) => <img className="max-w-full h-auto rounded-lg shadow-md my-4" alt={alt || ''} {...props} />,
                          table: ({ children, ...props }) => <div className="overflow-x-auto mb-4"><table className="min-w-full border border-theme" {...props}>{children}</table></div>,
                          thead: ({ children, ...props }) => <thead className="bg-theme-surface" {...props}>{children}</thead>,
                          th: ({ children, ...props }) => <th className="px-4 py-2 text-left font-semibold text-theme-primary border border-theme" {...props}>{children}</th>,
                          td: ({ children, ...props }) => <td className="px-4 py-2 text-theme-primary border border-theme" {...props}>{children}</td>,
                        }}
                      >
                        {getPreviewOutput('markdown')}
                      </ReactMarkdown>
                    </div>
                  </div>
                </div>
              )}
            </div>

            <div className="flex justify-between items-center pt-2 border-t border-theme">
              <div className="text-xs text-theme-muted">Run #{(currentRun.run_id || currentRun.id)?.slice(-8)}</div>
              <div className="flex gap-2">
                <Button variant="outline" onClick={() => setShowPreviewModal(false)} size="sm">Close</Button>
                <Button variant="primary" onClick={() => { setShowPreviewModal(false); downloadFromServer(previewFormat === 'text' ? 'txt' : previewFormat as 'json' | 'txt' | 'markdown'); }} size="sm">
                  <Download className="h-4 w-4 mr-2" />Download {previewFormat.toUpperCase()}
                </Button>
              </div>
            </div>
          </div>
        </Modal>,
        document.body
      )}
    </div>
  );
};

// Helper component for JSON output rendering
const RenderJsonOutput: React.FC<{
  data: unknown;
  showFullOutput: boolean;
  setShowFullOutput: (value: boolean) => void;
  onCopy: (text: string, format: string) => void;
}> = ({ data, showFullOutput, setShowFullOutput, onCopy }) => {
  const outputStr = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
  const lines = outputStr.split('\n');
  const shouldShowToggle = lines.length > 15;
  const displayLines = showFullOutput || !shouldShowToggle ? lines : lines.slice(0, 15);

  return (
    <div className="relative">
      <pre className={`text-xs bg-theme-code rounded border border-theme break-words whitespace-pre-wrap custom-scrollbar ${
        showFullOutput || !shouldShowToggle ? 'max-h-[600px] overflow-auto p-3' : 'max-h-48 overflow-hidden pt-3 px-3 pb-3'
      }`}>
        <code className="text-theme-code-text">{displayLines.join('\n')}</code>
      </pre>
      {shouldShowToggle && (
        <div className="mt-2 flex items-center justify-between">
          <Button
            size="sm"
            variant="ghost"
            onClick={() => setShowFullOutput(!showFullOutput)}
            className="text-xs text-theme-interactive-primary hover:text-theme-interactive-primary/80 p-1 h-auto"
          >
            {showFullOutput ? 'Collapse output' : `Expand to show all ${lines.length} lines`}
          </Button>
          <EnhancedCopyButton data={data} onCopy={onCopy} />
        </div>
      )}
      {!shouldShowToggle && (
        <div className="mt-2 flex items-center justify-end">
          <EnhancedCopyButton data={data} onCopy={onCopy} />
        </div>
      )}
    </div>
  );
};
