import React, { useState, useEffect, useCallback, useRef } from 'react';
import { AiWorkflow, AiWorkflowRun, AIOrchestrationMessage } from '@/shared/types/workflow';
import { getErrorMessage } from '@/shared/utils/typeGuards';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Modal } from '@/shared/components/ui/Modal';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { AlertCircle, Play, Send, Sparkles, History, TrendingUp, BarChart3, Trash2 } from 'lucide-react';
import { workflowsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { useAuth } from '@/shared/hooks/useAuth';
import { WorkflowExecutionDetails } from './WorkflowExecutionDetails';
import { WorkflowExecutionSummaryModal } from './WorkflowExecutionSummaryModal';

interface WorkflowExecutionFormProps {
  workflow: AiWorkflow;
  isOpen: boolean;
  onClose: () => void;
}

export const WorkflowExecutionForm: React.FC<WorkflowExecutionFormProps> = ({
  workflow,
  isOpen,
  onClose
}) => {
  const [chatInput, setChatInput] = useState('');
  const [additionalParams, setAdditionalParams] = useState<Record<string, unknown>>({});
  const [isExecuting, setIsExecuting] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [activeTab, setActiveTab] = useState<string>('execute');

  // Workflow runs state
  const [workflowRuns, setWorkflowRuns] = useState<AiWorkflowRun[]>([]);
  const [runsLoading, setRunsLoading] = useState(false);
  const [runsError, setRunsError] = useState<string | null>(null);
  const [expandedRuns, setExpandedRuns] = useState<Set<string>>(new Set());
  const [showSummaryModal, setShowSummaryModal] = useState(false);
  const [showDeleteAllConfirm, setShowDeleteAllConfirm] = useState(false);
  const [isDeletingAll, setIsDeletingAll] = useState(false);
  const previousActiveTabRef = useRef<string>('execute');
  const expandedRunsRef = useRef<Set<string>>(new Set());
  const reloadCallbacksRef = useRef<Map<string, () => void>>(new Map());
  const lastReloadTimeRef = useRef<number>(Date.now());

  const { showNotification } = useNotifications();
  const { isConnected, subscribe } = useWebSocket();
  const { currentUser } = useAuth();

  // Check permissions
  const canDeleteWorkflowRuns = currentUser?.permissions?.includes('ai.workflows.delete') || false;

  // Request deduplication ref to prevent parallel calls
  const loadingRef = useRef(false);

  // Load workflow runs for execution history
  const loadWorkflowRuns = useCallback(async () => {
    if (!workflow.id || !isOpen) return;

    // Prevent duplicate requests
    if (loadingRef.current) {
      return;
    }

    try {
      loadingRef.current = true;
      setRunsLoading(true);
      setRunsError(null);
      const response = await workflowsApi.getRuns(workflow.id, {
        page: 1,
        per_page: 10,
        sort_by: 'created_at',
        sort_order: 'desc'
      });
      setWorkflowRuns(response.items || []);
    } catch (error) {
      setRunsError('Failed to load execution history. Please try again.');
    } finally {
      setRunsLoading(false);
      loadingRef.current = false;
    }
  }, [workflow.id, isOpen]);

  // Load workflow runs when modal opens and ensure clean collapsed state
  useEffect(() => {
    if (isOpen && workflow.id) {
      // Always start with all runs collapsed for consistent UI
      setExpandedRuns(new Set());
      loadWorkflowRuns();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- Load when modal opens
  }, [isOpen, workflow.id]);

  // Automatic state reconciliation - sync with backend every 30 seconds when modal is open
  useEffect(() => {
    if (!isOpen || !workflow.id) return;

    const reconciliationInterval = setInterval(() => {
      // Only reconcile if we're on the history tab and have active runs
      // Use functional update to access current workflowRuns without dependency
      setWorkflowRuns(currentRuns => {
        const hasActiveRuns = currentRuns.some(run =>
          run.status === 'running' || run.status === 'initializing'
        );

        if (activeTab === 'history' && hasActiveRuns && !loadingRef.current) {
          loadWorkflowRuns();
        }
        return currentRuns; // No state change, just checking
      });
    }, 30000); // Every 30 seconds

    return () => clearInterval(reconciliationInterval);
    // IMPORTANT: Don't include workflowRuns or loadWorkflowRuns to prevent interval recreation
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, workflow.id, activeTab]);

  // Stale data detection - runs once per minute, checks for runs stuck >30 minutes
  useEffect(() => {
    if (!isOpen) return;

    const STALE_THRESHOLD = 30 * 60 * 1000; // 30 minutes
    const CHECK_INTERVAL = 60 * 1000; // Check every 60 seconds

    const staleCheckInterval = setInterval(() => {
      const now = Date.now();

      // Use functional update to access current workflowRuns without dependency
      setWorkflowRuns(currentRuns => {
        if (currentRuns.length === 0) return currentRuns;

        const staleRuns = currentRuns.filter(run => {
          if (run.status !== 'running' && run.status !== 'initializing') return false;
          const createdAt = new Date(run.created_at || run.started_at || Date.now()).getTime();
          return (now - createdAt) > STALE_THRESHOLD;
        });

        if (staleRuns.length > 0) {
          // Show notification to user
          showNotification(
            `Detected ${staleRuns.length} stale workflow run${staleRuns.length > 1 ? 's' : ''}. Refreshing from server...`,
            'warning'
          );

          // Refresh from server to get actual status
          setTimeout(() => {
            if (!loadingRef.current) {
              loadWorkflowRuns();
            }
          }, 1000);

          // Mark stale runs as failed locally until refresh completes
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, showNotification]);

  // Handle real-time workflow run updates - simplified for unified event format
  const handleWorkflowRunUpdate = useCallback((message: AIOrchestrationMessage) => {
    let shouldUpdateTime = false;

    // Extract event type from AiOrchestrationChannel format
    const eventType = message.event;
    const payload = message.payload;

    // Handle unified workflow run status changes
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
          // Update existing run
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
          // Add new run to the beginning
          shouldUpdateTime = true;
          return [workflowRun, ...prevRuns];
        }
        return prevRuns;
      });
    }

    // Handle node execution updates
    // Backend sends 'node_execution_update'
    if (eventType === 'node_execution_update') {
      const nodeExecution = payload as any;
      if (!nodeExecution) return;

      const runId = nodeExecution.workflow_run_id || nodeExecution.ai_workflow_run_id || nodeExecution.run_id;
      if (!runId) return;

      setWorkflowRuns(prevRuns => {
        const newRuns = prevRuns.map(run => {
          if (run.id === runId || run.run_id === runId) {
            // Update progress based on node executions
            const updatedRun = { ...run };

            // If node completed or failed, potentially update counts
            if (nodeExecution.status === 'completed') {
              updatedRun.last_node_update = new Date().toISOString();
              shouldUpdateTime = true;
            } else if (nodeExecution.status === 'failed') {
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
    // IMPORTANT: No dependencies to keep callback stable
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Subscribe to AiOrchestrationChannel for real-time updates
  useEffect(() => {
    if (!isOpen || !workflow.id || !isConnected) return;

    // Subscribe to workflow-level updates
    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'workflow', id: workflow.id },
      onMessage: (message: unknown) => {
        // Handle workflow run updates for this specific workflow
        handleWorkflowRunUpdate(message as AIOrchestrationMessage);
      }
    });

    return () => {
      unsubscribe();
    };
    // IMPORTANT: Don't include loadWorkflowRuns to prevent subscription recreation
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, workflow.id, isConnected, subscribe, handleWorkflowRunUpdate]);

  // Keep ref in sync with state to avoid capturing stale values
  useEffect(() => {
    expandedRunsRef.current = expandedRuns;
  }, [expandedRuns]);

  // Register a reload callback for each expanded run item
  const registerReloadCallback = useCallback((runId: string, callback: () => void) => {
    reloadCallbacksRef.current.set(runId, callback);
    return () => {
      reloadCallbacksRef.current.delete(runId);
    };
  }, []);

  // Handle tab switching - maintain collapsed state for clean UI
  useEffect(() => {
    const now = Date.now();

    // When switching to history tab, ensure clean collapsed state
    if (
      activeTab === 'history' &&
      previousActiveTabRef.current !== 'history'
    ) {
      // Maintain clean collapsed state - all runs start collapsed
      if (expandedRunsRef.current.size > 0) {
        // If there were any expanded runs, collapse them for clean view
        setExpandedRuns(new Set());
      }

      // Note: No need to reload since all runs are collapsed
      lastReloadTimeRef.current = now;
    }

    // Update the previous tab reference
    previousActiveTabRef.current = activeTab;
  }, [activeTab]);

  // Toggle run expansion - memoized to prevent re-renders
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

  // Handle run deletion - memoized to prevent re-renders
  const handleRunDeletion = useCallback((runId: string) => {
    // Remove the deleted run from the list (remove if either id or run_id matches)
    setWorkflowRuns(prev => prev.filter(r => {
      const currentRunId = r.id || r.run_id;
      return currentRunId !== runId;
    }));

    // Remove from expanded runs if it was expanded
    setExpandedRuns(prev => {
      const newSet = new Set(prev);
      newSet.delete(runId);
      return newSet;
    });

    // Optional: Refresh workflow runs from server to ensure consistency
    // This provides a fallback in case local state updates fail
    setTimeout(() => {
      loadWorkflowRuns();
    }, 100);
  }, []);

  // Handle delete all workflow runs
  const handleDeleteAllRuns = useCallback(async () => {
    // Check for running runs
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
      await workflowsApi.deleteAllRuns(workflow.id);

      showNotification('All workflow runs have been deleted successfully', 'success');

      // Clear local state
      setWorkflowRuns([]);
      setExpandedRuns(new Set());
      setShowDeleteAllConfirm(false);

      // Refresh to ensure consistency
      await loadWorkflowRuns();
    } catch (error: unknown) {
      showNotification(
        getErrorMessage(error),
        'error'
      );
    } finally {
      setIsDeletingAll(false);
    }
  }, [workflowRuns, workflow.id, showNotification, loadWorkflowRuns]);

  // Use ref to store handlers to prevent recreation
  const handlersRef = useRef<{
    toggle: Map<string, () => void>;
    delete: Map<string, () => void>;
  }>({
    toggle: new Map(),
    delete: new Map()
  });

  // Get or create stable handlers
  const getToggleHandler = useCallback((runId: string) => {
    if (!handlersRef.current.toggle.has(runId)) {
      handlersRef.current.toggle.set(runId, () => toggleRunExpansion(runId));
    }
    return handlersRef.current.toggle.get(runId)!;
  }, [toggleRunExpansion]);

  const getDeleteHandler = useCallback((runId: string) => {
    if (!handlersRef.current.delete.has(runId)) {
      handlersRef.current.delete.set(runId, () => handleRunDeletion(runId));
    }
    return handlersRef.current.delete.get(runId)!;
  }, [handleRunDeletion]);

  // Parse chat input to extract parameters
  const parseInputToParameters = (input: string): Record<string, unknown> => {
    const params: Record<string, unknown> = {};

    // Basic parsing - look for common patterns
    // Example: "Write a blog post about AI technology for developers"
    // Could extract: topic="AI technology", audience="developers"

    // For blog generation workflow specifically
    if (workflow.name.toLowerCase().includes('blog')) {
      params.topic = input;

      // Try to detect audience
      if (input.toLowerCase().includes('developer') || input.toLowerCase().includes('technical')) {
        params.target_audience = 'technical team';
      } else if (input.toLowerCase().includes('business') || input.toLowerCase().includes('executive')) {
        params.target_audience = 'business audience';
      } else {
        params.target_audience = 'general audience';
      }

      // Detect post length preference
      if (input.toLowerCase().includes('short') || input.toLowerCase().includes('brief')) {
        params.post_length = 'short';
      } else if (input.toLowerCase().includes('long') || input.toLowerCase().includes('detailed')) {
        params.post_length = 'long';
      } else {
        params.post_length = 'medium';
      }
    } else {
      // Generic parameter extraction
      params.input = input;
      params.prompt = input;
    }

    return params;
  };

  const handleExecute = async () => {
    if (!chatInput.trim() && Object.keys(additionalParams).length === 0) {
      showNotification('Please provide input for the workflow', 'warning');
      return;
    }

    setIsExecuting(true);

    try {
      // Parse chat input to parameters
      const parsedParams = parseInputToParameters(chatInput);

      // Clear input field immediately after capturing the input for execution
      setChatInput('');

      // Merge with additional parameters
      const inputVariables = {
        ...parsedParams,
        ...additionalParams
      };

      await workflowsApi.executeWorkflow(workflow.id, {
        input_variables: inputVariables,
        trigger_type: 'manual',
        trigger_context: {
          triggered_by: 'user',
          user_input: chatInput
        }
      });

      // Always switch to history tab after execution attempt
      setActiveTab('history');

      // Refresh the workflow runs to show the new execution
      await loadWorkflowRuns();

      // New runs start collapsed for clean UI experience

      // Don't close the modal - keep it open to show execution progress
    } catch (error: unknown) {
      showNotification(
        getErrorMessage(error),
        'error'
      );
    } finally {
      setIsExecuting(false);
    }
  };

  const suggestedPrompts = [
    "Write a blog post about the future of AI",
    "Create content about sustainable technology",
    "Explain cloud computing for beginners",
    "Discuss cybersecurity best practices"
  ];

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={
        <div className="flex items-center gap-2">
          <Sparkles className="h-5 w-5 text-theme-primary" />
          <span>Execute {workflow.name}</span>
        </div>
      }
      maxWidth="4xl"
      disableContentScroll={true}
    >
      <Tabs value={activeTab} onValueChange={setActiveTab} className="space-y-3 overflow-hidden">
        <TabsList className="w-full justify-start">
          <TabsTrigger value="execute" className="flex items-center whitespace-nowrap">
            <Sparkles className="h-4 w-4 mr-2 flex-shrink-0" />
            <span>Execute</span>
          </TabsTrigger>
          <TabsTrigger value="history" className="flex items-center whitespace-nowrap relative">
            <History className="h-4 w-4 mr-2 flex-shrink-0" />
            <span>Execution History</span>
            {workflowRuns.filter(run => ['running', 'initializing'].includes(run.status)).length > 0 && (
              <Badge
                variant="info"
                size="sm"
                className="ml-2 px-1.5 py-0 text-xs animate-pulse flex-shrink-0"
              >
                {workflowRuns.filter(run => ['running', 'initializing'].includes(run.status)).length}
              </Badge>
            )}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="execute" className="space-y-2 animate-in fade-in-50 slide-in-from-bottom-2 duration-300">
        {/* Main chat input */}
        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            What would you like to create?
          </label>
          <div className="relative">
            <Textarea
              value={chatInput}
              onChange={(e) => setChatInput(e.target.value)}
              placeholder="Describe what you want the workflow to do..."
              className="min-h-[100px] pr-12"
              onKeyDown={(e) => {
                if (e.key === 'Enter' && e.ctrlKey) {
                  handleExecute();
                }
              }}
            />
            <div className="absolute bottom-3 right-3">
              <Button
                size="sm"
                variant="ghost"
                onClick={handleExecute}
                disabled={isExecuting || !chatInput.trim()}
                title="Execute (Ctrl+Enter)"
              >
                <Send className="h-4 w-4" />
              </Button>
            </div>
          </div>
          <div className="text-xs text-theme-text-secondary mt-1">
            Press Ctrl+Enter to execute
          </div>
        </div>

        {/* Suggested prompts */}
        {suggestedPrompts.length > 0 && !chatInput && (
          <div>
            <label className="block text-xs font-medium text-theme-text-secondary mb-1">
              Suggestions:
            </label>
            <div className="flex flex-wrap gap-2">
              {suggestedPrompts.map((prompt, index) => (
                <button
                  key={index}
                  onClick={() => setChatInput(prompt)}
                  className="px-3 py-1.5 text-xs bg-theme-surface-secondary rounded-lg
                           text-theme-text-secondary hover:text-theme-text-primary
                           hover:bg-theme-surface-elevated transition-colors"
                >
                  {prompt}
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Advanced parameters */}
        <div>
          <button
            onClick={() => setShowAdvanced(!showAdvanced)}
            className="text-sm text-theme-primary hover:text-theme-primary-dark transition-colors"
          >
            {showAdvanced ? '− Hide' : '+ Show'} Advanced Options
          </button>

          {showAdvanced && (
            <div className="mt-2 p-3 bg-theme-surface-secondary rounded-lg space-y-2">
              <div className="text-sm text-theme-text-secondary mb-1">
                Add specific parameters for the workflow:
              </div>

              {/* Common workflow parameters */}
              {workflow.input_schema && Object.keys(workflow.input_schema).length > 0 ? (
                Object.entries(workflow.input_schema).map(([key, _schema]: [string, unknown]) => (
                  <div key={key}>
                    <label className="block text-sm font-medium text-theme-text-primary mb-1">
                      {key.charAt(0).toUpperCase() + key.slice(1).replace(/_/g, ' ')}
                    </label>
                    <Input
                      value={(additionalParams[key] as string) || ''}
                      onChange={(e) => setAdditionalParams({
                        ...additionalParams,
                        [key]: e.target.value
                      })}
                      placeholder={`Enter ${key}`}
                    />
                  </div>
                ))
              ) : (
                <>
                  <div>
                    <label className="block text-sm font-medium text-theme-text-primary mb-1">
                      Max Tokens
                    </label>
                    <Input
                      type="number"
                      value={(additionalParams.max_tokens as number) || ''}
                      onChange={(e) => setAdditionalParams({
                        ...additionalParams,
                        max_tokens: parseInt(e.target.value) || undefined
                      })}
                      placeholder="1500"
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-theme-text-primary mb-1">
                      Temperature
                    </label>
                    <Input
                      type="number"
                      step="0.1"
                      min="0"
                      max="2"
                      value={(additionalParams.temperature as number) || ''}
                      onChange={(e) => setAdditionalParams({
                        ...additionalParams,
                        temperature: parseFloat(e.target.value) || undefined
                      })}
                      placeholder="0.7"
                    />
                  </div>
                </>
              )}
            </div>
          )}
        </div>

        {/* Workflow info */}
        <div className="p-3 bg-theme-info/10 rounded-lg flex items-start gap-2">
          <AlertCircle className="h-4 w-4 text-theme-info mt-0.5" />
          <div className="text-sm text-theme-text-secondary">
            This workflow will process your input through {workflow.stats?.nodes_count || workflow.nodes?.length || 0} nodes
            {workflow.execution_mode && ` in ${workflow.execution_mode} mode`}.
          </div>
        </div>

        {/* Action buttons */}
        <div className="flex justify-end gap-3">
          <Button
            variant="outline"
            onClick={onClose}
            disabled={isExecuting}
          >
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleExecute}
            disabled={isExecuting || (!chatInput.trim() && Object.keys(additionalParams).length === 0)}
            className="transition-all duration-200 hover:scale-105 active:scale-95"
          >
            <div className="flex items-center">
              {isExecuting ? (
                <>
                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2" />
                  <span className="animate-in fade-in duration-200">Executing...</span>
                </>
              ) : (
                <>
                  <Play className="h-4 w-4 mr-2 transition-transform duration-200 group-hover:scale-110" />
                  <span>Execute Workflow</span>
                </>
              )}
            </div>
          </Button>
        </div>
        </TabsContent>

        <TabsContent value="history" className="space-y-2 animate-in fade-in-50 slide-in-from-bottom-2 duration-300">
          <Card>
            <div className="flex items-center justify-between mb-4">
              <CardTitle>Recent Executions</CardTitle>
                <div className="flex items-center gap-3">
                  {/* Debug info - temporary */}
                  {process.env.NODE_ENV === 'development' && (
                    <span className="text-xs text-theme-muted">
                      Runs: {workflowRuns?.length || 0} | Auth: {canDeleteWorkflowRuns ? 'Yes' : 'No'}
                    </span>
                  )}
                  {workflowRuns && workflowRuns.length > 0 && (
                    <>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => setShowSummaryModal(true)}
                        className="gap-2"
                      >
                        <TrendingUp className="h-4 w-4" />
                        View Summary
                      </Button>
                      {canDeleteWorkflowRuns && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => setShowDeleteAllConfirm(true)}
                          className="gap-2 text-theme-danger hover:text-theme-danger hover:border-theme-danger/30"
                          disabled={isDeletingAll}
                        >
                          <Trash2 className="h-4 w-4" />
                          Delete All
                        </Button>
                      )}
                    </>
                  )}
                  {runsLoading && (
                    <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-theme-interactive-primary"></div>
                  )}
                </div>
              </div>
            <CardContent className="relative">
              {/* Loading overlay for smooth transitions */}
              {runsLoading && (
                <div className="absolute inset-0 bg-theme-surface/80 backdrop-blur-sm flex items-center justify-center z-10 rounded-lg transition-all duration-200 ease-in-out">
                  <div className="flex items-center gap-3">
                    <div className="animate-spin rounded-full h-6 w-6 border-2 border-theme-interactive-primary border-t-transparent"></div>
                    <span className="text-sm text-theme-muted">Loading execution history...</span>
                  </div>
                </div>
              )}

              {/* Content with fade transitions */}
              <div className={`transition-all duration-300 ease-in-out ${runsLoading ? 'opacity-50' : 'opacity-100'}`}>
                {runsError ? (
                  <div className="text-center py-8 animate-in fade-in-50 duration-300">
                    <AlertCircle className="h-12 w-12 text-theme-error mx-auto mb-3 opacity-60" />
                    <p className="text-theme-error mb-4">{runsError}</p>
                    <Button
                      variant="outline"
                      onClick={loadWorkflowRuns}
                      className="transition-all duration-200"
                      disabled={runsLoading}
                    >
                      Try Again
                    </Button>
                  </div>
                ) : workflowRuns && workflowRuns.length > 0 ? (
                  <div className="space-y-1 animate-in fade-in-50 slide-in-from-top-2 duration-500">
                    {workflowRuns.map((run, index) => (
                      <div
                        key={run.id || run.run_id}
                        className="animate-in fade-in-50 slide-in-from-left-1 duration-300"
                        style={{ animationDelay: `${index * 50}ms` }}
                      >
                        <WorkflowExecutionDetails
                          run={run}
                          workflowId={workflow.id}
                          isExpanded={expandedRuns.has(run.id || run.run_id || '')}
                          onToggle={getToggleHandler(run.id || run.run_id || '')}
                          onDelete={getDeleteHandler(run.id || run.run_id || '')}
                          onRegisterReloadCallback={registerReloadCallback}
                        />
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="text-center py-12 animate-in fade-in-50 duration-500">
                    <BarChart3 className="h-16 w-16 text-theme-muted mx-auto mb-4 opacity-40" />
                    <p className="text-theme-muted text-lg mb-2">No execution history found</p>
                    <p className="text-theme-muted/70 text-sm">
                      Execute the workflow to see results here
                    </p>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Execution Summary Modal */}
      {workflow && (
        <WorkflowExecutionSummaryModal
          isOpen={showSummaryModal}
          onClose={() => setShowSummaryModal(false)}
          workflowId={workflow.id}
          workflowName={workflow.name}
        />
      )}

      {/* Delete All Confirmation Modal */}
      <Modal
        isOpen={showDeleteAllConfirm}
        onClose={() => setShowDeleteAllConfirm(false)}
        title="Delete All Workflow Runs"
        maxWidth="md"
        variant="centered"
      >
        <div className="space-y-4">
          <div className="flex items-start gap-3">
            <AlertCircle className="h-5 w-5 text-theme-warning mt-0.5" />
            <div className="flex-1">
              <p className="text-sm text-theme-primary font-medium">
                Are you sure you want to delete all workflow runs for "{workflow.name}"?
              </p>
              <p className="text-xs text-theme-muted mt-1">
                This will permanently delete all {workflowRuns.length} execution run{workflowRuns.length !== 1 ? 's' : ''} and their associated logs.
                This action cannot be undone.
              </p>
              {workflowRuns.some(run => ['running', 'initializing'].includes(run.status)) && (
                <p className="text-xs text-theme-warning mt-2 p-2 bg-theme-warning/10 rounded">
                  <strong>Note:</strong> Running executions cannot be deleted and will be skipped.
                </p>
              )}
            </div>
          </div>

          <div className="flex justify-end gap-3 pt-2">
            <Button
              variant="outline"
              onClick={() => setShowDeleteAllConfirm(false)}
              disabled={isDeletingAll}
            >
              Cancel
            </Button>
            <Button
              variant="danger"
              onClick={handleDeleteAllRuns}
              disabled={isDeletingAll}
            >
              {isDeletingAll ? (
                <>
                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2" />
                  Deleting...
                </>
              ) : (
                <>
                  <Trash2 className="h-4 w-4 mr-2" />
                  Delete All Runs
                </>
              )}
            </Button>
          </div>
        </div>
      </Modal>
    </Modal>
  );
};