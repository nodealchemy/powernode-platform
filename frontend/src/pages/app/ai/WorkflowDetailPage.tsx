import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Play,
  Edit,
  Download,
  Settings,
  Activity,
  CheckCircle,
  XCircle,
  Clock,
  AlertTriangle,
  Users,
  Calendar,
  DollarSign,
  BarChart3
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardTitle, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { workflowsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { AiWorkflow, AiWorkflowRun } from '@/shared/types/workflow';
import { NodeValidationPanel } from '@/features/ai-workflows/components/validation/NodeValidationPanel';
import { ValidationHistoryPanel } from '@/features/ai-workflows/components/validation/ValidationHistoryPanel';

export const WorkflowDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();
  const { isConnected, subscribe } = useWebSocket();

  const [workflow, setWorkflow] = useState<AiWorkflow | null>(null);
  const [loading, setLoading] = useState(true);
  const [workflowRuns, setWorkflowRuns] = useState<AiWorkflowRun[]>([]);
  const [runsLoading, setRunsLoading] = useState(false);

  // Check permissions
  const canExecuteWorkflows = currentUser?.permissions?.includes('ai.workflows.execute') || false;
  const canUpdateWorkflows = currentUser?.permissions?.includes('ai.workflows.update') || false;

  // Load workflow
  useEffect(() => {
    if (!id) return;

    const loadWorkflow = async () => {
      try {
        setLoading(true);
        const response = await workflowsApi.getWorkflow(id);
        setWorkflow(response);
      } catch (error) {
        console.error('Failed to load workflow:', error);
        addNotification({
          type: 'error',
          title: 'Error',
          message: 'Failed to load workflow. Please try again.'
        });
        navigate('/app/ai/workflows');
      } finally {
        setLoading(false);
      }
    };

    loadWorkflow();
  }, [id]); // Only depend on id, addNotification and navigate should be stable

  // Load workflow runs
  const loadWorkflowRuns = useCallback(async () => {
    if (!id) return;

    try {
      setRunsLoading(true);
      const response = await workflowsApi.getRuns(id, { workflow_id: id });
      setWorkflowRuns(response.items);
    } catch (error) {
      console.error('Failed to load workflow runs:', error);
    } finally {
      setRunsLoading(false);
    }
  }, [id]);

  useEffect(() => {
    loadWorkflowRuns();
  }, [loadWorkflowRuns]);

  // Subscribe to workflow run updates via WebSocket
  useEffect(() => {
    if (!id || !isConnected) return;

    const handleWorkflowUpdate = (message: any) => {
      // Extract event type (AiOrchestrationChannel uses 'event' field)
      const eventType = message.event || message.type;

      // Handle node execution updates - don't reload, progress updates via workflow messages
      if (eventType === 'node.execution.updated' || eventType === 'node.duration.updated') {
        return;
      }

      // Handle all workflow run update message types from backend
      const isWorkflowRunUpdate = [
        'workflow.run.status.changed',
        'workflow_run_status_changed',
        'workflow_progress_changed',
        'workflow_duration_update',
        'workflow_execution_started',
        'workflow_execution_completed',
        'workflow_execution_failed',
        'run_status_update'
      ].includes(eventType);

      if (isWorkflowRunUpdate) {
        // AiOrchestrationChannel wraps data in payload.workflow_run
        const updatedRun = message.payload?.workflow_run || message.workflow_run || message.data?.workflow_run;

        if (updatedRun) {
          setWorkflowRuns(prev => {
            const index = prev.findIndex(r => r.run_id === updatedRun.run_id || r.id === updatedRun.id);

            if (index >= 0) {
              // Update existing run - only update specific fields to avoid overwriting with incomplete data
              const updated = [...prev];
              const existingRun = updated[index];

              updated[index] = {
                ...existingRun,
                // Update status and progress fields
                status: updatedRun.status ?? existingRun.status,
                completed_nodes: updatedRun.completed_nodes ?? existingRun.completed_nodes,
                failed_nodes: updatedRun.failed_nodes ?? existingRun.failed_nodes,
                total_nodes: updatedRun.total_nodes ?? existingRun.total_nodes,
                // Update cost
                total_cost: updatedRun.cost_usd ?? updatedRun.total_cost ?? existingRun.total_cost,
                // Update timing - handle both duration_seconds and execution_time_ms
                execution_time_ms: updatedRun.duration_seconds
                  ? updatedRun.duration_seconds * 1000
                  : updatedRun.execution_time_ms ?? existingRun.execution_time_ms,
                // Update timestamps only if provided
                started_at: updatedRun.started_at ?? existingRun.started_at,
                completed_at: updatedRun.completed_at ?? existingRun.completed_at,
                // Update error details if provided
                error_details: updatedRun.error_details ?? existingRun.error_details
              };

              return updated;
            } else {
              // New run - add to list
              return [updatedRun, ...prev];
            }
          });
        }
      }
    };

    // Subscribe to AiOrchestrationChannel for workflow-level updates
    // This channel broadcasts all workflow run updates (new runs, status changes, etc.)
    const unsubscribeFn = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'workflow', id },
      onMessage: handleWorkflowUpdate
    });

    return () => {
      unsubscribeFn();
    };
  }, [id, isConnected, subscribe]);

  // Handle workflow execution
  const handleExecuteWorkflow = async () => {
    if (!workflow || !canExecuteWorkflows) return;

    try {
      const response = await workflowsApi.executeWorkflow(workflow.id, {
        trigger_type: 'manual',
        input_variables: {}
      });

      addNotification({
        type: 'success',
        title: 'Execution Started',
        message: `Workflow "${workflow.name}" has been started successfully.`
      });

      // Reload workflow runs to show the new execution
      await loadWorkflowRuns();

      // Navigate to execution monitoring
      navigate(`/app/ai/workflows/${workflow.id}/runs/${response.run_id}`);
    } catch (error) {
      console.error('Failed to execute workflow:', error);
      addNotification({
        type: 'error',
        title: 'Execution Failed',
        message: 'Failed to start workflow execution. Please try again.'
      });
    }
  };

  // Handle workflow validation
  const handleValidateWorkflow = async () => {
    if (!workflow) return;

    try {
      const response = await workflowsApi.validateWorkflow(workflow.id);
      
      if (response.valid) {
        addNotification({
          type: 'success',
          title: 'Validation Successful',
          message: 'Workflow structure is valid and ready for execution.'
        });
      } else {
        addNotification({
          type: 'warning',
          title: 'Validation Issues',
          message: `Found ${response.errors?.length || 0} errors and ${response.warnings?.length || 0} warnings.`
        });
      }
    } catch (error) {
      console.error('Failed to validate workflow:', error);
      addNotification({
        type: 'error',
        title: 'Validation Failed',
        message: 'Failed to validate workflow. Please try again.'
      });
    }
  };

  // Handle workflow export
  const handleExportWorkflow = async () => {
    if (!workflow) return;

    try {
      const response = await workflowsApi.exportWorkflow(workflow.id);
      
      // Create download
      const blob = new Blob([JSON.stringify(response.exportData, null, 2)], {
        type: 'application/json'
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = response.filename;
      a.click();
      URL.revokeObjectURL(url);

      addNotification({
        type: 'success',
        title: 'Export Complete',
        message: 'Workflow has been exported successfully.'
      });
    } catch (error) {
      console.error('Failed to export workflow:', error);
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export workflow. Please try again.'
      });
    }
  };

  // Status badge rendering
  const renderStatusBadge = (status: string) => {
    const statusConfig = {
      draft: { color: 'bg-theme-warning/10 text-theme-warning border-theme-warning/20', icon: Edit },
      published: { color: 'bg-theme-success/10 text-theme-success border-theme-success/20', icon: CheckCircle },
      archived: { color: 'bg-theme-secondary text-theme-muted border-theme-border', icon: XCircle },
      paused: { color: 'bg-theme-info/10 text-theme-info border-theme-info/20', icon: Clock }
    };

    const config = statusConfig[status as keyof typeof statusConfig] || statusConfig.draft;
    const IconComponent = config.icon;

    return (
      <Badge className={`${config.color} flex items-center gap-1`}>
        <IconComponent className="h-3 w-3" />
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </Badge>
    );
  };

  if (loading) {
    return (
      <PageContainer
        title="Loading..."
        description="Loading workflow details"
      >
        <div className="animate-pulse space-y-4">
          <div className="h-4 bg-theme-secondary rounded w-1/4"></div>
          <div className="h-4 bg-theme-secondary rounded w-1/2"></div>
          <div className="h-4 bg-theme-secondary rounded w-3/4"></div>
        </div>
      </PageContainer>
    );
  }

  if (!workflow) {
    return (
      <PageContainer
        title="Workflow Not Found"
        description="The requested workflow could not be found"
      >
        <Card>
          <CardContent className="text-center py-8">
            <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
            <h3 className="text-lg font-medium mb-2">Workflow Not Found</h3>
            <p className="text-theme-muted mb-4">
              The workflow you're looking for doesn't exist or you don't have permission to view it.
            </p>
            <Button onClick={() => navigate('/app/ai/workflows')}>
              Back to Workflows
            </Button>
          </CardContent>
        </Card>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={workflow.name}
      description={workflow.description}
      breadcrumbs={[
        { label: 'AI', href: '/app/ai' },
        { label: 'Workflows', href: '/app/ai/workflows' },
        { label: workflow.name }
      ]}
      actions={[
        {
          label: 'Validate',
          onClick: handleValidateWorkflow,
          icon: CheckCircle,
          variant: 'outline'
        },
        {
          label: 'Export',
          onClick: handleExportWorkflow,
          icon: Download,
          variant: 'outline'
        },
        ...(canUpdateWorkflows ? [{
          label: 'Edit',
          onClick: () => navigate(`/app/ai/workflows/${workflow.id}/edit`),
          icon: Edit,
          variant: 'outline' as const
        }] : []),
        ...(canExecuteWorkflows && workflow.status === 'active' ? [{
          label: 'Execute',
          onClick: handleExecuteWorkflow,
          icon: Play,
          variant: 'primary' as const
        }] : [])
      ]}
    >
      <div className="space-y-6">
        {/* Overview Cards */}
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
                  <p className="text-sm text-theme-muted">Nodes</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {workflow.stats?.nodes_count || workflow.nodes?.length || 0}
                  </p>
                </div>
                <Activity className="h-5 w-5 text-theme-muted" />
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

        {/* Main Content */}
        <Tabs defaultValue="overview" className="space-y-6">
          <TabsList className="w-full justify-start">
            <TabsTrigger value="overview">Overview</TabsTrigger>
            <TabsTrigger value="nodes">Nodes</TabsTrigger>
            <TabsTrigger value="runs">Execution History</TabsTrigger>
            <TabsTrigger value="validation">Validation</TabsTrigger>
            <TabsTrigger value="settings">Settings</TabsTrigger>
          </TabsList>

          <TabsContent value="overview" className="space-y-6">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <Card>

                  <CardTitle>Workflow Information</CardTitle>

                <CardContent className="space-y-4">
                  <div>
                    <label className="text-sm font-medium text-theme-muted">Description</label>
                    <p className="mt-1 text-theme-primary">{workflow.description}</p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Execution Mode</label>
                    <p className="mt-1 text-theme-primary capitalize">
                      {workflow.execution_mode || 'sequential'}
                    </p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Visibility</label>
                    <p className="mt-1 text-theme-primary capitalize">{workflow.visibility}</p>
                  </div>

                  {workflow.tags && workflow.tags.length > 0 && (
                    <div>
                      <label className="text-sm font-medium text-theme-muted">Tags</label>
                      <div className="mt-1 flex flex-wrap gap-1">
                        {workflow.tags.map(tag => (
                          <Badge key={tag} variant="outline" className="text-xs">
                            {tag}
                          </Badge>
                        ))}
                      </div>
                    </div>
                  )}
                </CardContent>
              </Card>

              <Card>

                  <CardTitle>Created By</CardTitle>

                <CardContent className="space-y-4">
                  <div className="flex items-center gap-3">
                    <div className="h-10 w-10 rounded-full bg-theme-secondary flex items-center justify-center">
                      <Users className="h-5 w-5 text-theme-muted" />
                    </div>
                    <div>
                      <p className="font-medium text-theme-primary">{workflow.created_by?.name || 'System Admin'}</p>
                      <p className="text-sm text-theme-muted">{workflow.created_by?.email || 'system@powernode.ai'}</p>
                    </div>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Created</label>
                    <p className="mt-1 text-theme-primary">
                      {workflow.created_at ? new Date(workflow.created_at).toLocaleDateString('en-US', {
                        year: 'numeric',
                        month: 'long',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit'
                      }) : 'No date'}
                    </p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Last Updated</label>
                    <p className="mt-1 text-theme-primary">
                      {workflow.updated_at ? new Date(workflow.updated_at).toLocaleDateString('en-US', {
                        year: 'numeric',
                        month: 'long',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit'
                      }) : 'No date'}
                    </p>
                  </div>
                </CardContent>
              </Card>
            </div>
          </TabsContent>

          <TabsContent value="nodes" className="space-y-4">
            <Card>

                <CardTitle>Workflow Nodes</CardTitle>

              <CardContent>
                {workflow.nodes && workflow.nodes.length > 0 ? (
                  <div className="space-y-4">
                    {workflow.nodes.map(node => (
                      <div key={node.id} className="border border-theme-border rounded-lg p-4">
                        <div className="flex items-start justify-between">
                          <div>
                            <h4 className="font-medium text-theme-primary">{node.name}</h4>
                            <p className="text-sm text-theme-muted">{node.description}</p>
                            <Badge variant="outline" className="mt-2">
                              {node.node_type ? node.node_type.replace('_', ' ') : 'Unknown Type'}
                            </Badge>
                          </div>
                          <div className="text-sm text-theme-muted">
                            Position: ({node.position_x}, {node.position_y})
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="text-center py-8 text-theme-muted">
                    <Activity className="h-12 w-12 mx-auto mb-4 opacity-50" />
                    <p>No nodes configured yet</p>
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="runs" className="space-y-4">
            <Card>
              <div className="flex flex-row items-center justify-between mb-4">
                <CardTitle>Execution History</CardTitle>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={loadWorkflowRuns}
                  disabled={runsLoading}
                >
                  {runsLoading ? 'Loading...' : 'Refresh'}
                </Button>
              </div>

              <CardContent>
                {runsLoading && workflowRuns.length === 0 ? (
                  <div className="text-center py-8 text-theme-muted">
                    <Activity className="h-8 w-8 mx-auto mb-2 animate-spin" />
                    <p>Loading execution history...</p>
                  </div>
                ) : workflowRuns.length === 0 ? (
                  <div className="text-center py-8 text-theme-muted">
                    <BarChart3 className="h-12 w-12 mx-auto mb-4 opacity-50" />
                    <p>No executions yet</p>
                    <p className="text-sm mt-2">Start your first workflow execution to see results here</p>
                  </div>
                ) : (
                  <div className="space-y-2">
                    {workflowRuns.map((run) => {
                      const progress = run.total_nodes && run.completed_nodes
                        ? Math.round((run.completed_nodes / run.total_nodes) * 100)
                        : 0;

                      const statusColor = {
                        completed: 'bg-theme-success',
                        failed: 'bg-theme-danger',
                        running: 'bg-theme-info',
                        initializing: 'bg-theme-warning',
                        pending: 'bg-theme-surface0',
                        cancelled: 'bg-theme-surface0',
                        paused: 'bg-theme-warning',
                        waiting_approval: 'bg-theme-interactive-primary'
                      }[run.status] || 'bg-theme-surface0';

                      const statusIcon = {
                        completed: CheckCircle,
                        failed: XCircle,
                        running: Activity,
                        initializing: Clock,
                        pending: Clock,
                        cancelled: XCircle,
                        paused: AlertTriangle,
                        waiting_approval: Users
                      }[run.status] || Clock;

                      const StatusIcon = statusIcon;

                      return (
                        <div
                          key={run.run_id}
                          className="flex items-center justify-between p-4 border border-theme rounded-lg hover:bg-theme-hover cursor-pointer transition-colors"
                          onClick={() => navigate(`/app/ai/workflows/${workflow.id}/runs/${run.run_id}`)}
                        >
                          <div className="flex items-center gap-4 flex-1">
                            <div className={`p-2 rounded-full ${statusColor} bg-opacity-10`}>
                              <StatusIcon className={`h-5 w-5 ${statusColor.replace('bg-', 'text-')}`} />
                            </div>

                            <div className="flex-1">
                              <div className="flex items-center gap-2">
                                <span className="font-medium text-theme-primary">Run #{run.run_id.slice(0, 8)}</span>
                                <Badge variant={run.status === 'completed' ? 'success' : run.status === 'failed' ? 'danger' : 'default'}>
                                  {run.status}
                                </Badge>
                              </div>

                              <div className="flex items-center gap-4 mt-1 text-sm text-theme-muted">
                                <span className="flex items-center gap-1">
                                  <Calendar className="h-3 w-3" />
                                  {new Date(run.created_at).toLocaleString()}
                                </span>
                                {run.triggered_by && (
                                  <span className="flex items-center gap-1">
                                    <Users className="h-3 w-3" />
                                    {run.triggered_by.name}
                                  </span>
                                )}
                              </div>

                              {run.total_nodes && run.total_nodes > 0 && (
                                <div className="mt-2">
                                  <div className="flex items-center justify-between text-xs text-theme-muted mb-1">
                                    <span>Progress: {run.completed_nodes || 0}/{run.total_nodes}</span>
                                    <span>{progress}%</span>
                                  </div>
                                  <div className="w-full bg-theme-muted bg-opacity-20 rounded-full h-1.5">
                                    <div
                                      className={`h-1.5 rounded-full transition-all ${statusColor}`}
                                      style={{ width: `${progress}%` }}
                                    />
                                  </div>
                                </div>
                              )}
                            </div>
                          </div>

                          <div className="flex items-center gap-4 text-sm">
                            {run.execution_time_ms && (
                              <div className="text-right">
                                <div className="text-theme-muted">Duration</div>
                                <div className="font-medium text-theme-primary">
                                  {run.execution_time_ms < 1000
                                    ? `${run.execution_time_ms}ms`
                                    : `${(run.execution_time_ms / 1000).toFixed(1)}s`}
                                </div>
                              </div>
                            )}

                            <div className="text-right">
                              <div className="text-theme-muted">Cost</div>
                              <div className="font-medium text-theme-primary flex items-center gap-1">
                                <DollarSign className="h-3 w-3" />
                                {run.total_cost.toFixed(4)}
                              </div>
                            </div>
                          </div>
                        </div>
                      );
                    })}

                    {workflowRuns.length >= 10 && (
                      <Button
                        variant="outline"
                        className="w-full"
                        onClick={() => navigate(`/app/ai/workflows/${workflow.id}/runs`)}
                      >
                        View All Runs
                      </Button>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="validation" className="space-y-6">
            <div className="space-y-6">
              {/* Workflow Validation Panel */}
              <NodeValidationPanel
                workflow={workflow}
                autoValidate={false}
              />

              {/* Validation History */}
              <Card>
                <CardTitle>Validation History</CardTitle>
                <CardContent>
                  <ValidationHistoryPanel workflowId={workflow.id} />
                </CardContent>
              </Card>
            </div>
          </TabsContent>

          <TabsContent value="settings" className="space-y-4">
            <Card>

                <CardTitle>Workflow Settings</CardTitle>

              <CardContent>
                <div className="space-y-4">
                  <div>
                    <label className="text-sm font-medium text-theme-muted">Timeout (seconds)</label>
                    <p className="mt-1 text-theme-primary">{workflow.timeout_seconds || 3600}</p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Max Execution Time</label>
                    <p className="mt-1 text-theme-primary">{workflow.max_execution_time || 'Not set'}</p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Cost Limit</label>
                    <p className="mt-1 text-theme-primary">
                      {workflow.cost_limit ? `$${workflow.cost_limit}` : 'Not set'}
                    </p>
                  </div>

                  {canUpdateWorkflows && (
                    <Button 
                      variant="outline"
                      onClick={() => navigate(`/app/ai/workflows/${workflow.id}/edit`)}
                    >
                      <Edit className="h-4 w-4 mr-2" />
                      Edit Settings
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </PageContainer>
  );
};