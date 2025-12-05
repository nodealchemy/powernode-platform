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
  XCircle,
  AlertCircle,
  Activity,
  Terminal,
  FileText,
  Download,
  Copy,
  Eye,
  Code,
  GitBranch,
  Cpu,
  DollarSign,
  Timer,
  ArrowRight,
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
import { AiWorkflowRun, AiWorkflowNodeExecution, AiWorkflowNode, AiWorkflowEdge } from '@/shared/types/workflow';
import { formatNodeType, sortNodesInExecutionOrder } from '@/shared/utils/workflowUtils';
import { getErrorMessage } from '@/shared/utils/typeGuards';

interface WorkflowExecutionDetailsProps {
  run: AiWorkflowRun;
  workflowId: string;
  isExpanded: boolean;
  onToggle: () => void;
  onDelete?: () => void;
  onRegisterReloadCallback?: (runId: string, callback: () => void) => () => void; // Register reload callback, returns cleanup function
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

  const [nodeExecutions, setNodeExecutions] = useState<AiWorkflowNodeExecution[]>([]);
  const [workflowNodes, setWorkflowNodes] = useState<AiWorkflowNode[]>([]);
  const [workflowEdges, setWorkflowEdges] = useState<AiWorkflowEdge[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set());
  const [expandedInputs, setExpandedInputs] = useState<Set<string>>(new Set());
  const [expandedOutputs, setExpandedOutputs] = useState<Set<string>>(new Set());
  const [expandedMetadata, setExpandedMetadata] = useState<Set<string>>(new Set());
  const [showFullOutput, setShowFullOutput] = useState(false);
  const [runStatus, setRunStatus] = useState(run.status);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [lastUpdateReceived, setLastUpdateReceived] = useState<number | null>(null);
  const [showDownloadMenu, setShowDownloadMenu] = useState(false);
  const [currentRun, setCurrentRun] = useState(run);
  const [liveNodeDurations, setLiveNodeDurations] = useState<Record<string, number>>({});
  const [showPreviewModal, setShowPreviewModal] = useState(false);
  const [previewFormat, setPreviewFormat] = useState<'json' | 'markdown' | 'text'>('json');

  // Use ref to track runStatus without causing useEffect dependencies
  const runStatusRef = useRef(runStatus);
  runStatusRef.current = runStatus;

  // Update run status when the run prop changes - only if actually different
  useEffect(() => {
    if (run.status !== runStatus) {
      setRunStatus(run.status);
    }
  }, [run.status, runStatus]);

  // Update currentRun when the run prop changes
  useEffect(() => {
    setCurrentRun(run);
  }, [run]);

  const loadExecutionDetails = useCallback(async () => {
    // Prevent multiple simultaneous loads using both state and ref
    if (loading || isLoadingRef.current) {
      return;
    }

    // Set loading state in both places for comprehensive tracking
    isLoadingRef.current = true;

    try {
      // Only show loading state if we don't already have data to prevent flickering
      if (nodeExecutions.length === 0) {
        setLoading(true);
      }
      setError(null);

      const runId = run.run_id || run.id;
      if (!runId) {
        throw new Error('No run ID available');
      }

      // Load both workflow definition and execution details in parallel with timeout
      const loadPromises = [
        workflowsApi.getWorkflow(workflowId),
        workflowsApi.getWorkflowRunDetails(runId, workflowId)
      ];

      // Add a timeout to prevent infinite loading
      const timeoutPromise = new Promise((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout - execution history loading timed out')), 30000);
      });

      const [workflowResponse, executionResponse] = await Promise.allSettled([
        Promise.race([loadPromises[0], timeoutPromise]),
        Promise.race([loadPromises[1], timeoutPromise])
      ]);

      // Extract workflow nodes and edges if workflow loaded successfully
      if (workflowResponse.status === 'fulfilled') {
        const workflow = (workflowResponse.value as any).workflow;
        if (workflow.nodes) {
          setWorkflowNodes(workflow.nodes);
        }
        if (workflow.edges) {
          setWorkflowEdges(workflow.edges);
        }
      }

      // Extract execution details if loaded successfully
      if (executionResponse.status === 'fulfilled') {
        const nodeExecs = (executionResponse.value as any).node_executions || [];
        setNodeExecutions(nodeExecs);
      } else if (executionResponse.status === 'rejected') {
        // If execution details fail to load but it's a 404, that's okay (no executions yet)
        const executionError = executionResponse.reason;
        if (executionError?.response?.status !== 404) {
          throw executionError;
        }
        // For 404, set empty executions (nodes will show as pending)
        setNodeExecutions([]);
      }
    } catch (error: unknown) {
      // Failed to load execution details
      const errorMessage = getErrorMessage(error);
      setError(errorMessage);

      // Only show notification for real errors, not 404s (which might mean no executions yet)
      const is404 = typeof error === 'object' && error !== null && 'response' in error &&
                    typeof (error as { response?: { status?: number } }).response === 'object' &&
                    (error as { response?: { status?: number } }).response?.status === 404;

      if (!is404) {
        addNotification({
          type: 'error',
          title: 'Error',
          message: errorMessage
        });
      }
    } finally {
      // Clear loading state in both places - critical for preventing stuck loading
      isLoadingRef.current = false;

      // Use timeout to prevent flickering, but also ensure it's definitely cleared
      const clearLoading = () => {
        setLoading(false);
        // Double-check: if somehow loading is still true after 1 second, force clear it
        setTimeout(() => {
          setLoading(false);
        }, 1000);
      };

      setTimeout(clearLoading, 50);
    }
  }, [run.run_id, run.id, workflowId, addNotification]);

  // Track state to prevent double execution
  const expansionProcessedRef = useRef<string | null>(null);
  const loadingTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const isLoadingRef = useRef<boolean>(false);

  // Load execution details when expanded with robust double-execution prevention
  useEffect(() => {
    if (isExpanded && run.id) {
      const expansionKey = `${run.id}-${isExpanded}`;

      // Clear any pending timeout from previous render
      if (loadingTimeoutRef.current) {
        clearTimeout(loadingTimeoutRef.current);
        loadingTimeoutRef.current = null;
      }

      // Prevent double loading for the same expansion
      if (expansionProcessedRef.current !== expansionKey && !isLoadingRef.current) {
        expansionProcessedRef.current = expansionKey;

        // Add small delay to prevent flickering during expansion animation
        loadingTimeoutRef.current = setTimeout(() => {
          loadingTimeoutRef.current = null;
          // Double-check we're not already loading (could have been triggered by reload)
          if (!isLoadingRef.current) {
            loadExecutionDetails();
          }
        }, 100);

        return () => {
          if (loadingTimeoutRef.current) {
            clearTimeout(loadingTimeoutRef.current);
            loadingTimeoutRef.current = null;
          }
        };
      }
    } else if (!isExpanded) {
      // Clear any pending timeout when collapsed
      if (loadingTimeoutRef.current) {
        clearTimeout(loadingTimeoutRef.current);
        loadingTimeoutRef.current = null;
      }
      // Reset when collapsed to allow re-expansion
      expansionProcessedRef.current = null;
    }
  }, [isExpanded, run.id]);

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (loadingTimeoutRef.current) {
        clearTimeout(loadingTimeoutRef.current);
      }
    };
  }, []);

  // Close download menu when clicking outside
  useEffect(() => {
    const handleClickOutside = () => {
      if (showDownloadMenu) {
        setShowDownloadMenu(false);
      }
    };

    if (showDownloadMenu) {
      document.addEventListener('click', handleClickOutside);
      return () => document.removeEventListener('click', handleClickOutside);
    }
  }, [showDownloadMenu]);

  // Live duration clock for running nodes
  useEffect(() => {
    // Find all running nodes and calculate their live durations
    const runningNodes = nodeExecutions.filter(n => n.status === 'running');

    if (runningNodes.length === 0) {
      // Clear live durations if no nodes are running
      setLiveNodeDurations({});
      return;
    }

    // Set up interval to update durations every second
    const interval = setInterval(() => {
      const now = Date.now();
      const newDurations: Record<string, number> = {};

      runningNodes.forEach(node => {
        if (node.started_at) {
          // Calculate milliseconds since node started
          const startTime = new Date(node.started_at).getTime();
          const elapsed = now - startTime;
          newDurations[node.execution_id] = elapsed;
        }
      });

      setLiveNodeDurations(newDurations);
    }, 1000); // Update every second

    // Initial update
    const initialDurations: Record<string, number> = {};
    const now = Date.now();
    runningNodes.forEach(node => {
      if (node.started_at) {
        const startTime = new Date(node.started_at).getTime();
        const elapsed = now - startTime;
        initialDurations[node.execution_id] = elapsed;
      }
    });
    setLiveNodeDurations(initialDurations);

    return () => clearInterval(interval);
  }, [nodeExecutions]);
  // Register reload callback for parent to trigger reloads without state changes
  useEffect(() => {
    if (!onRegisterReloadCallback || !run.id) return;

    const runId = run.id;

    // Create reload function that checks if we should actually reload
    const handleReload = () => {
      // Only reload if expanded and not currently loading
      if (
        isExpanded &&
        expansionProcessedRef.current === `${runId}-${isExpanded}` &&
        !isLoadingRef.current
      ) {
        // Cancel any pending expansion load since we're doing a reload now
        if (loadingTimeoutRef.current) {
          clearTimeout(loadingTimeoutRef.current);
          loadingTimeoutRef.current = null;
        }

        loadExecutionDetails();
      }
    };

    // Register the callback and get cleanup function
    const cleanup = onRegisterReloadCallback(runId, handleReload);

    return cleanup;
  }, [onRegisterReloadCallback, run.id, isExpanded]);

  // Recalculate progress whenever node executions change
  useEffect(() => {
    if (nodeExecutions.length === 0) return;

    // Filter out placeholder executions (nodes that haven't executed yet)
    const realExecutions = nodeExecutions.filter(n =>
      n.execution_id && !n.execution_id.startsWith('placeholder')
    );

    if (realExecutions.length === 0) return;

    // Count completed and failed nodes
    const completedCount = realExecutions.filter(n =>
      n.status === 'completed' || n.status === 'skipped'
    ).length;

    const failedCount = realExecutions.filter(n =>
      n.status === 'failed'
    ).length;

    // Update currentRun with recalculated progress
    setCurrentRun(prev => {
      // Only update if the counts actually changed to avoid unnecessary rerenders
      if (prev.completed_nodes === completedCount && prev.failed_nodes === failedCount) {
        return prev;
      }

      return {
        ...prev,
        completed_nodes: completedCount,
        failed_nodes: failedCount
      };
    });
  }, [nodeExecutions]);

  // Merge workflow nodes with their execution status
  const mergedNodes = useMemo(() => {
    // Defensive check: ensure nodeExecutions is an array
    const safeNodeExecutions = Array.isArray(nodeExecutions) ? nodeExecutions : [];

    if (workflowNodes.length === 0) {
      // If we don't have workflow nodes yet, return existing executions
      return safeNodeExecutions;
    }

    // Create a map of executions by node ID for quick lookup
    const executionMap = new Map<string, AiWorkflowNodeExecution>();
    safeNodeExecutions.forEach(execution => {
      const nodeId = execution.node?.node_id;
      if (nodeId) {
        executionMap.set(nodeId, execution);
      }
    });

    // Sort workflow nodes by actual execution order using workflow edges
    const sortedNodes = sortNodesInExecutionOrder(workflowNodes, workflowEdges);

    // Map each workflow node to either its execution or a placeholder
    const merged = sortedNodes.map(node => {
      const execution = executionMap.get(node.node_id);

      if (execution) {
        // Return existing execution with updated node info
        return {
          ...execution,
          node: {
            node_id: node.node_id,
            node_type: node.node_type,
            name: node.name
          }
        };
      } else {
        // Create a placeholder execution for nodes that haven't executed yet
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
          node: {
            node_id: node.node_id,
            node_type: node.node_type,
            name: node.name
          },
          input_data: undefined,
          output_data: undefined,
          error_details: undefined,
          metadata: undefined
        } as AiWorkflowNodeExecution;
      }
    });

    return merged;
  }, [workflowNodes, workflowEdges, nodeExecutions]);

  // REMOVED: Auto-expand running executions
  // WebSocket subscriptions now work regardless of expansion state,
  // so auto-expand is not needed and interferes with user intent
  // useEffect(() => {
  //   if (!isExpanded && activeStatuses.includes(runStatus)) {
  //     onToggle();
  //   }
  // }, [runStatus, isExpanded, activeStatuses, onToggle]);

  // Memoize runId to prevent subscription recreation on every run prop change
  const runId = useMemo(() => run.run_id || run.id, [run.run_id, run.id]);

  // Subscribe to real-time updates for active executions
  useEffect(() => {
    if (!isConnected || !runId) {
      return;
    }
    // CRITICAL FIX: Subscribe immediately without delay to catch all node execution broadcasts
    // The 500ms delay was causing the component to miss initial node status updates
    // Backend starts broadcasting immediately, so we must subscribe right away
    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'workflow_run', id: runId },
      onMessage: (data: any) => {
        // Handle node execution updates from unified orchestration channel
        // Backend sends events with 'event' field, not 'type'
        const eventType = data.event || data.type;

        // Handle node execution status updates (unified event from backend)
        // Backend sends 'node.execution.updated' event
        if (eventType === 'node.execution.updated') {
          const nodeExecution = data.payload?.node_execution || data.node_execution;

          if (!nodeExecution) {
            if (process.env.NODE_ENV === 'development') {
              console.warn('[WorkflowExecutionDetails] No nodeExecution in payload');
            }
            return;
          }

          // Track when we received the update
          setLastUpdateReceived(Date.now());

          setNodeExecutions(prev => {
            // FIX: Search by BOTH id and execution_id to handle different API response formats
            // API returns "id", WebSocket returns "execution_id"
            const existingIndex = prev.findIndex(n =>
              n.execution_id === nodeExecution.execution_id ||
              n.id === nodeExecution.execution_id ||
              n.execution_id === nodeExecution.id ||
              n.id === nodeExecution.id
            );

            if (existingIndex !== -1) {
              const existing = prev[existingIndex];

              // Check if the update actually contains new information
              const statusChanged = existing.status !== nodeExecution.status;
              const timingChanged = existing.completed_at !== nodeExecution.completed_at ||
                                  existing.execution_time_ms !== nodeExecution.execution_time_ms;
              const outputChanged = JSON.stringify(existing.output_data) !== JSON.stringify(nodeExecution.output_data);

              // Prevent stale broadcasts from overwriting completed/failed status
              const isBackwardsTransition =
                (existing.status === 'completed' || existing.status === 'failed') &&
                (nodeExecution.status === 'running' || nodeExecution.status === 'pending');

              if (isBackwardsTransition || (!statusChanged && !timingChanged && !outputChanged)) {
                return prev;
              }

              // Update the specific node that changed status
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
              // Add new node execution with proper structure
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

        // Handle live node duration updates
        if (eventType === 'node.duration.updated') {
          const nodeExecution = data.payload?.node_execution;

          // Update the running node with live elapsed time
          setNodeExecutions(prev => {
            const existingIndex = prev.findIndex(n => n.execution_id === nodeExecution.execution_id);

            if (existingIndex !== -1) {
              const existing = prev[existingIndex];

              // Only update duration for running nodes
              if (existing.status === 'running') {
                const updated = [...prev];
                updated[existingIndex] = {
                  ...existing,
                  duration_ms: nodeExecution.duration_ms
                };
                return updated;
              }
            }

            return prev;
          });
        }

        // Handle workflow run status changes
        if (eventType === 'workflow.execution.completed' || eventType === 'workflow.execution.failed' ||
            eventType === 'workflow.status.changed' || eventType === 'workflow.run.status.changed' ||
            eventType === 'workflow.run.progress.changed') {
          const workflowRun = data.payload?.workflow_run || data.workflow_run;
          if (workflowRun?.status && workflowRun.status !== runStatus) {
            setRunStatus(workflowRun.status);

            // Update currentRun with completion data if available
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
                outputVariables: workflowRun.output_variables || prev.output_variables,
                output_variables: workflowRun.output_variables || prev.output_variables
              }));
            }
          }
        }

        // Handle workflow execution started event
        if (eventType === 'workflow.execution.started') {
          const workflowRun = data.payload?.workflow_run || data.workflow_run;

          if (workflowRun) {
            // Update run status if changed
            if (workflowRun.status && workflowRun.status !== runStatus) {
              setRunStatus(workflowRun.status);
            }

            // Update all workflow run data from broadcast
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
              outputVariables: workflowRun.output_variables || prev.output_variables,
              output_variables: workflowRun.output_variables || prev.output_variables
            }));
          } else if (data.status) {
            // Handle simple status update without workflow_run data
            setRunStatus(data.status);
          }
        }
        }
      });

    // Return cleanup function that unsubscribes immediately
    return () => {
      unsubscribe();
    };
  }, [isConnected, runId, subscribe]); // CRITICAL: Use memoized runId to prevent duplicate subscriptions

  const toggleNodeExpansion = useCallback((executionId: string) => {
    setExpandedNodes(prev => {
      const newSet = new Set(prev);
      if (newSet.has(executionId)) {
        newSet.delete(executionId);
      } else {
        newSet.add(executionId);
      }
      return newSet;
    });
  }, []);

  const toggleInputExpansion = useCallback((executionId: string) => {
    setExpandedInputs(prev => {
      const newSet = new Set(prev);
      if (newSet.has(executionId)) {
        newSet.delete(executionId);
      } else {
        newSet.add(executionId);
      }
      return newSet;
    });
  }, []);

  const toggleOutputExpansion = useCallback((executionId: string) => {
    setExpandedOutputs(prev => {
      const newSet = new Set(prev);
      if (newSet.has(executionId)) {
        newSet.delete(executionId);
      } else {
        newSet.add(executionId);
      }
      return newSet;
    });
  }, []);

  const toggleMetadataExpansion = useCallback((executionId: string) => {
    setExpandedMetadata(prev => {
      const newSet = new Set(prev);
      if (newSet.has(executionId)) {
        newSet.delete(executionId);
      } else {
        newSet.add(executionId);
      }
      return newSet;
    });
  }, []);

  const formatDuration = useCallback((ms: number | undefined): string => {
    if (!ms) return '-';
    if (ms < 1000) return `${Math.round(ms)}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    const minutes = Math.floor(ms / 60000);
    const seconds = Math.floor((ms % 60000) / 1000);
    return `${minutes}m ${seconds}s`;
  }, []);

  const copyToClipboard = useCallback((text: string, format?: string) => {
    navigator.clipboard.writeText(text);
    addNotification({
      type: 'success',
      title: 'Copied',
      message: format ? `${format} copied to clipboard` : 'Content copied to clipboard'
    });
  }, [addNotification]);

  // Detect if content is markdown formatted
  const isMarkdownContent = useCallback((text: string): boolean => {
    if (typeof text !== 'string') return false;

    // Check for common markdown patterns
    const markdownPatterns = [
      /^#{1,6}\s/m,           // Headers
      /\*\*[^*]+\*\*/,       // Bold
      /\*[^*]+\*/,            // Italic
      /\[[^\]]+\]\([^)]+\)/, // Links
      /```[\s\S]*?```/,       // Code blocks
      /^\s*[-*+]\s/m,         // Lists
      /^\s*\d+\.\s/m          // Numbered lists
    ];

    return markdownPatterns.some(pattern => pattern.test(text));
  }, []);

  // Extract text content from output (handling various formats)
  const extractOutputText = useCallback((output: unknown): string | null => {
    if (typeof output === 'string') return output;
    if (!output) return null;

    // Type guard for object with properties
    if (typeof output !== 'object') return null;

    const obj = output as Record<string, unknown>;

    // Check for common output patterns
    if ('output' in obj && obj.output) return extractOutputText(obj.output);
    if ('result' in obj && obj.result) return extractOutputText(obj.result);
    if ('data' in obj && obj.data) return extractOutputText(obj.data);
    if ('response' in obj && obj.response) return extractOutputText(obj.response);
    if ('content' in obj && obj.content) return extractOutputText(obj.content);
    if ('text' in obj && obj.text) return extractOutputText(obj.text);
    if ('markdown' in obj && obj.markdown) return extractOutputText(obj.markdown);
    if ('final_markdown' in obj && obj.final_markdown) return extractOutputText(obj.final_markdown);

    // If it's an object, try to stringify it
    return JSON.stringify(output, null, 2);
  }, []);

  // Render copy button with format detection
  const EnhancedCopyButton: React.FC<{
    data: unknown;
    className?: string;
    showLabel?: boolean;
  }> = ({ data, className = '', showLabel = false }) => {
    const [showOptions, setShowOptions] = useState(false);
    const text = extractOutputText(data);
    const isMarkdown = text ? isMarkdownContent(text) : false;

    if (!text) return null;

    if (!isMarkdown) {
      // Simple copy button for non-markdown content
      return (
        <Button
          size="sm"
          variant="ghost"
          onClick={() => copyToClipboard(text, 'Content')}
          className={`p-1 h-auto ${className}`}
          title="Copy to clipboard"
        >
          <Copy className="h-3 w-3" />
          {showLabel && <span className="ml-1 text-xs">Copy</span>}
        </Button>
      );
    }

    // Enhanced copy button for markdown content with options
    return (
      <div className="relative inline-block">
        <Button
          size="sm"
          variant="ghost"
          onClick={() => setShowOptions(!showOptions)}
          className={`p-1 h-auto ${className}`}
          title="Copy options"
        >
          <Copy className="h-3 w-3" />
          {showLabel && <span className="ml-1 text-xs">Copy</span>}
        </Button>
        {showOptions && (
          <>
            <div
              className="fixed inset-0 z-40"
              onClick={() => setShowOptions(false)}
            />
            <div className="absolute right-0 mt-1 bg-theme-surface border border-theme rounded-md shadow-lg z-50 min-w-[180px]">
              <div className="p-2">
                <p className="text-xs text-theme-muted mb-2 font-medium px-2">
                  Copy Format:
                </p>
                <div className="space-y-1">
                  <button
                    onClick={() => {
                      copyToClipboard(text, 'Markdown');
                      setShowOptions(false);
                    }}
                    className="w-full text-left px-2 py-1.5 text-xs rounded hover:bg-theme-hover text-theme-primary flex items-center gap-2"
                  >
                    <FileText className="h-3 w-3" />
                    <span>Markdown Format</span>
                  </button>
                  <button
                    onClick={() => {
                      // Copy plain text (strip markdown formatting)
                      const plainText = text
                        .replace(/#{1,6}\s/g, '')
                        .replace(/\*\*([^*]+)\*\*/g, '$1')
                        .replace(/\*([^*]+)\*/g, '$1')
                        .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
                        .replace(/```[\s\S]*?```/g, '')
                        .trim();
                      copyToClipboard(plainText, 'Plain Text');
                      setShowOptions(false);
                    }}
                    className="w-full text-left px-2 py-1.5 text-xs rounded hover:bg-theme-hover text-theme-primary flex items-center gap-2"
                  >
                    <Terminal className="h-3 w-3" />
                    <span>Plain Text</span>
                  </button>
                  <button
                    onClick={() => {
                      // Copy as HTML (basic markdown to HTML conversion)
                      let html = text
                        .replace(/#{6}\s(.+)/g, '<h6>$1</h6>')
                        .replace(/#{5}\s(.+)/g, '<h5>$1</h5>')
                        .replace(/#{4}\s(.+)/g, '<h4>$1</h4>')
                        .replace(/#{3}\s(.+)/g, '<h3>$1</h3>')
                        .replace(/#{2}\s(.+)/g, '<h2>$1</h2>')
                        .replace(/#{1}\s(.+)/g, '<h1>$1</h1>')
                        .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
                        .replace(/\*([^*]+)\*/g, '<em>$1</em>')
                        .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
                        .replace(/\n/g, '<br/>');
                      copyToClipboard(html, 'HTML');
                      setShowOptions(false);
                    }}
                    className="w-full text-left px-2 py-1.5 text-xs rounded hover:bg-theme-hover text-theme-primary flex items-center gap-2"
                  >
                    <Code className="h-3 w-3" />
                    <span>HTML Format</span>
                  </button>
                </div>
              </div>
            </div>
          </>
        )}
      </div>
    );
  };

  // Render expandable content with See more/See less functionality
  const renderExpandableContent = useCallback((
    data: unknown,
    isExpanded: boolean,
    onToggle: () => void,
    maxLines: number = 6
  ) => {
    const dataStr = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
    const lines = dataStr.split('\n');
    const shouldShowToggle = lines.length > maxLines || dataStr.length > 300;
    const displayLines = isExpanded ? lines : lines.slice(0, maxLines);
    const displayText = displayLines.join('\n');

    return (
      <div className="relative">
        <pre className={`text-xs bg-theme-code rounded border border-theme break-words whitespace-pre-wrap ${
          isExpanded ? 'max-h-[500px] overflow-auto custom-scrollbar p-2' : 'max-h-24 overflow-hidden pt-2 px-2 pb-2'
        }`}>
          <code className="text-theme-code-text">
            {displayText}
            {!isExpanded && shouldShowToggle && lines.length > maxLines && '...'}
          </code>
        </pre>
        {shouldShowToggle && (
          <div className="mt-2 flex items-center justify-between">
            <Button
              size="sm"
              variant="ghost"
              onClick={onToggle}
              className="text-xs text-theme-interactive-primary hover:text-theme-interactive-primary/80 p-1 h-auto"
            >
              {isExpanded ? 'Collapse' : `Expand complete content (${lines.length} lines)`}
            </Button>
            <EnhancedCopyButton data={data} />
          </div>
        )}
        {!shouldShowToggle && (
          <div className="absolute top-2 right-2">
            <EnhancedCopyButton data={data} />
          </div>
        )}
        {isExpanded && shouldShowToggle && (
          <div className="text-xs text-theme-muted mt-1">
            Showing complete content - scroll to view all
          </div>
        )}
      </div>
    );
  }, [EnhancedCopyButton]);

  const exportExecution = () => {
    const exportData = {
      workflow_id: workflowId,
      run_id: currentRun.run_id || currentRun.run_id || currentRun.id,
      status: currentRun.status,
      started_at: currentRun.started_at,
      completed_at: currentRun.completed_at,
      duration: currentRun.duration_seconds,
      cost_usd: currentRun.cost_usd,
      trigger_type: currentRun.trigger_type,
      node_executions: nodeExecutions.map(node => ({
        execution_id: node.execution_id,
        node_id: node.node.node_id,
        node_name: node.node.name,
        node_type: node.node.node_type,
        status: node.status,
        started_at: node.started_at,
        completed_at: node.completed_at,
        duration_ms: node.execution_time_ms || node.duration_ms,
        input: node.input_data,
        output: node.output_data,
        error: node.error_details,
        cost: node.cost || node.cost_usd
      }))
    };

    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `workflow-execution-${currentRun.run_id || currentRun.run_id || currentRun.id}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);

    addNotification({
      type: 'success',
      title: 'Exported',
      message: 'Execution details exported successfully'
    });
  };

  const downloadFromServer = async (format: 'json' | 'txt' | 'markdown') => {
    try {
      const runId = currentRun.run_id || currentRun.id;
      if (!runId) {
        throw new Error('Run ID not found');
      }
      await workflowsApi.downloadWorkflowRun(runId, workflowId, format);

      // The API response should trigger a file download
      addNotification({
        type: 'success',
        title: 'Downloaded',
        message: `Workflow output downloaded as ${format.toUpperCase()}`
      });
    } catch (error: unknown) {
      addNotification({
        type: 'error',
        title: 'Download Failed',
        message: getErrorMessage(error)
      });
    }
  };

  // Get formatted output based on preview format
  const getFormattedOutput = useCallback((format: 'json' | 'markdown' | 'text'): string => {
    // PRIORITY: Always use currentRun first (contains freshly refreshed data)
    // Only fall back to run prop if currentRun has no output
    let output = null;

    // Priority 1: Check currentRun for fresh data (updated by refresh before modal opens)
    if (currentRun.output || currentRun.output_variables || currentRun.output_variables) {
      output = currentRun.output || currentRun.output_variables || currentRun.output_variables;
    }
    // Priority 2: Fall back to run prop only if currentRun has nothing
    else if (run.output || run.output_variables || run.output_variables) {
      output = run.output || run.output_variables || run.output_variables;
    }

    if (!output) {
      return 'No output available. Workflow may not have completed yet or did not produce output.';
    }

    // For JSON format, return the entire output structure
    if (format === 'json') {
      return JSON.stringify(output, null, 2);
    }

    // Extract text content recursively for text/markdown formats
    const extractContent = (data: unknown, depth: number = 0): string => {
      if (typeof data === 'string') {
        return data;
      }
      if (!data) {
        return '';
      }

      // Type guard for object
      if (typeof data !== 'object') {
        return '';
      }

      const obj = data as Record<string, unknown>;

      // PRIORITY 1: Check for new structured format with markdown field (from updated workflow)
      if ('markdown' in obj && typeof obj.markdown === 'string') {
        return obj.markdown;
      }

      // PRIORITY 2: Check nested End node structure
      if ('result' in obj && typeof obj.result === 'object' && obj.result !== null) {
        const result = obj.result as Record<string, unknown>;
        if ('final_output' in result) {
          const finalOutput = result.final_output as Record<string, unknown>;
          if ('markdown' in finalOutput && typeof finalOutput.markdown === 'string') {
            return finalOutput.markdown;
          }
          if ('result' in finalOutput) return extractContent(finalOutput.result, depth + 1);
          if ('output' in finalOutput) return extractContent(finalOutput.output, depth + 1);
        }
      }

      // PRIORITY 3: Check all_node_outputs structure for blog workflow
      if ('data' in obj && typeof obj.data === 'object' && obj.data !== null) {
        const dataObj = obj.data as Record<string, unknown>;
        if ('all_node_outputs' in dataObj) {
          const nodeOutputs = dataObj.all_node_outputs as Record<string, unknown>;

          // Try markdown_formatter first
          if ('markdown_formatter' in nodeOutputs && typeof nodeOutputs.markdown_formatter === 'object' && nodeOutputs.markdown_formatter !== null) {
            const formatter = nodeOutputs.markdown_formatter as Record<string, unknown>;
            if ('output' in formatter) {
              const markdownOutput = formatter.output;

              // Check if it's a valid output (not an error message)
              if (typeof markdownOutput === 'string' && !markdownOutput.includes('error') && !markdownOutput.includes('Error')) {
                // Try to parse JSON if it looks like JSON
                if (markdownOutput.trim().startsWith('{')) {
                  try {
                    const parsed = JSON.parse(markdownOutput);
                    // Recursively extract content from parsed JSON (will check for markdown field)
                    return extractContent(parsed, depth + 1);
                  } catch (e) {
                    // If parsing fails, return as-is (it might be plain markdown)
                    return markdownOutput;
                  }
                }
                return markdownOutput;
              }
            }
          }

          // Fall back to writer node (has the blog post content)
          if ('writer' in nodeOutputs && typeof nodeOutputs.writer === 'object' && nodeOutputs.writer !== null) {
            const writer = nodeOutputs.writer as Record<string, unknown>;
            if ('output' in writer) {
              const writerOutput = writer.output;
              if (typeof writerOutput === 'string') {
                // Try to parse JSON if it looks like JSON
                if (writerOutput.trim().startsWith('{')) {
                  try {
                    const parsed = JSON.parse(writerOutput);
                    return extractContent(parsed, depth + 1);
                  } catch (e) {
                    return writerOutput;
                  }
                }
                return writerOutput;
              }
            }
          }

          // Fall back to editor node
          if ('editor' in nodeOutputs && typeof nodeOutputs.editor === 'object' && nodeOutputs.editor !== null) {
            const editor = nodeOutputs.editor as Record<string, unknown>;
            if ('output' in editor) {
              const editorOutput = editor.output;
              if (typeof editorOutput === 'string') {
                // Try to parse JSON if it looks like JSON
                if (editorOutput.trim().startsWith('{')) {
                  try {
                    const parsed = JSON.parse(editorOutput);
                    return extractContent(parsed, depth + 1);
                  } catch (e) {
                    return editorOutput;
                  }
                }
                return editorOutput;
              }
            }
          }
        }
      }

      // PRIORITY 4: Check common field names
      if ('output' in obj && typeof obj.output === 'string') return obj.output;
      if ('final_markdown' in obj) return extractContent(obj.final_markdown, depth + 1);
      if ('markdown_formatter_output' in obj) return extractContent(obj.markdown_formatter_output, depth + 1);
      if ('output' in obj) return extractContent(obj.output, depth + 1);
      if ('result' in obj && typeof obj.result === 'string') return obj.result;
      if ('content' in obj) return extractContent(obj.content, depth + 1);
      if ('text' in obj) return extractContent(obj.text, depth + 1);
      // CRITICAL FIX: Recurse into data.data if it's an object (contains nested markdown)
      if ('data' in obj) {
        return extractContent(obj.data, depth + 1);
      }
      if ('response' in obj) return extractContent(obj.response, depth + 1);

      // Return JSON stringified version as fallback
      return JSON.stringify(obj, null, 2);
    };

    const content = extractContent(output);

    // Ensure we have content
    if (!content || content === 'No output available') {
      return 'No output available. Workflow may not have completed yet or did not produce output.';
    }

    switch (format) {
      case 'markdown':
        // Return markdown content as-is
        return content;

      case 'text':
        // Strip markdown formatting if present
        if (isMarkdownContent(content)) {
          return content
            .replace(/#{1,6}\s/g, '')
            .replace(/\*\*([^*]+)\*\*/g, '$1')
            .replace(/\*([^*]+)\*/g, '$1')
            .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
            .replace(/```[\s\S]*?```/g, '')
            .replace(/^\s*[-*+]\s/gm, '• ')
            .replace(/^\s*\d+\.\s/gm, '')
            .trim();
        }
        return content;

      default:
        return content;
    }
  }, [currentRun, run, isMarkdownContent]);

  // No need for custom markdown parser - using react-markdown library instead

  const handleDelete = async () => {
    if (runStatus === 'running' || runStatus === 'initializing') {
      addNotification({
        type: 'error',
        title: 'Cannot Delete',
        message: 'Cannot delete a workflow execution while it is running'
      });
      return;
    }

    setIsDeleting(true);
    try {
      const runId = run.run_id || run.id;
      if (!runId) {
        throw new Error('Run ID not found');
      }
      await workflowsApi.deleteWorkflowRun(runId, workflowId);

      addNotification({
        type: 'success',
        title: 'Deleted',
        message: `Workflow run #${runId.slice(-8)} deleted successfully`
      });

      // Close the confirmation modal first
      setShowDeleteConfirm(false);

      // Call the onDelete callback to update parent component
      if (onDelete) {
        onDelete();
      }
    } catch (error: unknown) {
      addNotification({
        type: 'error',
        title: 'Delete Failed',
        message: getErrorMessage(error)
      });
    } finally {
      setIsDeleting(false);
    }
  };

  // Handle Enter key in delete confirmation modal
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

  const renderStatusIcon = useCallback((status: string) => {
    switch (status) {
      case 'completed':
        return <CheckCircle className="h-4 w-4 text-theme-success" />;
      case 'failed':
        return <XCircle className="h-4 w-4 text-theme-error" />;
      case 'running':
        return <Activity className="h-4 w-4 text-theme-info animate-pulse" />;
      case 'cancelled':
        return <AlertCircle className="h-4 w-4 text-theme-warning" />;
      case 'pending':
        return <Clock className="h-4 w-4 text-theme-muted" />;
      default:
        return <AlertCircle className="h-4 w-4 text-theme-muted" />;
    }
  }, []);

  const renderNodeOutput = (output: unknown) => {
    if (!output || (typeof output === 'object' && output !== null && Object.keys(output).length === 0)) {
      return <span className="text-theme-muted">No output</span>;
    }

    // Special handling for different output types
    if (typeof output === 'object' && output !== null) {
      const obj = output as Record<string, unknown>;

      // Check if it's an error object
      if ('error' in obj || 'error_message' in obj) {
        return (
          <div className="relative bg-theme-error/10 border border-theme-error/20 rounded p-3">
            <div className="absolute top-2 right-2">
              <EnhancedCopyButton data={output} />
            </div>
            <p className="text-sm text-theme-error font-medium mb-1">Error Output:</p>
            <pre className="text-xs overflow-x-auto pr-8">
              <code className="text-theme-error">{JSON.stringify(output, null, 2)}</code>
            </pre>
          </div>
        );
      }

      // Check if it's a result with specific fields
      if ('result' in obj || 'data' in obj || 'response' in obj) {
        const mainContent = obj.result || obj.data || obj.response;
        return (
          <div className="space-y-2">
            <>
              {'message' in obj && obj.message ? (
                <div className="text-sm text-theme-primary">
                  <span className="font-medium">Message:</span> {String(obj.message)}
                </div>
              ) : null}
              <div className="relative bg-theme-code p-3 rounded border border-theme">
                <div className="absolute top-2 right-2">
                  <EnhancedCopyButton data={mainContent} />
                </div>
                <pre className="text-xs overflow-x-auto pr-8">
                  <code className="text-theme-code-text">
                    {typeof mainContent === 'string' ? mainContent : JSON.stringify(mainContent, null, 2)}
                  </code>
                </pre>
              </div>
              {'metadata' in obj && obj.metadata && (
                <details className="text-xs">
                  <summary className="cursor-pointer text-theme-muted hover:text-theme-primary">
                    Metadata
                  </summary>
                  <pre className="mt-2 p-2 bg-theme-surface rounded overflow-x-auto">
                    <code>{JSON.stringify(obj.metadata, null, 2)}</code>
                  </pre>
                </details>
              )}
            </>
          </div>
        );
      }

      // For arrays, show count and preview
      if (Array.isArray(output)) {
        return (
          <div>
            <p className="text-xs text-theme-muted mb-2">
              Array with {output.length} item{output.length !== 1 ? 's' : ''}
            </p>
            <RenderJsonOutput data={output} />
          </div>
        );
      }
    }

    // Default JSON rendering with expandable view
    return (
      <div>
        <p className="text-xs text-theme-muted mb-2 flex items-center gap-1">
          <span>Output:</span>
        </p>
        <RenderJsonOutput data={output} />
      </div>
    );
  };

  // Helper component for rendering JSON with expand/collapse
  const RenderJsonOutput: React.FC<{ data: unknown }> = ({ data }) => {
    const outputStr = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
    const lines = outputStr.split('\n');
    // Always show complete output without arbitrary line limits
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
            <EnhancedCopyButton data={data} />
          </div>
        )}
        {!shouldShowToggle && (
          <div className="mt-2 flex items-center justify-end">
            <EnhancedCopyButton data={data} />
          </div>
        )}
        {showFullOutput && shouldShowToggle && (
          <div className="text-xs text-theme-muted mt-1">
            Showing complete output ({lines.length} lines)
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="border-l-2 border-theme ml-8">
      {/* Execution Header - Always Visible */}
      <div
        className="flex items-start justify-between p-4 hover:bg-theme-surface/50 transition-colors"
      >
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <button
              onClick={(e) => {
                e.stopPropagation();
                onToggle();
              }}
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
              Run #{(currentRun.run_id || currentRun.run_id || currentRun.id)?.slice(-8)}
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
              onClick={(e) => {
                e.stopPropagation();
                setShowDownloadMenu(!showDownloadMenu);
              }}
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
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setShowDownloadMenu(false);
                        downloadFromServer('json');
                      }}
                      className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary"
                    >
                      JSON (structured data)
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setShowDownloadMenu(false);
                        downloadFromServer('txt');
                      }}
                      className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary"
                    >
                      Text (readable format)
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setShowDownloadMenu(false);
                        downloadFromServer('markdown');
                      }}
                      className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary"
                    >
                      Markdown (formatted)
                    </button>
                    <hr className="my-1 border-theme" />
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setShowDownloadMenu(false);
                        exportExecution();
                      }}
                      className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-muted"
                    >
                      Export Execution Details
                    </button>
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* Preview Button */}
          <Button
            size="sm"
            variant="ghost"
            onClick={async (e) => {
              e.stopPropagation();
              // Refresh execution details before showing preview to ensure we have latest output
              try {
                const runId = run.run_id || run.id;
                if (runId && workflowId) {
                  const executionResponse = await workflowsApi.getWorkflowRunDetails(runId, workflowId);
                  if (executionResponse.workflow_run) {
                    setCurrentRun(prev => ({
                      ...prev,
                      ...executionResponse.workflow_run,
                      output: executionResponse.workflow_run.output || prev.output,
                      outputVariables: executionResponse.workflow_run.output_variables || executionResponse.workflow_run.output_variables || prev.output_variables,
                      output_variables: executionResponse.workflow_run.output_variables || prev.output_variables
                    }));
                  }
                }
              } catch (error) {
                console.error('Failed to refresh output before preview:', error);
                // Continue anyway - show preview with existing data
              }
              setShowPreviewModal(true);
            }}
            className="p-2"
            title="Preview workflow output"
          >
            <Eye className="h-4 w-4" />
          </Button>

          <Button
            size="sm"
            variant="ghost"
            onClick={(e) => {
              e.stopPropagation();
              loadExecutionDetails();
            }}
            className="p-2"
            title="Refresh execution details"
          >
            <Activity className="h-4 w-4" />
          </Button>
          <Button
            size="sm"
            variant="ghost"
            onClick={(e) => {
              e.stopPropagation();
              if (runStatus === 'running' || runStatus === 'initializing') {
                addNotification({
                  type: 'warning',
                  title: 'Cannot Delete',
                  message: 'Cannot delete a workflow execution while it is running'
                });
                return;
              }
              setShowDeleteConfirm(true);
            }}
            className={`p-2 ${
              runStatus === 'running' || runStatus === 'initializing'
                ? 'text-theme-muted opacity-50 cursor-not-allowed'
                : 'text-theme-destructive hover:bg-theme-destructive/10'
            }`}
            title={
              runStatus === 'running' || runStatus === 'initializing'
                ? 'Cannot delete while execution is running'
                : 'Delete execution'
            }
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
                    <p className="text-sm text-theme-primary font-medium">
                      Unable to load detailed execution logs
                    </p>
                    <p className="text-xs text-theme-muted mt-1">
                      The execution summary is shown above. Detailed node-by-node execution logs may not be available for this run.
                    </p>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={loadExecutionDetails}
                      className="mt-3"
                    >
                      Try Again
                    </Button>
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
                      <p className="font-medium text-theme-primary capitalize">
                        {run.trigger_type || 'manual'}
                      </p>
                    </div>
                    <div>
                      <span className="text-theme-muted">Started:</span>
                      <p className="font-medium text-theme-primary">
                        {new Date(run.started_at || run.created_at).toLocaleTimeString()}
                      </p>
                    </div>
                    {run.completed_at && (
                      <div>
                        <span className="text-theme-muted">Completed:</span>
                        <p className="font-medium text-theme-primary">
                          {new Date(run.completed_at).toLocaleTimeString()}
                        </p>
                      </div>
                    )}
                    <div>
                      <span className="text-theme-muted">Total Duration:</span>
                      <p className="font-medium text-theme-primary">
                        {formatDuration((currentRun.duration_seconds || 0) * 1000)}
                      </p>
                    </div>
                  </div>

                  {/* Input Variables */}
                  {run.input_variables && Object.keys(run.input_variables).length > 0 && (
                    <div className="mt-2 pt-2 border-t border-theme">
                      <p className="text-sm text-theme-muted mb-1">Input Variables:</p>
                      <pre className="text-xs bg-theme-code p-2 rounded border border-theme overflow-x-auto">
                        <code className="text-theme-code-text">
                          {JSON.stringify(run.input_variables, null, 2)}
                        </code>
                      </pre>
                    </div>
                  )}

                  {/* Error Details - only show for failed workflow runs */}
                  {run.error_details && Object.keys(run.error_details).length > 0 && runStatus === 'failed' && (
                    <div className="mt-2 pt-2 border-t border-theme-error/20">
                      <p className="text-sm text-theme-error font-medium mb-1">Error Details:</p>
                      <div className="bg-theme-error/10 border border-theme-error/20 rounded p-3">
                        <p className="text-sm text-theme-error">
                          {run.error_details.error_message || 'An error occurred during execution'}
                        </p>
                        {run.error_details.stack_trace && (
                          <pre className="text-xs mt-2 overflow-x-auto">
                            <code>{run.error_details.stack_trace}</code>
                          </pre>
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
                    {mergedNodes.map((node, index) => {
                      const isExpanded = expandedNodes.has(node.execution_id);
                      const isLast = index === mergedNodes.length - 1;

                      // Rendering node execution details

                      return (
                        <div key={`${node.execution_id || `fallback-${index}`}-${node.node?.node_id || index}`} className="relative">
                          {/* Connection line */}
                          {!isLast && (
                            <div className="absolute left-4 top-10 bottom-0 w-0.5 bg-theme-border" />
                          )}

                          {/* Node Execution Card */}
                          <div className="flex items-start gap-3">
                            {/* Status Icon */}
                            <div className="relative flex items-center justify-center w-8 h-8 rounded-full bg-theme-surface border-2 border-theme">
                              {renderStatusIcon(node.status)}
                              {/* Debug indicator for development */}
                              {process.env.NODE_ENV === 'development' && (
                                <div className="absolute -top-1 -right-1 text-xs bg-theme-warning text-theme-warning-text px-1 rounded" title={`Status: ${node.status}`}>
                                  {node.status === 'completed' ? '✓' : node.status === 'failed' ? '✗' : node.status === 'running' ? '⏳' : '⭕'}
                                </div>
                              )}
                            </div>

                            {/* Node Details */}
                            <div className="flex-1 border border-theme rounded-lg bg-theme-surface">
                              <div
                                className="p-2 cursor-pointer hover:bg-theme-hover/50 transition-colors"
                                onClick={() => toggleNodeExpansion(node.execution_id)}
                              >
                                <div className="flex items-start justify-between">
                                  <div className="flex-1">
                                    <div className="flex items-center gap-2">
                                      {isExpanded ? (
                                        <ChevronDown className="h-3 w-3 text-theme-muted" />
                                      ) : (
                                        <ChevronRight className="h-3 w-3 text-theme-muted" />
                                      )}
                                      <h5 className="font-medium text-sm text-theme-primary">
                                        {node.node?.name || `Node ${index + 1}`}
                                      </h5>
                                      <Badge variant="outline" size="sm">
                                        {formatNodeType(node.node?.node_type || 'unknown')}
                                      </Badge>
                                    </div>

                                    <div className="flex items-center gap-3 mt-1 text-xs text-theme-muted">
                                      <span className="flex items-center gap-1">
                                        <Clock className="h-3 w-3" />
                                        {node.status === 'running' && liveNodeDurations[node.execution_id]
                                          ? `${formatDuration(liveNodeDurations[node.execution_id])} (live)`
                                          : formatDuration(node.execution_time_ms || node.duration_ms)
                                        }
                                        {node.status === 'running' && liveNodeDurations[node.execution_id] && (
                                          <span className="animate-pulse text-theme-info">●</span>
                                        )}
                                      </span>
                                      {node.tokens_used && (
                                        <span className="flex items-center gap-1">
                                          <Cpu className="h-3 w-3" />
                                          {node.tokens_used} tokens
                                        </span>
                                      )}
                                      {(node.cost || node.cost_usd) && ((node.cost || node.cost_usd) ?? 0) > 0 && (
                                        <span className="flex items-center gap-1">
                                          <DollarSign className="h-3 w-3" />
                                          ${(node.cost || node.cost_usd || 0).toFixed(4)}
                                        </span>
                                      )}
                                    </div>
                                  </div>

                                  <Badge
                                    variant={
                                      node.status === 'completed' ? 'success' :
                                      node.status === 'failed' ? 'danger' :
                                      node.status === 'running' ? 'info' :
                                      node.status === 'pending' ? 'outline' :
                                      node.status === 'cancelled' ? 'secondary' :
                                      'secondary'
                                    }
                                    size="sm"
                                  >
                                    {node.status}
                                  </Badge>
                                </div>
                              </div>

                              {/* Expanded Node Details */}
                              {isExpanded && (
                                <div className="border-t border-theme px-2 pb-1 space-y-1">
                                  {/* Input */}
                                  {node.input_data && (
                                    <div className="mt-2">
                                      <p className="text-xs text-theme-muted mb-2 flex items-center gap-1">
                                        <ArrowRight className="h-3 w-3" />
                                        Input:
                                      </p>
                                      {renderExpandableContent(
                                        node.input_data,
                                        expandedInputs.has(node.execution_id),
                                        () => toggleInputExpansion(node.execution_id),
                                        6
                                      )}
                                    </div>
                                  )}

                                  {/* Output */}
                                  {node.output_data && (
                                    <div>
                                      <p className="text-xs text-theme-muted mb-2 flex items-center gap-1">
                                        <FileText className="h-3 w-3" />
                                        Output:
                                      </p>
                                      {renderExpandableContent(
                                        node.output_data,
                                        expandedOutputs.has(node.execution_id),
                                        () => toggleOutputExpansion(node.execution_id),
                                        6
                                      )}
                                    </div>
                                  )}

                                  {/* Error - only show for failed nodes */}
                                  {node.error_details && node.status === 'failed' && (
                                    <div>
                                      <p className="text-xs text-theme-error mb-1 flex items-center gap-1">
                                        <XCircle className="h-3 w-3" />
                                        Error:
                                      </p>
                                      <div className="bg-theme-error/10 border border-theme-error/20 rounded p-2">
                                        <p className="text-xs text-theme-error">
                                          {node.error_details.message || 'Node execution failed'}
                                        </p>
                                        {node.error_details.stack && (
                                          <pre className="text-xs mt-1 overflow-x-auto">
                                            <code>{node.error_details.stack}</code>
                                          </pre>
                                        )}
                                      </div>
                                    </div>
                                  )}

                                  {/* Metadata */}
                                  {node.metadata && Object.keys(node.metadata).length > 0 && (
                                    <div>
                                      <p className="text-xs text-theme-muted mb-2 flex items-center gap-1">
                                        <Code className="h-3 w-3" />
                                        Metadata:
                                      </p>
                                      {renderExpandableContent(
                                        node.metadata,
                                        expandedMetadata.has(node.execution_id),
                                        () => toggleMetadataExpansion(node.execution_id),
                                        6
                                      )}
                                    </div>
                                  )}
                                </div>
                              )}
                            </div>
                          </div>
                        </div>
                      );
                    })}
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
                      <p className="text-xs mt-2">
                        {loading ? 'Loading workflow structure...' : 'This workflow may not have any defined nodes.'}
                      </p>
                    </div>
                  </CardContent>
                </Card>
              )}

              {/* Final Workflow Output */}
              {(() => {
                const output = run.output || run.output_variables || run.output_variables;
                const hasOutput = output && typeof output === 'object' && Object.keys(output).length > 0;

                // Checking final workflow output

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
                          {Object.keys(run.output_variables || run.output_variables || run.output || {}).length} variables
                        </Badge>
                        <EnhancedCopyButton data={run.output || run.output_variables || run.output_variables} showLabel={false} />
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => {
                            const output = run.output || run.output_variables || run.output_variables;
                            const blob = new Blob([
                              typeof output === 'string'
                                ? output
                                : JSON.stringify(output, null, 2)
                            ], { type: 'application/json' });
                            const url = window.URL.createObjectURL(blob);
                            const a = document.createElement('a');
                            a.href = url;
                            a.download = `workflow-output-${run.run_id || run.id}.json`;
                            document.body.appendChild(a);
                            a.click();
                            document.body.removeChild(a);
                            window.URL.revokeObjectURL(url);
                          }}
                          className="p-1"
                        >
                          <Download className="h-3 w-3" />
                        </Button>
                      </div>
                    </div>
                  
                  <CardContent>
                    {renderNodeOutput(run.output || run.output_variables || run.output_variables)}
                  </CardContent>
                </Card>
              )}

              {/* Debug Output Section (Development Only) */}
              {process.env.NODE_ENV === 'development' && runStatus === 'completed' && (() => {
                const output = run.output || run.output_variables || run.output_variables;
                const hasOutput = output && typeof output === 'object' && Object.keys(output).length > 0;
                return !hasOutput;
              })() && (
                <Card className="border-theme-warning/30 bg-theme-warning/5">
                  
                    <CardTitle className="text-sm flex items-center gap-2">
                      <AlertCircle className="h-4 w-4 text-theme-warning" />
                      Debug: Empty Output (Development Only)
                    </CardTitle>
                  
                  <CardContent>
                    <div className="space-y-1 text-xs">
                      <div>
                        <span className="font-medium">Run ID:</span> {run.run_id || run.id}
                      </div>
                      <div>
                        <span className="font-medium">Status:</span> {run.status}
                      </div>
                      <div>
                        <span className="font-medium">Available Output Fields:</span>
                        <pre className="mt-1 p-2 bg-theme-code rounded text-theme-code-text">
                          {JSON.stringify({
                            output: run.output,
                            outputVariables: run.output_variables,
                            output_variables: run.output_variables,
                            allKeys: Object.keys(run)
                          }, null, 2)}
                        </pre>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              )}
            </>
          )}
        </div>
      )}

      {/* Delete Confirmation Modal - Rendered at document root to prevent z-index issues */}
      {showDeleteConfirm && createPortal(
        <Modal
          isOpen={showDeleteConfirm}
          onClose={() => setShowDeleteConfirm(false)}
          title="Delete Workflow Execution"
          maxWidth="md"
          variant="centered"
        >
          <div className="space-y-4">
            <div className="flex items-start gap-3">
              <AlertCircle className="h-5 w-5 text-theme-warning mt-0.5" />
              <div className="flex-1">
                <p className="text-sm text-theme-primary font-medium">
                  Are you sure you want to delete this workflow execution?
                </p>
                <p className="text-xs text-theme-muted mt-1">
                  This will permanently delete run #{run.run_id?.slice(-8) || run.id?.slice(-8) || 'Unknown'} and all associated execution logs.
                  This action cannot be undone.
                </p>
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
                  <dd className="text-theme-primary">
                    {(run.started_at || run.created_at)
                      ? new Date(run.started_at || run.created_at).toLocaleString()
                      : 'Unknown'
                    }
                  </dd>
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
              <Button
                variant="outline"
                onClick={() => setShowDeleteConfirm(false)}
                disabled={isDeleting}
              >
                Cancel
              </Button>
              <Button
                variant="danger"
                onClick={handleDelete}
                disabled={isDeleting}
                title="Press Enter to delete"
              >
                {isDeleting ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin mr-2" />
                    Deleting...
                  </>
                ) : (
                  <>
                    <Trash2 className="h-4 w-4 mr-2" />
                    Delete Execution
                    <span className="ml-2 text-xs opacity-70">(Enter)</span>
                  </>
                )}
              </Button>
            </div>
          </div>
        </Modal>,
        document.body
      )}

      {/* Preview Modal - Rendered at document root */}
      {showPreviewModal && createPortal(
        <Modal
          isOpen={showPreviewModal}
          onClose={() => setShowPreviewModal(false)}
          title="Preview Workflow Output"
          maxWidth="4xl"
          variant="centered"
          disableContentScroll={true}
        >
          <div className="space-y-4">
            {/* Format Selector */}
            <div className="flex items-center gap-2 pb-3 border-b border-theme">
              <span className="text-sm text-theme-muted font-medium">Format:</span>
              <div className="flex gap-1">
                <Button
                  size="sm"
                  variant={previewFormat === 'json' ? 'primary' : 'outline'}
                  onClick={() => setPreviewFormat('json')}
                  className="px-3 py-1 text-xs"
                >
                  <Code className="h-3 w-3 mr-1" />
                  JSON
                </Button>
                <Button
                  size="sm"
                  variant={previewFormat === 'text' ? 'primary' : 'outline'}
                  onClick={() => setPreviewFormat('text')}
                  className="px-3 py-1 text-xs"
                >
                  <Terminal className="h-3 w-3 mr-1" />
                  Text
                </Button>
                <Button
                  size="sm"
                  variant={previewFormat === 'markdown' ? 'primary' : 'outline'}
                  onClick={() => setPreviewFormat('markdown')}
                  className="px-3 py-1 text-xs"
                >
                  <FileText className="h-3 w-3 mr-1" />
                  Markdown
                </Button>
              </div>
              <div className="flex-1" />
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  const content = getFormattedOutput(previewFormat);
                  copyToClipboard(content, `${previewFormat.toUpperCase()} content`);
                }}
                className="px-3 py-1 text-xs"
              >
                <Copy className="h-3 w-3 mr-1" />
                Copy
              </Button>
            </div>

            {/* Preview Content - Fixed height to fit modal */}
            <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden" style={{ height: '60vh', minHeight: '400px' }}>
              {previewFormat === 'json' && (
                <div className="relative h-full flex flex-col">
                  <div className="bg-theme-surface/95 backdrop-blur-sm border-b border-theme px-4 py-2 text-xs text-theme-muted flex-shrink-0">
                    <span className="flex items-center gap-2">
                      <Code className="h-3 w-3" />
                      Complete JSON output - scroll to view all content
                    </span>
                  </div>
                  <div className="flex-1 overflow-auto custom-scrollbar">
                    <pre className="p-4 text-sm">
                      <code className="text-theme-code-text">
                        {getFormattedOutput('json')}
                      </code>
                    </pre>
                  </div>
                </div>
              )}

              {previewFormat === 'text' && (
                <div className="relative h-full flex flex-col">
                  <div className="bg-theme-surface/95 backdrop-blur-sm border-b border-theme px-4 py-2 text-xs text-theme-muted flex-shrink-0">
                    <span className="flex items-center gap-2">
                      <Terminal className="h-3 w-3" />
                      Complete text output - scroll to view all content
                    </span>
                  </div>
                  <div className="flex-1 overflow-auto custom-scrollbar">
                    <pre className="p-4 text-sm whitespace-pre-wrap">
                      <code className="text-theme-primary">
                        {getFormattedOutput('text')}
                      </code>
                    </pre>
                  </div>
                </div>
              )}

              {previewFormat === 'markdown' && (
                <div className="relative h-full flex flex-col">
                  <div className="bg-theme-surface/95 backdrop-blur-sm border-b border-theme px-4 py-2 text-xs text-theme-muted flex-shrink-0">
                    <span className="flex items-center gap-2">
                      <FileText className="h-3 w-3" />
                      Complete markdown document - scroll to view all content
                    </span>
                  </div>
                  <div className="flex-1 overflow-auto custom-scrollbar p-6">
                    {/* Rendered Markdown View using react-markdown */}
                    <div className="markdown-content text-theme-primary">
                    <ReactMarkdown
                      remarkPlugins={[remarkGfm, remarkBreaks]}
                      components={{
                        // Headings
                        h1: ({ children, ...props }) => (
                          <h1 className="text-3xl font-bold text-theme-primary mt-6 mb-4 first:mt-0" {...props}>{children}</h1>
                        ),
                        h2: ({ children, ...props }) => (
                          <h2 className="text-2xl font-bold text-theme-primary mt-5 mb-3" {...props}>{children}</h2>
                        ),
                        h3: ({ children, ...props }) => (
                          <h3 className="text-xl font-bold text-theme-primary mt-4 mb-2" {...props}>{children}</h3>
                        ),
                        h4: ({ children, ...props }) => (
                          <h4 className="text-lg font-semibold text-theme-primary mt-3 mb-2" {...props}>{children}</h4>
                        ),
                        h5: ({ children, ...props }) => (
                          <h5 className="text-base font-semibold text-theme-primary mt-3 mb-2" {...props}>{children}</h5>
                        ),
                        h6: ({ children, ...props }) => (
                          <h6 className="text-sm font-semibold text-theme-primary mt-3 mb-2" {...props}>{children}</h6>
                        ),
                        // Paragraphs
                        p: ({ children, ...props }) => (
                          <p className="text-theme-primary mb-4 leading-7" {...props}>{children}</p>
                        ),
                        // Lists
                        ul: ({ children, ...props }) => (
                          <ul className="list-disc list-inside mb-4 space-y-2 text-theme-primary" {...props}>{children}</ul>
                        ),
                        ol: ({ children, ...props }) => (
                          <ol className="list-decimal list-inside mb-4 space-y-2 text-theme-primary" {...props}>{children}</ol>
                        ),
                        li: ({ children, ...props }) => (
                          <li className="text-theme-primary ml-4" {...props}>{children}</li>
                        ),
                        // Inline formatting
                        strong: ({ children, ...props }) => (
                          <strong className="font-bold text-theme-primary" {...props}>{children}</strong>
                        ),
                        em: ({ children, ...props }) => (
                          <em className="italic text-theme-primary" {...props}>{children}</em>
                        ),
                        // Links
                        a: ({ children, ...props }) => (
                          <a
                            className="text-theme-interactive-primary hover:underline"
                            target="_blank"
                            rel="noopener noreferrer"
                            {...props}
                          >{children}</a>
                        ),
                        // Code
                        code: ({ node, ...props }) => {
                          const isInline = node && 'properties' in node && node.properties && 'inline' in node.properties;
                          return isInline ? (
                            <code
                              className="px-1.5 py-0.5 bg-theme-code text-theme-code-text rounded text-sm font-mono"
                              {...props}
                            />
                          ) : (
                            <code
                              className="block bg-theme-code text-theme-code-text rounded p-4 overflow-x-auto font-mono text-sm"
                              {...props}
                            />
                          );
                        },
                        pre: ({ children, ...props }) => (
                          <pre className="bg-theme-code rounded p-4 mb-4 overflow-x-auto" {...props}>{children}</pre>
                        ),
                        // Blockquotes
                        blockquote: ({ children, ...props }) => (
                          <blockquote
                            className="border-l-4 border-theme-interactive-primary pl-4 py-2 mb-4 italic text-theme-muted"
                            {...props}
                          >{children}</blockquote>
                        ),
                        // Horizontal rule
                        hr: ({ ...props }) => (
                          <hr className="border-theme my-6" {...props} />
                        ),
                        // Images - alt comes from markdown via props
                        img: ({ alt, ...props }) => (
                          <img
                            className="max-w-full h-auto rounded-lg shadow-md my-4"
                            alt={alt || ''}
                            {...props}
                          />
                        ),
                        // Tables
                        table: ({ children, ...props }) => (
                          <div className="overflow-x-auto mb-4">
                            <table className="min-w-full border border-theme" {...props}>{children}</table>
                          </div>
                        ),
                        thead: ({ children, ...props }) => (
                          <thead className="bg-theme-surface" {...props}>{children}</thead>
                        ),
                        tbody: ({ children, ...props }) => (
                          <tbody {...props}>{children}</tbody>
                        ),
                        tr: ({ children, ...props }) => (
                          <tr className="border-b border-theme" {...props}>{children}</tr>
                        ),
                        th: ({ children, ...props }) => (
                          <th className="px-4 py-2 text-left font-semibold text-theme-primary border border-theme" {...props}>{children}</th>
                        ),
                        td: ({ children, ...props }) => (
                          <td className="px-4 py-2 text-theme-primary border border-theme" {...props}>{children}</td>
                        ),
                      }}
                    >
                      {getFormattedOutput('markdown')}
                    </ReactMarkdown>
                  </div>
                </div>
                </div>
              )}
            </div>

            {/* Actions */}
            <div className="flex justify-between items-center pt-2 border-t border-theme">
              <div className="text-xs text-theme-muted">
                Run #{(currentRun.run_id || currentRun.run_id || currentRun.id)?.slice(-8)}
              </div>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  onClick={() => setShowPreviewModal(false)}
                  size="sm"
                >
                  Close
                </Button>
                <Button
                  variant="primary"
                  onClick={() => {
                    setShowPreviewModal(false);
                    // Map preview format to download format
                    const downloadFormat = previewFormat === 'text' ? 'txt' : previewFormat;
                    downloadFromServer(downloadFormat as 'json' | 'txt' | 'markdown');
                  }}
                  size="sm"
                >
                  <Download className="h-4 w-4 mr-2" />
                  Download {previewFormat.toUpperCase()}
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