import { useState, useEffect, useCallback } from 'react';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { workflowsApi } from '@/shared/services/ai';
import { AiWorkflow, AIOrchestrationMessage } from '@/shared/types/workflow';
import { getErrorMessage } from '@/shared/utils/typeGuards';
import { logger } from '@/shared/utils/logger';
import { useWorkflowDetail } from '../hooks/useWorkflowDetail';
import { useWorkflowRuns } from '../hooks/useWorkflowRuns';
import { parseInputToParameters } from './workflow-detail';

export function useWorkflowDetailModal(workflowId: string, isOpen: boolean, initialTab: string) {
  const { currentUser } = useAuth();
  const { addNotification, showNotification } = useNotifications();
  const { isConnected, subscribe } = useWebSocket();

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

  const [isEditMode, setIsEditMode] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [editedWorkflow, setEditedWorkflow] = useState<Partial<AiWorkflow>>({});

  const [chatInput, setChatInput] = useState('');
  const [additionalParams, setAdditionalParams] = useState<Record<string, unknown>>({});
  const [isExecuting, setIsExecuting] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);

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

  const [showSummaryModal, setShowSummaryModal] = useState(false);
  const [showDeleteAllConfirm, setShowDeleteAllConfirm] = useState(false);

  const canExecuteWorkflows = currentUser?.permissions?.includes('ai.workflows.execute') || false;
  const canUpdateWorkflows = currentUser?.permissions?.includes('ai.workflows.update') || false;
  const canDeleteWorkflowRuns = currentUser?.permissions?.includes('ai.workflows.delete') || false;

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
  }, [isOpen, workflowId, initialTab]);

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
      logger.error('[WorkflowDetailModal] Failed to update workflow:', err);
      addNotification({
        type: 'error',
        title: 'Update Failed',
        message: 'Failed to update workflow. Please try again.'
      });
    } finally {
      setIsSaving(false);
    }
  }, [workflow, canUpdateWorkflows, editedWorkflow, setWorkflow, setLastUpdateTime, addNotification]);

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

  const handleProtectedClose = useCallback((onClose: () => void) => {
    if (isExecutionInProgress) {
      addNotification({
        type: 'info',
        title: 'Execution in Progress',
        message: 'Please wait for the workflow execution to complete before closing.'
      });
      return;
    }
    onClose();
  }, [isExecutionInProgress, addNotification]);

  const handleEditChange = useCallback((updates: Partial<AiWorkflow>) => {
    setEditedWorkflow(prev => ({ ...prev, ...updates }));
  }, []);

  return {
    workflow,
    loading,
    error,
    lastUpdateTime,
    loadWorkflow,
    isConnected,
    activeTab,
    setActiveTab,
    isEditMode,
    isSaving,
    editedWorkflow,
    chatInput,
    setChatInput,
    additionalParams,
    setAdditionalParams,
    isExecuting,
    showAdvanced,
    setShowAdvanced,
    workflowRuns,
    runsLoading,
    runsError,
    expandedRuns,
    isDeletingAll,
    loadWorkflowRuns,
    handleDeleteAllRuns,
    registerReloadCallback,
    getToggleHandler,
    getDeleteHandler,
    showSummaryModal,
    setShowSummaryModal,
    showDeleteAllConfirm,
    setShowDeleteAllConfirm,
    canExecuteWorkflows,
    canUpdateWorkflows,
    canDeleteWorkflowRuns,
    handleToggleEditMode,
    handleSaveWorkflow,
    handleExecute,
    handleProtectedClose,
    handleEditChange,
  };
}
