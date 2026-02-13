import React, { useState, useEffect, useCallback } from 'react';
import { createPortal } from 'react-dom';
import {
  AlertCircle,
  Loader2,
  Trash2
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Modal } from '@/shared/components/ui/Modal';
import { workflowsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { AiWorkflowRun } from '@/shared/types/workflow';
import { getErrorMessage } from '@/shared/utils/typeGuards';
import {
  formatDuration,
  createExportData,
  downloadBlob
} from './execution/executionUtils';
import { useExecutionPolling } from './execution/useExecutionPolling';
import { ExecutionHeader } from './execution/ExecutionHeader';
import { NodeExecutionList } from './execution/NodeExecutionList';
import { ExecutionOutputPanel } from './execution/ExecutionOutputPanel';

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

  // Core data from polling hook
  const {
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
  } = useExecutionPolling({ run, workflowId, isExpanded, onRegisterReloadCallback });

  // UI state
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set());
  const [expandedInputs, setExpandedInputs] = useState<Set<string>>(new Set());
  const [expandedOutputs, setExpandedOutputs] = useState<Set<string>>(new Set());
  const [expandedMetadata, setExpandedMetadata] = useState<Set<string>>(new Set());
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [showPreviewModal, setShowPreviewModal] = useState(false);

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
    } catch (err) {
      addNotification({ type: 'error', title: 'Download Failed', message: getErrorMessage(err) });
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
    } catch (err) {
      addNotification({ type: 'error', title: 'Delete Failed', message: getErrorMessage(err) });
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

  const handlePreviewClick = useCallback(async () => {
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
  }, [run.run_id, run.id, workflowId, setCurrentRun]);

  return (
    <div className="border-l-2 border-theme ml-8">
      {/* Execution Header */}
      <ExecutionHeader
        currentRun={currentRun}
        runStatus={runStatus}
        isExpanded={isExpanded}
        isConnected={isConnected}
        lastUpdateReceived={lastUpdateReceived}
        onToggle={onToggle}
        onRefresh={loadExecutionDetails}
        onPreviewClick={handlePreviewClick}
        onDeleteClick={() => {
          if (runStatus === 'running' || runStatus === 'initializing') {
            addNotification({ type: 'warning', title: 'Cannot Delete', message: 'Cannot delete a workflow execution while it is running' });
            return;
          }
          setShowDeleteConfirm(true);
        }}
        onDownloadFromServer={downloadFromServer}
        onExportExecution={exportExecution}
      />

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
              <NodeExecutionList
                run={run}
                currentRun={currentRun}
                runStatus={runStatus}
                mergedNodes={mergedNodes}
                loading={loading}
                expandedNodes={expandedNodes}
                expandedInputs={expandedInputs}
                expandedOutputs={expandedOutputs}
                expandedMetadata={expandedMetadata}
                liveNodeDurations={liveNodeDurations}
                onToggleNode={toggleNodeExpansion}
                onToggleInput={toggleInputExpansion}
                onToggleOutput={toggleOutputExpansion}
                onToggleMetadata={toggleMetadataExpansion}
                onCopy={copyToClipboard}
              />
              <ExecutionOutputPanel
                run={run}
                currentRun={currentRun}
                onCopy={copyToClipboard}
                isPreviewOpen={showPreviewModal}
                onClosePreview={() => setShowPreviewModal(false)}
                onDownloadFromServer={downloadFromServer}
              />
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
    </div>
  );
};
