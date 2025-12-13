import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  Play,
  Eye,
  EyeOff,
  Calendar,
  Clock,
  User,
  Settings,
  Workflow,
  Wifi,
  WifiOff,
  GitBranch,
  CheckCircle,
  BarChart3,
  Edit,
  Send,
  Sparkles,
  History,
  TrendingUp,
  Trash2,
  AlertCircle
} from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Select } from '@/shared/components/ui/Select';
import { workflowsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { AiWorkflow, AiWorkflowRun, AIOrchestrationMessage } from '@/shared/types/workflow';
import { sortNodesInExecutionOrder, formatNodeType, getNodeExecutionLevels } from '@/shared/utils/workflowUtils';
import { getErrorMessage } from '@/shared/utils/typeGuards';
import { WorkflowExecutionDetails } from './WorkflowExecutionDetails';
import { WorkflowExecutionSummaryModal } from './WorkflowExecutionSummaryModal';

export interface WorkflowDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  workflowId: string;
  initialTab?: 'overview' | 'configuration' | 'nodes' | 'execute' | 'history';
}

export const WorkflowDetailModal: React.FC<WorkflowDetailModalProps> = ({
  isOpen,
  onClose,
  workflowId,
  initialTab = 'overview'
}) => {
  const { currentUser } = useAuth();
  const { addNotification, showNotification } = useNotifications();
  const { isConnected, subscribe } = useWebSocket();

  const [workflow, setWorkflow] = useState<AiWorkflow | null>(null);
  const [loading, setLoading] = useState(true); // Start as true to prevent flash
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<string>('overview');
  const [isExecutionInProgress] = useState(false);
  const [lastUpdateTime, setLastUpdateTime] = useState(new Date());

  // Edit mode state
  const [isEditMode, setIsEditMode] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [editedWorkflow, setEditedWorkflow] = useState<Partial<AiWorkflow>>({});

  // Execution state (moved from WorkflowExecutionForm)
  const [chatInput, setChatInput] = useState('');
  const [additionalParams, setAdditionalParams] = useState<Record<string, unknown>>({});
  const [isExecuting, setIsExecuting] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);

  // Workflow runs state (moved from WorkflowExecutionForm)
  const [workflowRuns, setWorkflowRuns] = useState<AiWorkflowRun[]>([]);
  const [runsLoading, setRunsLoading] = useState(false);
  const [runsError, setRunsError] = useState<string | null>(null);
  const [expandedRuns, setExpandedRuns] = useState<Set<string>>(new Set());
  const [showSummaryModal, setShowSummaryModal] = useState(false);
  const [showDeleteAllConfirm, setShowDeleteAllConfirm] = useState(false);
  const [isDeletingAll, setIsDeletingAll] = useState(false);
  const previousActiveTabRef = useRef<string>('overview');
  const expandedRunsRef = useRef<Set<string>>(new Set());
  const reloadCallbacksRef = useRef<Map<string, () => void>>(new Map());
  const lastReloadTimeRef = useRef<number>(Date.now());

  // Check permissions
  const canExecuteWorkflows = currentUser?.permissions?.includes('ai.workflows.execute') || false;
  const canUpdateWorkflows = currentUser?.permissions?.includes('ai.workflows.update') || false;
  const canDeleteWorkflowRuns = currentUser?.permissions?.includes('ai.workflows.delete') || false;

  // Request deduplication ref to prevent parallel calls
  const loadingRef = useRef(false);

  // Load workflow details
  const loadWorkflow = async () => {
    if (!workflowId || !isOpen) return;

    try {
      setLoading(true);
      setError(null);
      const response = await workflowsApi.getWorkflow(workflowId);
      setWorkflow(response);
      setLastUpdateTime(new Date());
    } catch (err) {
      setError('Failed to load workflow details. Please try again.');
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load workflow details'
      });
    } finally {
      setLoading(false);
    }
  };

  // Load workflow runs for execution history
  const loadWorkflowRuns = useCallback(async () => {
    if (!workflowId || !isOpen) return;

    // Prevent duplicate requests
    if (loadingRef.current) {
      return;
    }

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

  // eslint-disable-next-line react-hooks/exhaustive-deps -- Load when modal opens
  useEffect(() => {
    if (isOpen && workflowId) {
      // Reset loading state first to prevent flash
      setLoading(true);
      setWorkflow(null);
      setError(null);
      loadWorkflow();
      // Set to initial tab (from prop) and reset edit mode when opening modal
      setActiveTab(initialTab);
      setIsEditMode(false);
      setEditedWorkflow({});
      // Reset execution state
      setChatInput('');
      setAdditionalParams({});
      setShowAdvanced(false);
      // Reset runs state
      setExpandedRuns(new Set());
      loadWorkflowRuns();
    }
  }, [isOpen, workflowId, initialTab]);

  // Automatic state reconciliation - sync with backend every 30 seconds when modal is open
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, workflowId, activeTab]);

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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, showNotification]);

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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Subscribe to AiOrchestrationChannel for real-time updates
  useEffect(() => {
    if (!isOpen || !workflowId || !isConnected) return;

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'workflow', id: workflowId },
      onMessage: (message: unknown) => {
        handleWorkflowRunUpdate(message as AIOrchestrationMessage);
      }
    });

    return () => {
      unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, workflowId, isConnected, subscribe, handleWorkflowRunUpdate]);

  // Keep ref in sync with state
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
      setShowDeleteAllConfirm(false);

      await loadWorkflowRuns();
    } catch (err: unknown) {
      showNotification(getErrorMessage(err), 'error');
    } finally {
      setIsDeletingAll(false);
    }
  }, [workflowRuns, workflowId, showNotification, loadWorkflowRuns]);

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

  // Toggle edit mode
  const handleToggleEditMode = () => {
    if (isEditMode) {
      setEditedWorkflow({});
      setIsEditMode(false);
    } else {
      setEditedWorkflow({
        name: workflow?.name,
        description: workflow?.description,
        status: workflow?.status,
        visibility: workflow?.visibility,
        tags: workflow?.tags,
        execution_mode: workflow?.execution_mode,
        timeout_seconds: workflow?.timeout_seconds,
        configuration: workflow?.configuration
      });
      setIsEditMode(true);
    }
  };

  // Save workflow changes
  const handleSaveWorkflow = async () => {
    if (!workflow || !canUpdateWorkflows) return;

    try {
      setIsSaving(true);

      const updateData: Record<string, unknown> = {
        name: editedWorkflow.name,
        description: editedWorkflow.description,
        status: editedWorkflow.status,
        visibility: editedWorkflow.visibility
      };

      if (editedWorkflow.tags !== undefined) {
        updateData.metadata = {
          ...workflow.metadata,
          tags: editedWorkflow.tags
        };
      }

      if (editedWorkflow.execution_mode || editedWorkflow.timeout_seconds || editedWorkflow.configuration) {
        updateData.configuration = {
          ...workflow.configuration,
          ...(editedWorkflow.execution_mode && { execution_mode: editedWorkflow.execution_mode }),
          ...(editedWorkflow.timeout_seconds && { timeout_seconds: editedWorkflow.timeout_seconds }),
          ...(editedWorkflow.configuration && typeof editedWorkflow.configuration === 'object' && editedWorkflow.configuration)
        };
      }

      const response = await workflowsApi.updateWorkflow(workflow.id, updateData);

      setWorkflow(response);
      setIsEditMode(false);
      setEditedWorkflow({});
      setLastUpdateTime(new Date());

      addNotification({
        type: 'success',
        title: 'Workflow Updated',
        message: 'Workflow has been updated successfully.'
      });
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Update Failed',
        message: 'Failed to update workflow. Please try again.'
      });
    } finally {
      setIsSaving(false);
    }
  };

  // Parse chat input to extract parameters
  const parseInputToParameters = (input: string): Record<string, unknown> => {
    const params: Record<string, unknown> = {};

    if (workflow?.name.toLowerCase().includes('blog')) {
      params.topic = input;

      if (input.toLowerCase().includes('developer') || input.toLowerCase().includes('technical')) {
        params.target_audience = 'technical team';
      } else if (input.toLowerCase().includes('business') || input.toLowerCase().includes('executive')) {
        params.target_audience = 'business audience';
      } else {
        params.target_audience = 'general audience';
      }

      if (input.toLowerCase().includes('short') || input.toLowerCase().includes('brief')) {
        params.post_length = 'short';
      } else if (input.toLowerCase().includes('long') || input.toLowerCase().includes('detailed')) {
        params.post_length = 'long';
      } else {
        params.post_length = 'medium';
      }
    } else {
      params.input = input;
      params.prompt = input;
    }

    return params;
  };

  // Handle workflow execution
  const handleExecute = async () => {
    if (!workflow) return;

    if (!chatInput.trim() && Object.keys(additionalParams).length === 0) {
      showNotification('Please provide input for the workflow', 'warning');
      return;
    }

    setIsExecuting(true);

    try {
      const parsedParams = parseInputToParameters(chatInput);
      setChatInput('');

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

      setActiveTab('history');
      await loadWorkflowRuns();
    } catch (err: unknown) {
      showNotification(getErrorMessage(err), 'error');
    } finally {
      setIsExecuting(false);
    }
  };

  // Protected close handler
  const handleProtectedClose = () => {
    if (isExecutionInProgress) {
      addNotification({
        type: 'info',
        title: 'Execution in Progress',
        message: 'Please wait for the workflow execution to complete before closing.'
      });
      return;
    }
    onClose();
  };

  // Status badge rendering
  const renderStatusBadge = (status: string) => {
    const statusConfig = {
      draft: { variant: 'warning' as const, label: 'Draft' },
      active: { variant: 'success' as const, label: 'Active' },
      inactive: { variant: 'secondary' as const, label: 'Inactive' },
      archived: { variant: 'secondary' as const, label: 'Archived' },
      paused: { variant: 'info' as const, label: 'Paused' }
    };

    const config = statusConfig[status as keyof typeof statusConfig] || statusConfig.draft;

    return (
      <Badge variant={config.variant} size="sm">
        {config.label}
      </Badge>
    );
  };

  // Visibility badge rendering
  const renderVisibilityBadge = (visibility: string) => {
    const visibilityConfig = {
      private: { icon: EyeOff, label: 'Private' },
      account: { icon: User, label: 'Account' },
      public: { icon: Eye, label: 'Public' }
    };

    const config = visibilityConfig[visibility as keyof typeof visibilityConfig] || visibilityConfig.private;
    const IconComponent = config.icon;

    return (
      <div className="flex items-center gap-1 text-sm text-theme-muted">
        <IconComponent className="h-3 w-3" />
        {config.label}
      </div>
    );
  };

  const suggestedPrompts = [
    "Write a blog post about the future of AI",
    "Create content about sustainable technology",
    "Explain cloud computing for beginners",
    "Discuss cybersecurity best practices"
  ];

  // Modal footer with actions
  const footer = (
    <div className="flex justify-between items-center w-full">
      <div className="flex gap-3">
        <Button
          variant="outline"
          onClick={handleProtectedClose}
          disabled={isSaving || isExecuting}
        >
          Close
        </Button>
      </div>

      <div className="flex gap-3">
        {isEditMode ? (
          <>
            <Button
              variant="outline"
              onClick={handleToggleEditMode}
              disabled={isSaving}
            >
              Cancel
            </Button>
            <Button
              onClick={handleSaveWorkflow}
              disabled={isSaving}
              className="bg-theme-success hover:bg-theme-success/80"
            >
              {isSaving ? 'Saving...' : 'Save Changes'}
            </Button>
          </>
        ) : (
          <>
            {canUpdateWorkflows && workflow && activeTab === 'overview' && (
              <Button
                variant="outline"
                onClick={handleToggleEditMode}
              >
                <Edit className="h-4 w-4 mr-2" />
                Edit
              </Button>
            )}
          </>
        )}
      </div>
    </div>
  );

  // Don't render modal until workflow data is loaded
  if (loading || !workflow) {
    return null;
  }

  // Error state
  if (error) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={handleProtectedClose}
        title="Error Loading Workflow"
        maxWidth="md"
        icon={<Workflow />}
        footer={
          <Button variant="outline" onClick={handleProtectedClose}>
            Close
          </Button>
        }
      >
        <div className="text-center py-8">
          <p className="text-theme-error">{error}</p>
          <Button
            variant="outline"
            onClick={loadWorkflow}
            className="mt-4"
          >
            Try Again
          </Button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleProtectedClose}
      title={
        <div className="flex items-center gap-3">
          <span>{workflow.name}</span>
          <div className="flex items-center gap-1">
            {isConnected ? (
              <Wifi className="h-4 w-4 text-theme-success" aria-label="Live updates active" />
            ) : (
              <WifiOff className="h-4 w-4 text-theme-muted" aria-label="Live updates inactive" />
            )}
            <span className="text-xs text-theme-muted">
              {isConnected ? 'Live' : 'Offline'}
            </span>
          </div>
        </div>
      }
      subtitle={
        <div className="flex items-center justify-between">
          <span>{workflow.description}</span>
          <span className="text-xs text-theme-muted ml-4">
            Last updated: {lastUpdateTime.toLocaleTimeString()}
          </span>
        </div>
      }
      maxWidth="5xl"
      variant="centered"
      icon={<Workflow />}
      footer={footer}
      disableContentScroll={true}
    >
      <div className="space-y-6">
        {/* Header Stats */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Status</p>
                  {renderStatusBadge(workflow.status)}
                </div>
                <Settings className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Visibility</p>
                  {renderVisibilityBadge(workflow.visibility)}
                </div>
                <Eye className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Total Runs</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {workflow.stats?.runs_count || 0}
                  </p>
                </div>
                <BarChart3 className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Version</p>
                  <p className="text-lg font-semibold text-theme-primary">v{workflow.version}</p>
                </div>
                <Calendar className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Main Content Tabs */}
        <Tabs value={activeTab} onValueChange={setActiveTab} className="space-y-6">
          <TabsList className="w-full justify-start">
            <TabsTrigger value="overview">Basic Information</TabsTrigger>
            <TabsTrigger value="configuration">Configuration</TabsTrigger>
            <TabsTrigger value="nodes">Nodes ({workflow.stats?.nodes_count || 0})</TabsTrigger>
            {canExecuteWorkflows && workflow.status === 'active' && (
              <TabsTrigger value="execute" className="flex items-center whitespace-nowrap">
                <Sparkles className="h-4 w-4 mr-2 flex-shrink-0" />
                <span>Execute</span>
              </TabsTrigger>
            )}
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

          <TabsContent value="overview" className="space-y-6">
            <Card>

                <CardTitle>Basic Information</CardTitle>

              <CardContent className="space-y-4">
                <div>
                  <label className="text-sm font-medium text-theme-muted block mb-2">Name</label>
                  {isEditMode ? (
                    <Input
                      value={editedWorkflow.name || ''}
                      onChange={(e) => setEditedWorkflow({ ...editedWorkflow, name: e.target.value })}
                      placeholder="Workflow name"
                    />
                  ) : (
                    <p className="text-theme-primary">{workflow.name}</p>
                  )}
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-muted block mb-2">Description</label>
                  {isEditMode ? (
                    <Textarea
                      value={editedWorkflow.description || ''}
                      onChange={(e) => setEditedWorkflow({ ...editedWorkflow, description: e.target.value })}
                      placeholder="Workflow description"
                      rows={3}
                    />
                  ) : (
                    <p className="text-theme-primary">{workflow.description}</p>
                  )}
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label className="text-sm font-medium text-theme-muted block mb-2">Status</label>
                    {isEditMode ? (
                      <Select
                        value={editedWorkflow.status || workflow.status}
                        onChange={(value) => setEditedWorkflow({ ...editedWorkflow, status: value as AiWorkflow['status'] })}
                      >
                        <option value="draft">Draft</option>
                        <option value="active">Active</option>
                        <option value="inactive">Inactive</option>
                        <option value="archived">Archived</option>
                        <option value="paused">Paused</option>
                      </Select>
                    ) : (
                      <div className="mt-1">{renderStatusBadge(workflow.status)}</div>
                    )}
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted block mb-2">Visibility</label>
                    {isEditMode ? (
                      <Select
                        value={editedWorkflow.visibility || workflow.visibility}
                        onChange={(value) => setEditedWorkflow({ ...editedWorkflow, visibility: value as AiWorkflow['visibility'] })}
                      >
                        <option value="private">Private</option>
                        <option value="account">Account</option>
                        <option value="public">Public</option>
                      </Select>
                    ) : (
                      <p className="text-theme-primary capitalize">{workflow.visibility}</p>
                    )}
                  </div>
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-muted block mb-2">Tags</label>
                  {isEditMode ? (
                    <Input
                      value={editedWorkflow.tags?.join(', ') || ''}
                      onChange={(e) => setEditedWorkflow({
                        ...editedWorkflow,
                        tags: e.target.value.split(',').map(t => t.trim()).filter(Boolean)
                      })}
                      placeholder="Enter tags separated by commas"
                    />
                  ) : (
                    <div className="flex flex-wrap gap-2">
                      {workflow.tags && workflow.tags.length > 0 ? (
                        workflow.tags.map(tag => (
                          <Badge key={tag} variant="outline">
                            {tag}
                          </Badge>
                        ))
                      ) : (
                        <p className="text-theme-muted text-sm">No tags</p>
                      )}
                    </div>
                  )}
                </div>

                {!isEditMode && (
                  <>
                    <div className="border-t border-theme pt-4">
                      <label className="text-sm font-medium text-theme-muted">Created</label>
                      <p className="mt-1 text-theme-primary">
                        {workflow.created_at ? new Date(workflow.created_at).toLocaleDateString() : 'Unknown'} by{' '}
                        {workflow.created_by?.name || 'Unknown User'}
                      </p>
                    </div>

                    <div className="border-t border-theme pt-4">
                      <label className="text-sm font-medium text-theme-muted">Statistics</label>
                      <div className="grid grid-cols-2 gap-4 mt-2">
                        <div>
                          <p className="text-sm text-theme-muted">Total Nodes</p>
                          <p className="text-lg font-semibold text-theme-primary">
                            {workflow.stats?.nodes_count || 0}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-theme-muted">Total Runs</p>
                          <p className="text-lg font-semibold text-theme-primary">
                            {workflow.stats?.runs_count || 0}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-theme-muted">Success Rate</p>
                          <p className="text-lg font-semibold text-theme-primary">
                            {workflow.stats?.success_rate ? `${Math.round(workflow.stats.success_rate * 100)}%` : 'N/A'}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-theme-muted">Avg Runtime</p>
                          <p className="text-lg font-semibold text-theme-primary">
                            {workflow.stats?.avg_runtime ? `${workflow.stats.avg_runtime}s` : 'N/A'}
                          </p>
                        </div>
                      </div>
                    </div>
                  </>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="nodes" className="space-y-4">
            <Card>

                <CardTitle>Workflow Nodes (Execution Order)</CardTitle>

              <CardContent>
                {workflow.nodes && workflow.nodes.length > 0 ? (
                  <div className="space-y-3">
                    {(() => {
                      const sortedNodes = sortNodesInExecutionOrder(workflow.nodes, workflow.edges);
                      const executionLevels = getNodeExecutionLevels(workflow.nodes, workflow.edges);

                      return sortedNodes.map((node, index) => {
                        const isLast = index === sortedNodes.length - 1;
                        const executionLevel = executionLevels.get(node.node_id) || 0;

                        return (
                          <div key={node.id} className="relative">
                            {!isLast && (
                              <div className="absolute left-6 top-12 bottom-0 w-0.5 bg-theme-border" />
                            )}

                            <div className="flex items-start gap-3">
                              <div className="flex flex-col items-center">
                                <div className={`
                                  flex items-center justify-center w-12 h-12 rounded-full font-semibold text-sm
                                  ${node.is_start_node ? 'bg-theme-success text-white' :
                                    node.is_end_node ? 'bg-theme-info text-white' :
                                    'bg-theme-surface border-2 border-theme text-theme-primary'}
                                `}>
                                  {node.is_start_node ? (
                                    <Play className="h-5 w-5" />
                                  ) : node.is_end_node ? (
                                    <CheckCircle className="h-5 w-5" />
                                  ) : (
                                    index + 1
                                  )}
                                </div>
                              </div>

                              <div className="flex-1 p-4 border border-theme rounded-lg bg-theme-surface">
                                <div className="flex items-start justify-between gap-4">
                                  <div className="flex-1">
                                    <div className="flex items-center gap-2">
                                      <h4 className="font-medium text-theme-primary">{node.name}</h4>
                                      {node.is_start_node && (
                                        <Badge variant="success" size="sm">Start</Badge>
                                      )}
                                      {node.is_end_node && (
                                        <Badge variant="info" size="sm">End</Badge>
                                      )}
                                      {node.is_error_handler && (
                                        <Badge variant="danger" size="sm">Error Handler</Badge>
                                      )}
                                    </div>

                                    <div className="flex items-center gap-4 mt-2 text-sm text-theme-muted">
                                      <span className="flex items-center gap-1">
                                        <GitBranch className="h-3 w-3" />
                                        Type: {formatNodeType(node.node_type || 'unknown')}
                                      </span>
                                      {executionLevel > 0 && (
                                        <span className="flex items-center gap-1">
                                          Level: {executionLevel}
                                        </span>
                                      )}
                                    </div>

                                    {node.description && (
                                      <p className="text-sm text-theme-secondary mt-2">{node.description}</p>
                                    )}

                                    {workflow.edges && (() => {
                                      const outgoingEdges = workflow.edges.filter(e => e.source_node_id === node.node_id);
                                      const incomingEdges = workflow.edges.filter(e => e.target_node_id === node.node_id);

                                      return (outgoingEdges.length > 0 || incomingEdges.length > 0) && (
                                        <div className="flex gap-4 mt-3 text-xs text-theme-muted">
                                          {incomingEdges.length > 0 && (
                                            <span>← {incomingEdges.length} input{incomingEdges.length > 1 ? 's' : ''}</span>
                                          )}
                                          {outgoingEdges.length > 0 && (
                                            <span>→ {outgoingEdges.length} output{outgoingEdges.length > 1 ? 's' : ''}</span>
                                          )}
                                        </div>
                                      );
                                    })()}

                                    {node.timeout_seconds && (
                                      <div className="mt-2 text-xs text-theme-muted">
                                        <Clock className="inline h-3 w-3 mr-1" />
                                        Timeout: {node.timeout_seconds}s
                                      </div>
                                    )}
                                    {node.retry_count && node.retry_count > 0 && (
                                      <div className="mt-1 text-xs text-theme-muted">
                                        Retry: {node.retry_count} time{node.retry_count > 1 ? 's' : ''}
                                      </div>
                                    )}
                                  </div>

                                  <div className="flex flex-col items-end gap-2">
                                    <Badge
                                      variant={
                                        node.node_type === 'ai_agent' ? 'info' :
                                        node.node_type === 'api_call' ? 'warning' :
                                        node.node_type === 'human_approval' ? 'danger' :
                                        'outline'
                                      }
                                      size="sm"
                                    >
                                      {node.node_type || 'unknown'}
                                    </Badge>

                                    <span className="text-xs text-theme-muted">
                                      #{index + 1} of {sortedNodes.length}
                                    </span>
                                  </div>
                                </div>
                              </div>
                            </div>
                          </div>
                        );
                      });
                    })()}
                  </div>
                ) : (
                  <p className="text-theme-muted">No nodes configured for this workflow.</p>
                )}
              </CardContent>
            </Card>
          </TabsContent>


          <TabsContent value="configuration" className="space-y-4">
            <Card>

                <CardTitle>Workflow Configuration</CardTitle>

              <CardContent className="space-y-4">
                <div>
                  <label className="text-sm font-medium text-theme-muted block mb-2">Execution Mode</label>
                  {isEditMode ? (
                    <Select
                      value={editedWorkflow.execution_mode || workflow.execution_mode || 'sequential'}
                      onChange={(value) => setEditedWorkflow({ ...editedWorkflow, execution_mode: value as AiWorkflow['execution_mode'] })}
                    >
                      <option value="sequential">Sequential</option>
                      <option value="parallel">Parallel</option>
                      <option value="conditional">Conditional</option>
                    </Select>
                  ) : (
                    <p className="text-theme-primary capitalize">
                      {workflow.execution_mode || 'sequential'}
                    </p>
                  )}
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-muted block mb-2">Timeout (seconds)</label>
                  {isEditMode ? (
                    <Input
                      type="number"
                      value={editedWorkflow.timeout_seconds || workflow.timeout_seconds || ''}
                      onChange={(e) => setEditedWorkflow({ ...editedWorkflow, timeout_seconds: parseInt(e.target.value) || undefined })}
                      placeholder="3600"
                      min="1"
                    />
                  ) : (
                    <p className="text-theme-primary">
                      {workflow.timeout_seconds ? `${workflow.timeout_seconds} seconds` : 'Not set'}
                    </p>
                  )}
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-muted block mb-2">
                    Advanced Configuration (JSON)
                  </label>
                  {isEditMode ? (
                    <Textarea
                      value={editedWorkflow.configuration ? JSON.stringify(editedWorkflow.configuration, null, 2) : JSON.stringify(workflow.configuration || {}, null, 2)}
                      onChange={(e) => {
                        try {
                          const parsed = JSON.parse(e.target.value);
                          setEditedWorkflow({ ...editedWorkflow, configuration: parsed });
                        } catch (err) {
                          setEditedWorkflow({ ...editedWorkflow, configuration: e.target.value as unknown as Record<string, unknown> });
                        }
                      }}
                      rows={10}
                      className="font-mono text-xs"
                      placeholder="{}"
                    />
                  ) : (
                    <pre className="text-xs bg-theme-surface p-3 rounded border border-theme text-theme-primary overflow-x-auto">
                      {JSON.stringify(workflow.configuration || {}, null, 2)}
                    </pre>
                  )}
                  {isEditMode && (
                    <p className="text-xs text-theme-muted mt-1">
                      Enter valid JSON configuration. This is optional.
                    </p>
                  )}
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          {/* Execute Tab */}
          <TabsContent value="execute" className="space-y-4 animate-in fade-in-50 slide-in-from-bottom-2 duration-300">
            <Card>
              <CardContent className="space-y-4">
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
              </CardContent>
            </Card>
          </TabsContent>

          {/* Execution History Tab */}
          <TabsContent value="history" className="space-y-4 animate-in fade-in-50 slide-in-from-bottom-2 duration-300">
            <Card>
              <div className="flex items-center justify-between mb-4">
                <CardTitle>Recent Executions</CardTitle>
                <div className="flex items-center gap-3">
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
                {/* Loading overlay */}
                {runsLoading && (
                  <div className="absolute inset-0 bg-theme-surface/80 backdrop-blur-sm flex items-center justify-center z-10 rounded-lg transition-all duration-200 ease-in-out">
                    <div className="flex items-center gap-3">
                      <div className="animate-spin rounded-full h-6 w-6 border-2 border-theme-interactive-primary border-t-transparent"></div>
                      <span className="text-sm text-theme-muted">Loading execution history...</span>
                    </div>
                  </div>
                )}

                {/* Content */}
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
      </div>

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
