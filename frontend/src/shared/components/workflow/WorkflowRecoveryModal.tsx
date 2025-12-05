import React, { useState, useEffect } from 'react';
import { RotateCcw, Save, RefreshCw, Play, AlertTriangle, CheckCircle, Info } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Card } from '@/shared/components/ui/Card';
import { api } from '@/shared/services/api';
import { useNotifications } from '@/shared/hooks/useNotifications';

export interface RecoveryOptions {
  checkpoint_recovery: {
    available: boolean;
    checkpoint_count: number;
    best_checkpoint: {
      id: string;
      checkpoint_type: string;
      sequence_number: number;
      age_seconds: number;
      metadata: {
        progress_percentage: number;
        cost_so_far: number;
      };
    } | null;
  };
  node_retry: {
    retryable_nodes: Array<{
      execution_id: string;
      node_name: string;
      error_message: string;
      retry_stats: {
        retryable: boolean;
        retries_remaining: number;
      };
    }>;
    failed_nodes: Array<{
      execution_id: string;
      node_name: string;
      error_message: string;
    }>;
  };
  workflow_restart: {
    available: boolean;
    preserve_progress: boolean;
  };
}

export interface WorkflowRecoveryModalProps {
  isOpen: boolean;
  onClose: () => void;
  workflowRunId: string;
  workflowName: string;
  onRecoveryInitiated?: (strategy: string) => void;
}

export const WorkflowRecoveryModal: React.FC<WorkflowRecoveryModalProps> = ({
  isOpen,
  onClose,
  workflowRunId,
  workflowName,
  onRecoveryInitiated
}) => {
  const { addNotification } = useNotifications();
  const [options, setOptions] = useState<RecoveryOptions | null>(null);
  const [loading, setLoading] = useState(true);
  const [recovering, setRecovering] = useState<string | null>(null);
  const [selectedStrategy, setSelectedStrategy] = useState<'checkpoint' | 'retry' | 'restart' | null>(null);

  useEffect(() => {
    if (isOpen) {
      loadRecoveryOptions();
    }
  }, [isOpen, workflowRunId]);

  const loadRecoveryOptions = async () => {
    try {
      setLoading(true);
      const response = await api.get(`/ai/workflow_runs/${workflowRunId}/recovery/options`);
      setOptions(response.data.data);

      // Auto-select best strategy
      if (response.data.data.checkpoint_recovery.available) {
        setSelectedStrategy('checkpoint');
      } else if (response.data.data.node_retry.retryable_nodes.length > 0) {
        setSelectedStrategy('retry');
      } else if (response.data.data.workflow_restart.available) {
        setSelectedStrategy('restart');
      }
    } catch (error) {
      console.error('Failed to load recovery options:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleCheckpointRecovery = async () => {
    try {
      setRecovering('checkpoint');
      await api.post(`/ai/workflow_runs/${workflowRunId}/recovery/checkpoint_recover`);
      onRecoveryInitiated?.('checkpoint');
      onClose();
    } catch (error) {
      console.error('Failed to recover from checkpoint:', error);
      addNotification({ type: 'error', message: 'Failed to recover from checkpoint. Please try again.' });
    } finally {
      setRecovering(null);
    }
  };

  const handleNodeRetry = async (nodeExecutionId: string) => {
    try {
      setRecovering(`retry-${nodeExecutionId}`);
      await api.post(`/ai/workflow_runs/${workflowRunId}/recovery/nodes/${nodeExecutionId}/retry`);
      await loadRecoveryOptions(); // Refresh to show updated state
    } catch (error) {
      console.error('Failed to retry node:', error);
      addNotification({ type: 'error', message: 'Failed to retry node. Please try again.' });
    } finally {
      setRecovering(null);
    }
  };

  const handleWorkflowRestart = async () => {
    if (!confirm('Are you sure you want to restart the workflow? This will discard all progress.')) {
      return;
    }

    try {
      setRecovering('restart');
      // Implement restart logic - this would typically call a workflow execution endpoint
      await api.post(`/ai/workflows/${workflowRunId}/execute`);
      onRecoveryInitiated?.('restart');
      onClose();
    } catch (error) {
      console.error('Failed to restart workflow:', error);
      addNotification({ type: 'error', message: 'Failed to restart workflow. Please try again.' });
    } finally {
      setRecovering(null);
    }
  };

  const formatAge = (seconds: number) => {
    if (seconds < 60) return `${seconds}s ago`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    return `${Math.floor(seconds / 3600)}h ago`;
  };

  if (!isOpen) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={
        <div className="flex items-center gap-2">
          <RotateCcw className="h-5 w-5 text-theme-interactive-primary" />
          <span>Workflow Recovery Options</span>
        </div>
      }
      size="lg"
    >
      <div className="space-y-4">
        {/* Workflow info */}
        <div className="p-3 bg-theme-background rounded-lg">
          <div className="text-sm text-theme-secondary">Workflow</div>
          <div className="text-lg font-medium text-theme-primary">{workflowName}</div>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-8">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary"></div>
          </div>
        ) : !options ? (
          <div className="text-center py-8">
            <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-3" />
            <p className="text-sm text-theme-secondary">Failed to load recovery options</p>
          </div>
        ) : (
          <div className="space-y-3">
            {/* Checkpoint Recovery */}
            <Card
              className={`p-4 cursor-pointer transition-colors ${
                selectedStrategy === 'checkpoint'
                  ? 'border-theme-interactive-primary bg-theme-interactive-primary/5'
                  : 'border-theme hover:border-theme-interactive-primary/50'
              } ${!options.checkpoint_recovery.available ? 'opacity-50 cursor-not-allowed' : ''}`}
              onClick={() => options.checkpoint_recovery.available && setSelectedStrategy('checkpoint')}
            >
              <div className="flex items-start gap-3">
                <div className={`p-2 rounded-lg ${
                  options.checkpoint_recovery.available ? 'bg-theme-success/10' : 'bg-theme-surface0/10'
                }`}>
                  <Save className={`h-5 w-5 ${
                    options.checkpoint_recovery.available ? 'text-theme-success' : 'text-theme-muted'
                  }`} />
                </div>

                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <h4 className="text-sm font-medium text-theme-primary">Checkpoint Recovery</h4>
                    {selectedStrategy === 'checkpoint' && (
                      <CheckCircle className="h-4 w-4 text-theme-interactive-primary" />
                    )}
                  </div>

                  <p className="text-xs text-theme-secondary mb-2">
                    Resume from the last successful checkpoint
                  </p>

                  {options.checkpoint_recovery.available && options.checkpoint_recovery.best_checkpoint ? (
                    <div className="grid grid-cols-3 gap-2 text-xs">
                      <div className="p-2 bg-theme-background rounded">
                        <div className="text-theme-muted">Checkpoint</div>
                        <div className="text-theme-primary font-medium">
                          #{options.checkpoint_recovery.best_checkpoint.sequence_number}
                        </div>
                      </div>
                      <div className="p-2 bg-theme-background rounded">
                        <div className="text-theme-muted">Progress</div>
                        <div className="text-theme-primary font-medium">
                          {options.checkpoint_recovery.best_checkpoint.metadata.progress_percentage.toFixed(1)}%
                        </div>
                      </div>
                      <div className="p-2 bg-theme-background rounded">
                        <div className="text-theme-muted">Age</div>
                        <div className="text-theme-primary font-medium">
                          {formatAge(options.checkpoint_recovery.best_checkpoint.age_seconds)}
                        </div>
                      </div>
                    </div>
                  ) : (
                    <div className="p-2 bg-theme-background rounded text-xs text-theme-muted">
                      No checkpoints available
                    </div>
                  )}

                  {selectedStrategy === 'checkpoint' && options.checkpoint_recovery.available && (
                    <button
                      onClick={handleCheckpointRecovery}
                      disabled={recovering === 'checkpoint'}
                      className="mt-3 w-full px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                    >
                      {recovering === 'checkpoint' ? (
                        <>
                          <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                          Recovering...
                        </>
                      ) : (
                        <>
                          <RotateCcw className="h-4 w-4" />
                          Recover from Checkpoint
                        </>
                      )}
                    </button>
                  )}
                </div>
              </div>
            </Card>

            {/* Node Retry */}
            <Card
              className={`p-4 cursor-pointer transition-colors ${
                selectedStrategy === 'retry'
                  ? 'border-theme-interactive-primary bg-theme-interactive-primary/5'
                  : 'border-theme hover:border-theme-interactive-primary/50'
              } ${options.node_retry.retryable_nodes.length === 0 ? 'opacity-50 cursor-not-allowed' : ''}`}
              onClick={() => options.node_retry.retryable_nodes.length > 0 && setSelectedStrategy('retry')}
            >
              <div className="flex items-start gap-3">
                <div className={`p-2 rounded-lg ${
                  options.node_retry.retryable_nodes.length > 0 ? 'bg-theme-info/10' : 'bg-theme-surface0/10'
                }`}>
                  <RefreshCw className={`h-5 w-5 ${
                    options.node_retry.retryable_nodes.length > 0 ? 'text-theme-info' : 'text-theme-muted'
                  }`} />
                </div>

                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <h4 className="text-sm font-medium text-theme-primary">Node Retry</h4>
                    {selectedStrategy === 'retry' && (
                      <CheckCircle className="h-4 w-4 text-theme-interactive-primary" />
                    )}
                  </div>

                  <p className="text-xs text-theme-secondary mb-2">
                    Retry failed nodes with automatic backoff
                  </p>

                  {options.node_retry.retryable_nodes.length > 0 ? (
                    <div className="space-y-2">
                      {options.node_retry.retryable_nodes.map((node) => (
                        <div key={node.execution_id} className="p-2 bg-theme-background rounded">
                          <div className="flex items-center justify-between mb-1">
                            <div className="text-xs font-medium text-theme-primary">{node.node_name}</div>
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                handleNodeRetry(node.execution_id);
                              }}
                              disabled={recovering === `retry-${node.execution_id}`}
                              className="px-2 py-0.5 bg-theme-interactive-primary text-white rounded text-xs hover:bg-theme-interactive-primary/90 transition-colors disabled:opacity-50"
                            >
                              {recovering === `retry-${node.execution_id}` ? 'Retrying...' : 'Retry'}
                            </button>
                          </div>
                          <div className="text-xs text-theme-muted">{node.error_message}</div>
                          <div className="text-xs text-theme-secondary mt-1">
                            {node.retry_stats.retries_remaining} retries remaining
                          </div>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="p-2 bg-theme-background rounded text-xs text-theme-muted">
                      No retryable nodes
                    </div>
                  )}
                </div>
              </div>
            </Card>

            {/* Workflow Restart */}
            <Card
              className={`p-4 cursor-pointer transition-colors ${
                selectedStrategy === 'restart'
                  ? 'border-theme-interactive-primary bg-theme-interactive-primary/5'
                  : 'border-theme hover:border-theme-interactive-primary/50'
              } ${!options.workflow_restart.available ? 'opacity-50 cursor-not-allowed' : ''}`}
              onClick={() => options.workflow_restart.available && setSelectedStrategy('restart')}
            >
              <div className="flex items-start gap-3">
                <div className={`p-2 rounded-lg ${
                  options.workflow_restart.available ? 'bg-theme-warning/10' : 'bg-theme-surface0/10'
                }`}>
                  <Play className={`h-5 w-5 ${
                    options.workflow_restart.available ? 'text-theme-warning' : 'text-theme-muted'
                  }`} />
                </div>

                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <h4 className="text-sm font-medium text-theme-primary">Workflow Restart</h4>
                    {selectedStrategy === 'restart' && (
                      <CheckCircle className="h-4 w-4 text-theme-interactive-primary" />
                    )}
                  </div>

                  <p className="text-xs text-theme-secondary mb-2">
                    Start the workflow from the beginning
                  </p>

                  {options.workflow_restart.available ? (
                    <>
                      {options.workflow_restart.preserve_progress && (
                        <div className="p-2 bg-theme-info/10 border border-theme-info/20 rounded mb-2">
                          <div className="flex items-start gap-1 text-xs text-theme-info">
                            <Info className="h-3 w-3 mt-0.5 flex-shrink-0" />
                            <span>Progress can be preserved using checkpoint recovery instead</span>
                          </div>
                        </div>
                      )}

                      <div className="p-2 bg-theme-warning/10 border border-theme-warning/20 rounded text-xs text-theme-warning">
                        <div className="flex items-start gap-1">
                          <AlertTriangle className="h-3 w-3 mt-0.5 flex-shrink-0" />
                          <span>Warning: This will discard all current progress</span>
                        </div>
                      </div>

                      {selectedStrategy === 'restart' && (
                        <button
                          onClick={handleWorkflowRestart}
                          disabled={recovering === 'restart'}
                          className="mt-3 w-full px-4 py-2 bg-orange-600 text-white rounded-lg hover:bg-orange-600/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                        >
                          {recovering === 'restart' ? (
                            <>
                              <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                              Restarting...
                            </>
                          ) : (
                            <>
                              <Play className="h-4 w-4" />
                              Restart Workflow
                            </>
                          )}
                        </button>
                      )}
                    </>
                  ) : (
                    <div className="p-2 bg-theme-background rounded text-xs text-theme-muted">
                      Restart not available
                    </div>
                  )}
                </div>
              </div>
            </Card>
          </div>
        )}
      </div>
    </Modal>
  );
};
