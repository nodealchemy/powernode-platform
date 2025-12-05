import React, { useState, useEffect } from 'react';
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
  Edit
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
import { AiWorkflow } from '@/shared/types/workflow';
import { WorkflowExecutionForm } from './WorkflowExecutionForm';
import { sortNodesInExecutionOrder, formatNodeType, getNodeExecutionLevels } from '@/shared/utils/workflowUtils';

export interface WorkflowDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  workflowId: string;
}

export const WorkflowDetailModal: React.FC<WorkflowDetailModalProps> = ({
  isOpen,
  onClose,
  workflowId
}) => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();
  const { isConnected } = useWebSocket();

  const [workflow, setWorkflow] = useState<AiWorkflow | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<string>('overview');
  const [showExecutionForm, setShowExecutionForm] = useState(false);
  const [isExecutionInProgress] = useState(false);
  const [lastUpdateTime, setLastUpdateTime] = useState(new Date());

  // Edit mode state
  const [isEditMode, setIsEditMode] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [editedWorkflow, setEditedWorkflow] = useState<Partial<AiWorkflow>>({});

  // Check permissions
  const canExecuteWorkflows = currentUser?.permissions?.includes('ai.workflows.execute') || false;
  const canUpdateWorkflows = currentUser?.permissions?.includes('ai.workflows.update') || false;

  // Load workflow details
  const loadWorkflow = async () => {
    if (!workflowId || !isOpen) return;

    try {
      setLoading(true);
      setError(null);
      const response = await workflowsApi.getWorkflow(workflowId);
      setWorkflow(response);
      setLastUpdateTime(new Date());
    } catch (error) {
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

  // eslint-disable-next-line react-hooks/exhaustive-deps -- Load when modal opens
  useEffect(() => {
    if (isOpen && workflowId) {
      loadWorkflow();
      // Reset to overview tab and edit mode when opening modal
      setActiveTab('overview');
      setIsEditMode(false);
      setEditedWorkflow({});
    }
  }, [isOpen, workflowId]);

  // Toggle edit mode
  const handleToggleEditMode = () => {
    if (isEditMode) {
      // Canceling edit - reset changes
      setEditedWorkflow({});
      setIsEditMode(false);
    } else {
      // Entering edit mode - initialize with current workflow values
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

      // Restructure data to match backend expectations
      const updateData: Record<string, any> = {
        name: editedWorkflow.name,
        description: editedWorkflow.description,
        status: editedWorkflow.status,
        visibility: editedWorkflow.visibility
      };

      // Tags go in metadata
      if (editedWorkflow.tags !== undefined) {
        updateData.metadata = {
          ...workflow.metadata,
          tags: editedWorkflow.tags
        };
      }

      // execution_mode and timeout_seconds go in configuration
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
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Update Failed',
        message: 'Failed to update workflow. Please try again.'
      });
    } finally {
      setIsSaving(false);
    }
  };



  // Handle showing execution form instead of direct execution
  const handleShowExecutionForm = () => {
    if (!workflow || !canExecuteWorkflows) return;
    setShowExecutionForm(true);
  };


  // Protected close handler - prevent accidental closes during execution
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

  // Modal footer with actions
  const footer = (
    <div className="flex justify-between items-center w-full">
      <div className="flex gap-3">
        <Button
          variant="outline"
          onClick={handleProtectedClose}
          disabled={isSaving}
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
            {canUpdateWorkflows && workflow && (
              <Button
                variant="outline"
                onClick={handleToggleEditMode}
              >
                <Edit className="h-4 w-4 mr-2" />
                Edit
              </Button>
            )}
            {canExecuteWorkflows && workflow?.status === 'active' && (
              <Button
                onClick={handleShowExecutionForm}
                className="bg-theme-success hover:bg-theme-success/80"
              >
                <Play className="h-4 w-4 mr-2" />
                Execute
              </Button>
            )}
          </>
        )}
      </div>
    </div>
  );

  // Loading state
  if (loading || !workflow) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={handleProtectedClose}
        title="Loading Workflow..."
        maxWidth="5xl"
        icon={<Workflow />}
        footer={
          <Button variant="outline" onClick={handleProtectedClose}>
            Close
          </Button>
        }
      >
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary"></div>
        </div>
      </Modal>
    );
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
                        onChange={(value) => setEditedWorkflow({ ...editedWorkflow, status: value as any })}
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
                        onChange={(value) => setEditedWorkflow({ ...editedWorkflow, visibility: value as any })}
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
                      // Sort nodes in execution order
                      const sortedNodes = sortNodesInExecutionOrder(workflow.nodes, workflow.edges);
                      const executionLevels = getNodeExecutionLevels(workflow.nodes, workflow.edges);

                      return sortedNodes.map((node, index) => {
                        const isLast = index === sortedNodes.length - 1;
                        const executionLevel = executionLevels.get(node.node_id) || 0;

                        return (
                          <div key={node.id} className="relative">
                            {/* Connection line to next node */}
                            {!isLast && (
                              <div className="absolute left-6 top-12 bottom-0 w-0.5 bg-theme-border" />
                            )}

                            <div className="flex items-start gap-3">
                              {/* Execution order indicator */}
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

                              {/* Node details */}
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

                                    {/* Show connections */}
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

                                    {/* Node configuration details */}
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

                                  {/* Node type badge */}
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

                                    {/* Execution position */}
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
                      onChange={(value) => setEditedWorkflow({ ...editedWorkflow, execution_mode: value as any })}
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
                        } catch (error) {
                          // Keep invalid JSON in state for user to fix
                          setEditedWorkflow({ ...editedWorkflow, configuration: e.target.value as any });
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
        </Tabs>
      </div>


      {/* Workflow Execution Form Modal */}
      {workflow && (
        <WorkflowExecutionForm
          workflow={workflow}
          isOpen={showExecutionForm}
          onClose={() => setShowExecutionForm(false)}
        />
      )}
    </Modal>
  );
};