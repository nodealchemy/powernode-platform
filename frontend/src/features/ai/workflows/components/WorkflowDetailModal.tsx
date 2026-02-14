import React from 'react';
import {
  Workflow,
  Edit,
  Sparkles,
  History,
  Trash2,
  AlertCircle
} from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { WorkflowExecutionSummaryModal } from './WorkflowExecutionSummaryModal';
import { WorkflowModalHeader } from './WorkflowModalHeader';
import { useWorkflowDetailModal } from './useWorkflowDetailModal';
import {
  OverviewTab,
  ConfigurationTab,
  NodesTab,
  ExecuteTab,
  HistoryTab,
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
  const {
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
  } = useWorkflowDetailModal(workflowId, isOpen, initialTab);

  const onProtectedClose = () => handleProtectedClose(onClose);

  // Modal footer with actions
  const footer = (
    <div className="flex justify-between items-center w-full">
      <div className="flex gap-3">
        <Button
          variant="outline"
          onClick={onProtectedClose}
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

  if (loading || !workflow) {
    return null;
  }

  if (error) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onProtectedClose}
        title="Error Loading Workflow"
        maxWidth="md"
        icon={<Workflow />}
        footer={
          <Button variant="outline" onClick={onProtectedClose}>
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
      onClose={onProtectedClose}
      title={
        <WorkflowModalHeader
          workflow={workflow}
          isConnected={isConnected}
          lastUpdateTime={lastUpdateTime}
        />
      }
      maxWidth="5xl"
      variant="centered"
      icon={<Workflow />}
      footer={footer}
      disableContentScroll={true}
    >
      <div className="space-y-6">
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
                Are you sure you want to delete all workflow runs for &quot;{workflow.name}&quot;?
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
