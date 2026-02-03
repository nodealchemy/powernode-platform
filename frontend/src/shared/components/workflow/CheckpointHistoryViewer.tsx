import React, { useState, useEffect } from 'react';
import { Save, Clock, RotateCcw, CheckCircle, AlertTriangle, Database, ArrowRight } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { api } from '@/shared/services/api';
import { useNotifications } from '@/shared/hooks/useNotifications';

export interface Checkpoint {
  id: string;
  checkpoint_type: 'node_completed' | 'batch_completed' | 'manual' | 'error_handler' | 'conditional_branch';
  node_id: string;
  sequence_number: number;
  created_at: string;
  age_seconds?: number;
  metadata: {
    progress_percentage: number;
    cost_so_far?: number;
    duration_so_far?: number;
    type?: string;
    node_id?: string;
    workflow_version?: string;
    total_nodes?: number;
    completed_nodes?: number;
    reason?: string;
    custom?: Record<string, any>;
  };
  state_keys?: string[];
  state_snapshot?: {
     
    variables?: Record<string, any>;
    completed_nodes?: string[];
     
    [key: string]: any;
  };
}

export interface CheckpointHistoryViewerProps {
  workflowRunId?: string;
  checkpoints?: Checkpoint[];
  onRestore?: (checkpointId: string) => void;
  onCreateCheckpoint?: () => void;
  className?: string;
}

export const CheckpointHistoryViewer: React.FC<CheckpointHistoryViewerProps> = ({
  workflowRunId,
  checkpoints: checkpointsProp,
  onRestore,
  onCreateCheckpoint,
  className = ''
}) => {
  const { addNotification } = useNotifications();
  const [checkpoints, setCheckpoints] = useState<Checkpoint[]>(checkpointsProp || []);
  const [loading, setLoading] = useState(!checkpointsProp);
  const [restoring, setRestoring] = useState<string | null>(null);
  const [selectedCheckpoint, setSelectedCheckpoint] = useState<string | null>(null);

  useEffect(() => {
    // Only load from API if checkpoints not provided via props
    if (!checkpointsProp && workflowRunId) {
      loadCheckpoints();
    } else if (checkpointsProp) {
      setCheckpoints(checkpointsProp);
      setLoading(false);
    }
  }, [workflowRunId, checkpointsProp]);

  const loadCheckpoints = async () => {
    try {
      setLoading(true);
      const response = await api.get(`/ai/workflow_runs/${workflowRunId}/recovery/checkpoints`);
      setCheckpoints(response.data.data.checkpoints || []);
    } catch (error) {
      console.error('Failed to load checkpoints:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleRestore = async (checkpointId: string) => {
    if (!confirm('Are you sure you want to restore from this checkpoint? The workflow will resume from this point.')) {
      return;
    }

    try {
      setRestoring(checkpointId);
      await api.post(`/ai/workflow_runs/${workflowRunId}/recovery/checkpoints/${checkpointId}/restore`);
      onRestore?.(checkpointId);
    } catch (error) {
      console.error('Failed to restore checkpoint:', error);
      addNotification({ type: 'error', message: 'Failed to restore from checkpoint. Please try again.' });
    } finally {
      setRestoring(null);
    }
  };

  const getCheckpointTypeInfo = (type: Checkpoint['checkpoint_type']) => {
    switch (type) {
      case 'node_completed':
        return { icon: CheckCircle, color: 'text-theme-success', bg: 'bg-theme-success/10', label: 'Node Completed' };
      case 'batch_completed':
        return { icon: Database, color: 'text-theme-info', bg: 'bg-theme-info/10', label: 'Batch Completed' };
      case 'manual':
        return { icon: Save, color: 'text-theme-interactive-primary', bg: 'bg-theme-interactive-primary/10', label: 'Manual' };
      case 'error_handler':
        return { icon: AlertTriangle, color: 'text-theme-warning', bg: 'bg-theme-warning/10', label: 'Error Handler' };
      case 'conditional_branch':
        return { icon: ArrowRight, color: 'text-theme-info', bg: 'bg-theme-info/10', label: 'Conditional' };
    }
  };

  const formatAge = (seconds?: number) => {
    if (!seconds) return 'Just now';
    if (seconds < 60) return `${seconds}s ago`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    return `${Math.floor(seconds / 86400)}d ago`;
  };

  const formatCost = (cost?: number) => {
    if (cost === undefined) return '$0.0000';
    return `$${cost.toFixed(4)}`;
  };

  const formatDuration = (ms?: number) => {
    if (ms === undefined) return '0ms';
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  if (loading) {
    return (
      <Card className={`p-6 ${className}`}>
        <div className="flex items-center justify-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary"></div>
        </div>
      </Card>
    );
  }

  return (
    <Card className={`p-4 ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <Save className="h-5 w-5 text-theme-interactive-primary" />
          <h3 className="text-lg font-semibold text-theme-primary">Checkpoint History</h3>
        </div>

        {onCreateCheckpoint && (
          <button
            onClick={onCreateCheckpoint}
            className="px-3 py-1.5 bg-theme-interactive-primary text-white rounded-lg text-sm hover:bg-theme-interactive-primary/90 transition-colors"
          >
            Create Checkpoint
          </button>
        )}
      </div>

      {/* Checkpoint count */}
      <div className="mb-4 p-3 bg-theme-background rounded-lg">
        <div className="text-sm text-theme-secondary">
          {checkpoints.length} checkpoint{checkpoints.length !== 1 ? 's' : ''} available
        </div>
      </div>

      {/* Checkpoints list */}
      {checkpoints.length === 0 ? (
        <div className="text-center py-8">
          <Save className="h-12 w-12 text-theme-secondary mx-auto mb-3 opacity-50" />
          <p className="text-sm text-theme-secondary">No checkpoints available</p>
          <p className="text-xs text-theme-muted mt-1">
            Checkpoints are created automatically after each node completion
          </p>
        </div>
      ) : (
        <div className="space-y-3 max-h-96 overflow-y-auto">
          {checkpoints.map((checkpoint) => {
            const typeInfo = getCheckpointTypeInfo(checkpoint.checkpoint_type);
            const TypeIcon = typeInfo.icon;
            const isSelected = selectedCheckpoint === checkpoint.id;
            const isRestoring = restoring === checkpoint.id;

            return (
              <div
                key={checkpoint.id}
                className={`p-3 border rounded-lg transition-colors cursor-pointer ${
                  isSelected
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary/5'
                    : 'border-theme hover:border-theme-interactive-primary/50'
                }`}
                onClick={() => setSelectedCheckpoint(isSelected ? null : checkpoint.id)}
              >
                {/* Checkpoint header */}
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <div className={`p-1.5 rounded-lg ${typeInfo.bg}`}>
                      <TypeIcon className={`h-4 w-4 ${typeInfo.color}`} />
                    </div>
                    <div>
                      <div className="text-sm font-medium text-theme-primary">
                        #{checkpoint.sequence_number} - {typeInfo.label}
                      </div>
                      <div className="flex items-center gap-2 text-xs text-theme-muted">
                        <Clock className="h-3 w-3" />
                        <span>{formatAge(checkpoint.age_seconds)}</span>
                      </div>
                    </div>
                  </div>

                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleRestore(checkpoint.id);
                    }}
                    disabled={isRestoring}
                    className="px-3 py-1 bg-theme-interactive-primary text-white rounded text-xs hover:bg-theme-interactive-primary/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1"
                  >
                    {isRestoring ? (
                      <>
                        <div className="animate-spin rounded-full h-3 w-3 border-b border-white"></div>
                        Restoring...
                      </>
                    ) : (
                      <>
                        <RotateCcw className="h-3 w-3" />
                        Restore
                      </>
                    )}
                  </button>
                </div>

                {/* Checkpoint metadata */}
                <div className="grid grid-cols-3 gap-2 text-xs">
                  <div className="p-2 bg-theme-background rounded">
                    <div className="text-theme-muted">Progress</div>
                    <div className="text-theme-primary font-medium">
                      {checkpoint.metadata.progress_percentage.toFixed(1)}%
                    </div>
                  </div>
                  <div className="p-2 bg-theme-background rounded">
                    <div className="text-theme-muted">Cost</div>
                    <div className="text-theme-primary font-medium">
                      {formatCost(checkpoint.metadata.cost_so_far)}
                    </div>
                  </div>
                  <div className="p-2 bg-theme-background rounded">
                    <div className="text-theme-muted">Duration</div>
                    <div className="text-theme-primary font-medium">
                      {formatDuration(checkpoint.metadata.duration_so_far)}
                    </div>
                  </div>
                </div>

                {/* Expanded details */}
                {isSelected && (
                  <div className="mt-3 pt-3 border-t border-theme space-y-2">
                    <div className="text-xs">
                      <div className="text-theme-muted mb-1">Node Information</div>
                      <div className="p-2 bg-theme-background rounded">
                        <div className="text-theme-primary">
                          Node ID: <span className="font-mono">{checkpoint.node_id}</span>
                        </div>
                        <div className="text-theme-secondary mt-1">
                          Completed: {checkpoint.metadata.completed_nodes}/{checkpoint.metadata.total_nodes} nodes
                        </div>
                      </div>
                    </div>

                    {(checkpoint.state_keys && checkpoint.state_keys.length > 0) && (
                      <div className="text-xs">
                        <div className="text-theme-muted mb-1">State Snapshot</div>
                        <div className="p-2 bg-theme-background rounded">
                          <div className="flex flex-wrap gap-1">
                            {checkpoint.state_keys.map(key => (
                              <span
                                key={key}
                                className="px-2 py-0.5 bg-theme-surface border border-theme rounded text-theme-primary"
                              >
                                {key}
                              </span>
                            ))}
                          </div>
                        </div>
                      </div>
                    )}

                    {checkpoint.metadata.custom && Object.keys(checkpoint.metadata.custom).length > 0 && (
                      <div className="text-xs">
                        <div className="text-theme-muted mb-1">Custom Metadata</div>
                        <div className="p-2 bg-theme-background rounded">
                          <pre className="text-theme-primary overflow-x-auto">
                            {JSON.stringify(checkpoint.metadata.custom, null, 2)}
                          </pre>
                        </div>
                      </div>
                    )}

                    <div className="text-xs text-theme-muted">
                      Workflow version: {checkpoint.metadata.workflow_version}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </Card>
  );
};
