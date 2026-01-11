// Hook for managing workflow runs state and operations

import { useState, useRef, useCallback, useEffect } from 'react';
import { workflowsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { AiWorkflowRun, AIOrchestrationMessage } from '@/shared/types/workflow';
import { getErrorMessage } from '@/shared/utils/typeGuards';

interface UseWorkflowRunsOptions {
  workflowId: string;
  isOpen: boolean;
  activeTab: string;
}

interface UseWorkflowRunsReturn {
  workflowRuns: AiWorkflowRun[];
  runsLoading: boolean;
  runsError: string | null;
  expandedRuns: Set<string>;
  isDeletingAll: boolean;
  loadWorkflowRuns: () => Promise<void>;
  setWorkflowRuns: React.Dispatch<React.SetStateAction<AiWorkflowRun[]>>;
  toggleRunExpansion: (runId: string) => void;
  handleRunDeletion: (runId: string) => void;
  handleDeleteAllRuns: () => Promise<void>;
  setExpandedRuns: React.Dispatch<React.SetStateAction<Set<string>>>;
  handleWorkflowRunUpdate: (message: AIOrchestrationMessage) => void;
  registerReloadCallback: (runId: string, callback: () => void) => () => void;
  getToggleHandler: (runId: string) => () => void;
  getDeleteHandler: (runId: string) => () => void;
}

export const useWorkflowRuns = ({
  workflowId,
  isOpen,
  activeTab
}: UseWorkflowRunsOptions): UseWorkflowRunsReturn => {
  const { showNotification } = useNotifications();

  const [workflowRuns, setWorkflowRuns] = useState<AiWorkflowRun[]>([]);
  const [runsLoading, setRunsLoading] = useState(false);
  const [runsError, setRunsError] = useState<string | null>(null);
  const [expandedRuns, setExpandedRuns] = useState<Set<string>>(new Set());
  const [isDeletingAll, setIsDeletingAll] = useState(false);

  const loadingRef = useRef(false);
  const previousActiveTabRef = useRef<string>('overview');
  const expandedRunsRef = useRef<Set<string>>(new Set());
  const reloadCallbacksRef = useRef<Map<string, () => void>>(new Map());
  const lastReloadTimeRef = useRef<number>(Date.now());

  // Handler refs for stable callbacks
  const handlersRef = useRef<{
    toggle: Map<string, () => void>;
    delete: Map<string, () => void>;
  }>({
    toggle: new Map(),
    delete: new Map()
  });

  // Load workflow runs
  const loadWorkflowRuns = useCallback(async () => {
    if (!workflowId || !isOpen) return;

    if (loadingRef.current) return;

    try {
      loadingRef.current = true;
      setRunsLoading(true);
      setRunsError(null);
      const response = await workflowsApi.getRuns(workflowId, {
        page: 1,
        per_page: 10,
        sort_by: 'created_at',
        sort_order: 'desc'
      });
      setWorkflowRuns(response.items || []);
    } catch (err) {
      setRunsError('Failed to load execution history. Please try again.');
    } finally {
      setRunsLoading(false);
      loadingRef.current = false;
    }
  }, [workflowId, isOpen]);

  // Toggle run expansion
  const toggleRunExpansion = useCallback((runId: string) => {
    setExpandedRuns(prev => {
      const newSet = new Set(prev);
      if (newSet.has(runId)) {
        newSet.delete(runId);
      } else {
        newSet.add(runId);
      }
      return newSet;
    });
  }, []);

  // Handle run deletion
  const handleRunDeletion = useCallback((runId: string) => {
    setWorkflowRuns(prev => prev.filter(r => {
      const currentRunId = r.id || r.run_id;
      return currentRunId !== runId;
    }));

    setExpandedRuns(prev => {
      const newSet = new Set(prev);
      newSet.delete(runId);
      return newSet;
    });

    setTimeout(() => {
      loadWorkflowRuns();
    }, 100);
  }, [loadWorkflowRuns]);

  // Handle delete all workflow runs
  const handleDeleteAllRuns = useCallback(async () => {
    const runningRuns = workflowRuns.filter(run => ['running', 'initializing'].includes(run.status));
    if (runningRuns.length > 0) {
      showNotification(
        `Cannot delete ${runningRuns.length} workflow run${runningRuns.length > 1 ? 's' : ''} that are currently running`,
        'error'
      );
      return;
    }

    if (workflowRuns.length === 0) {
      showNotification('No workflow runs to delete', 'warning');
      return;
    }

    setIsDeletingAll(true);
    try {
      await workflowsApi.deleteAllRuns(workflowId);
      showNotification('All workflow runs have been deleted successfully', 'success');
      setWorkflowRuns([]);
      setExpandedRuns(new Set());
      await loadWorkflowRuns();
    } catch (err: unknown) {
      showNotification(getErrorMessage(err), 'error');
    } finally {
      setIsDeletingAll(false);
    }
  }, [workflowRuns, workflowId, showNotification, loadWorkflowRuns]);

  // Handle real-time workflow run updates
  const handleWorkflowRunUpdate = useCallback((message: AIOrchestrationMessage) => {
    let shouldUpdateTime = false;
    const eventType = message.event;
    const payload = message.payload;

    if (eventType === 'workflow_run_status_changed' ||
        eventType === 'workflow_run_update' ||
        eventType === 'metrics_update') {
      const workflowRun = payload as AiWorkflowRun;

      if (!workflowRun || !(workflowRun.id || workflowRun.run_id)) {
        return;
      }

      setWorkflowRuns(prevRuns => {
        const runIndex = prevRuns.findIndex(run =>
          run.id === (workflowRun.id || workflowRun.run_id) || run.run_id === workflowRun.run_id
        );

        if (runIndex >= 0) {
          const existingRun = prevRuns[runIndex];
          const hasChanges = existingRun.status !== workflowRun.status ||
                           existingRun.completed_nodes !== (workflowRun.completed_nodes || existingRun.completed_nodes) ||
                           existingRun.total_nodes !== (workflowRun.total_nodes || existingRun.total_nodes) ||
                           existingRun.cost_usd !== (workflowRun.cost_usd || existingRun.cost_usd);

          if (hasChanges) {
            const newRuns = [...prevRuns];
            newRuns[runIndex] = { ...existingRun, ...workflowRun };
            shouldUpdateTime = true;
            return newRuns;
          }
          return prevRuns;
        } else if (eventType === 'workflow_run_update') {
          shouldUpdateTime = true;
          return [workflowRun, ...prevRuns];
        }
        return prevRuns;
      });
    }

    if (eventType === 'node_execution_update') {
      const nodeExecution = payload as Record<string, unknown>;
      if (!nodeExecution) return;

      const runId = nodeExecution.workflow_run_id || nodeExecution.ai_workflow_run_id || nodeExecution.run_id;
      if (!runId) return;

      setWorkflowRuns(prevRuns => {
        const newRuns = prevRuns.map(run => {
          if (run.id === runId || run.run_id === runId) {
            const updatedRun = { ...run };

            if (nodeExecution.status === 'completed' || nodeExecution.status === 'failed') {
              updatedRun.last_node_update = new Date().toISOString();
              shouldUpdateTime = true;
            }

            return updatedRun;
          }
          return run;
        });

        return shouldUpdateTime ? newRuns : prevRuns;
      });
    }
  }, []);

  // Register a reload callback for each expanded run item
  const registerReloadCallback = useCallback((runId: string, callback: () => void) => {
    reloadCallbacksRef.current.set(runId, callback);
    return () => {
      reloadCallbacksRef.current.delete(runId);
    };
  }, []);

  // Get or create stable toggle handler
  const getToggleHandler = useCallback((runId: string) => {
    if (!handlersRef.current.toggle.has(runId)) {
      handlersRef.current.toggle.set(runId, () => toggleRunExpansion(runId));
    }
    return handlersRef.current.toggle.get(runId)!;
  }, [toggleRunExpansion]);

  // Get or create stable delete handler
  const getDeleteHandler = useCallback((runId: string) => {
    if (!handlersRef.current.delete.has(runId)) {
      handlersRef.current.delete.set(runId, () => handleRunDeletion(runId));
    }
    return handlersRef.current.delete.get(runId)!;
  }, [handleRunDeletion]);

  // Keep ref in sync with state
  useEffect(() => {
    expandedRunsRef.current = expandedRuns;
  }, [expandedRuns]);

  // Handle tab switching
  useEffect(() => {
    const now = Date.now();

    if (activeTab === 'history' && previousActiveTabRef.current !== 'history') {
      if (expandedRunsRef.current.size > 0) {
        setExpandedRuns(new Set());
      }
      lastReloadTimeRef.current = now;
    }

    previousActiveTabRef.current = activeTab;
  }, [activeTab]);

  // Automatic state reconciliation - sync with backend every 30 seconds
  useEffect(() => {
    if (!isOpen || !workflowId) return;

    const reconciliationInterval = setInterval(() => {
      setWorkflowRuns(currentRuns => {
        const hasActiveRuns = currentRuns.some(run =>
          run.status === 'running' || run.status === 'initializing'
        );

        if (activeTab === 'history' && hasActiveRuns && !loadingRef.current) {
          loadWorkflowRuns();
        }
        return currentRuns;
      });
    }, 30000);

    return () => clearInterval(reconciliationInterval);
  }, [isOpen, workflowId, activeTab, loadWorkflowRuns]);

  // Stale data detection
  useEffect(() => {
    if (!isOpen) return;

    const STALE_THRESHOLD = 30 * 60 * 1000;
    const CHECK_INTERVAL = 60 * 1000;

    const staleCheckInterval = setInterval(() => {
      const now = Date.now();

      setWorkflowRuns(currentRuns => {
        if (currentRuns.length === 0) return currentRuns;

        const staleRuns = currentRuns.filter(run => {
          if (run.status !== 'running' && run.status !== 'initializing') return false;
          const createdAt = new Date(run.created_at || run.started_at || Date.now()).getTime();
          return (now - createdAt) > STALE_THRESHOLD;
        });

        if (staleRuns.length > 0) {
          showNotification(
            `Detected ${staleRuns.length} stale workflow run${staleRuns.length > 1 ? 's' : ''}. Refreshing from server...`,
            'warning'
          );

          setTimeout(() => {
            if (!loadingRef.current) {
              loadWorkflowRuns();
            }
          }, 1000);

          return currentRuns.map(run => {
            if (staleRuns.find(stale => stale.id === run.id)) {
              return {
                ...run,
                status: 'failed',
                error_details: {
                  error_message: 'Workflow execution timed out or connection lost. Please refresh to see actual status.',
                  stale_detection: true
                }
              };
            }
            return run;
          });
        }

        return currentRuns;
      });
    }, CHECK_INTERVAL);

    return () => clearInterval(staleCheckInterval);
  }, [isOpen, showNotification, loadWorkflowRuns]);

  return {
    workflowRuns,
    runsLoading,
    runsError,
    expandedRuns,
    isDeletingAll,
    loadWorkflowRuns,
    setWorkflowRuns,
    toggleRunExpansion,
    handleRunDeletion,
    handleDeleteAllRuns,
    setExpandedRuns,
    handleWorkflowRunUpdate,
    registerReloadCallback,
    getToggleHandler,
    getDeleteHandler
  };
};
