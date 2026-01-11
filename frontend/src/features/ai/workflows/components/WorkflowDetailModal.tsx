import React, { useState, useEffect, useCallback } from 'react';
import {
  Eye,
  Calendar,
  Settings,
  Workflow,
  Wifi,
  WifiOff,
  BarChart3,
  Edit,
  Sparkles,
  History,
  Trash2,
  AlertCircle
} from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { workflowsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { AiWorkflow, AIOrchestrationMessage } from '@/shared/types/workflow';
import { getErrorMessage } from '@/shared/utils/typeGuards';
import { WorkflowExecutionSummaryModal } from './WorkflowExecutionSummaryModal';
import { useWorkflowDetail } from '../hooks/useWorkflowDetail';
import { useWorkflowRuns } from '../hooks/useWorkflowRuns';
import {
  OverviewTab,
  ConfigurationTab,
  NodesTab,
  ExecuteTab,
  HistoryTab,
  renderStatusBadge,
  renderVisibilityBadge,
  parseInputToParameters
} from './workflow-detail';

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

  // Workflow data management
  const {
    workflow,
    loading,
    error,
    lastUpdateTime,
    loadWorkflow,
    setWorkflow,
    setLastUpdateTime
  } = useWorkflowDetail({ workflowId, isOpen });

  const [activeTab, setActiveTab] = useState<string>('overview');
  const [isExecutionInProgress] = useState(false);

  // Edit mode state
  const [isEditMode, setIsEditMode] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [editedWorkflow, setEditedWorkflow] = useState<Partial<AiWorkflow>>({});

  // Execution state
  const [chatInput, setChatInput] = useState('');
  const [additionalParams, setAdditionalParams] = useState<Record<string, unknown>>({});
  const [isExecuting, setIsExecuting] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);

  // Workflow runs management
  const {
    workflowRuns,
    runsLoading,
    runsError,
    expandedRuns,
    isDeletingAll,
    loadWorkflowRuns,
    setExpandedRuns,
    handleDeleteAllRuns,
    handleWorkflowRunUpdate,
    registerReloadCallback,
    getToggleHandler,
    getDeleteHandler
  } = useWorkflowRuns({ workflowId, isOpen, activeTab });

  // Modal state
  const [showSummaryModal, setShowSummaryModal] = useState(false);
  const [showDeleteAllConfirm, setShowDeleteAllConfirm] = useState(false);

  // Check permissions
  const canExecuteWorkflows = currentUser?.permissions?.includes('ai.workflows.execute') || false;
  const canUpdateWorkflows = currentUser?.permissions?.includes('ai.workflows.update') || false;
  const canDeleteWorkflowRuns = currentUser?.permissions?.includes('ai.workflows.delete') || false;

  // Reset state when modal opens
  useEffect(() => {
    if (isOpen && workflowId) {
      setActiveTab(initialTab);
      setIsEditMode(false);
      setEditedWorkflow({});
      setChatInput('');
      setAdditionalParams({});
      setShowAdvanced(false);
      setExpandedRuns(new Set());
      loadWorkflowRuns();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, workflowId, initialTab]);

  // Subscribe to WebSocket for real-time updates
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
  }, [isOpen, workflowId, isConnected, subscribe, handleWorkflowRunUpdate]);

  // Toggle edit mode
  const handleToggleEditMode = useCallback(() => {
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
  }, [isEditMode, workflow]);

  // Save workflow changes
  const handleSaveWorkflow = useCallback(async () => {
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
  }, [workflow, canUpdateWorkflows, editedWorkflow, setWorkflow, setLastUpdateTime, addNotification]);

  // Handle workflow execution
  const handleExecute = useCallback(async () => {
    if (!workflow) return;

    if (!chatInput.trim() && Object.keys(additionalParams).length === 0) {
      showNotification('Please provide input for the workflow', 'warning');
      return;
    }

    setIsExecuting(true);

    try {
      const parsedParams = parseInputToParameters(chatInput, workflow);
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
  }, [workflow, chatInput, additionalParams, showNotification, loadWorkflowRuns]);

  // Protected close handler
  const handleProtectedClose = useCallback(() => {
    if (isExecutionInProgress) {
      addNotification({
        type: 'info',
        title: 'Execution in Progress',
        message: 'Please wait for the workflow execution to complete before closing.'
      });
      return;
    }
    onClose();
  }, [isExecutionInProgress, addNotification, onClose]);

  // Handle edit changes
  const handleEditChange = useCallback((updates: Partial<AiWorkflow>) => {
    setEditedWorkflow(prev => ({ ...prev, ...updates }));
  }, []);

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
            <OverviewTab
              workflow={workflow}
              isEditMode={isEditMode}
              editedWorkflow={editedWorkflow}
              onEditChange={handleEditChange}
            />
          </TabsContent>

          <TabsContent value="nodes" className="space-y-4">
            <NodesTab workflow={workflow} />
          </TabsContent>

          <TabsContent value="configuration" className="space-y-4">
            <ConfigurationTab
              workflow={workflow}
              isEditMode={isEditMode}
              editedWorkflow={editedWorkflow}
              onEditChange={handleEditChange}
            />
          </TabsContent>

          <TabsContent value="execute" className="space-y-4 animate-in fade-in-50 slide-in-from-bottom-2 duration-300">
            <ExecuteTab
              workflow={workflow}
              chatInput={chatInput}
              additionalParams={additionalParams}
              isExecuting={isExecuting}
              showAdvanced={showAdvanced}
              onChatInputChange={setChatInput}
              onAdditionalParamsChange={setAdditionalParams}
              onToggleAdvanced={() => setShowAdvanced(!showAdvanced)}
              onExecute={handleExecute}
            />
          </TabsContent>

          <TabsContent value="history" className="space-y-4 animate-in fade-in-50 slide-in-from-bottom-2 duration-300">
            <HistoryTab
              workflowId={workflow.id}
              workflowRuns={workflowRuns}
              runsLoading={runsLoading}
              runsError={runsError}
              expandedRuns={expandedRuns}
              canDeleteWorkflowRuns={canDeleteWorkflowRuns}
              isDeletingAll={isDeletingAll}
              onShowSummaryModal={() => setShowSummaryModal(true)}
              onShowDeleteAllConfirm={() => setShowDeleteAllConfirm(true)}
              onLoadWorkflowRuns={loadWorkflowRuns}
              getToggleHandler={getToggleHandler}
              getDeleteHandler={getDeleteHandler}
              registerReloadCallback={registerReloadCallback}
            />
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
