import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Play, Clock, XCircle, RefreshCw, AlertCircle, CheckCircle,
  ChevronDown, ChevronRight, GitBranch, ExternalLink
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { CiCdPipelineRun, CiCdPipelineRunStatus } from '@/types/cicd';

interface RunHistoryProps {
  runs: CiCdPipelineRun[];
  loading: boolean;
  onCancel: (id: string) => void;
  onRetry: (id: string) => void;
}

const getStatusConfig = (status: CiCdPipelineRunStatus) => {
  const configs: Record<CiCdPipelineRunStatus, { bg: string; text: string; icon: React.ElementType; label: string }> = {
    pending: { bg: 'bg-theme-warning/10', text: 'text-theme-warning', icon: Clock, label: 'Pending' },
    queued: { bg: 'bg-theme-warning/10', text: 'text-theme-warning', icon: Clock, label: 'Queued' },
    running: { bg: 'bg-theme-info/10', text: 'text-theme-info', icon: RefreshCw, label: 'Running' },
    success: { bg: 'bg-theme-success/10', text: 'text-theme-success', icon: CheckCircle, label: 'Success' },
    failure: { bg: 'bg-theme-error/10', text: 'text-theme-error', icon: XCircle, label: 'Failed' },
    cancelled: { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', icon: AlertCircle, label: 'Cancelled' },
  };
  return configs[status] || configs.pending;
};

const StatusBadge: React.FC<{ status: CiCdPipelineRunStatus }> = ({ status }) => {
  const config = getStatusConfig(status);
  const Icon = config.icon;
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium ${config.bg} ${config.text}`}>
      <Icon className={`w-3 h-3 ${status === 'running' ? 'animate-spin' : ''}`} />
      {config.label}
    </span>
  );
};

const formatDuration = (seconds: number | null): string => {
  if (!seconds) return '-';
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
  return `${Math.round(seconds / 3600)}h ${Math.round((seconds % 3600) / 60)}m`;
};

const formatTimeAgo = (dateString: string): string => {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  return `${diffDays}d ago`;
};

const getTriggerLabel = (triggerType: string): string => {
  const labels: Record<string, string> = {
    manual: 'Manual',
    webhook: 'Webhook',
    schedule: 'Scheduled',
    retry: 'Retry',
    pull_request: 'PR',
    push: 'Push',
  };
  return labels[triggerType] || triggerType;
};

const RunRow: React.FC<{
  run: CiCdPipelineRun;
  isExpanded: boolean;
  onToggle: () => void;
  onNavigate: () => void;
  onCancel: () => void;
  onRetry: () => void;
}> = ({ run, isExpanded, onToggle, onNavigate, onCancel, onRetry }) => {
  const config = getStatusConfig(run.status);

  return (
    <div className={`border-b border-theme last:border-b-0 ${isExpanded ? 'bg-theme-surface-hover' : ''}`}>
      {/* Condensed Row */}
      <button
        onClick={onToggle}
        className="w-full px-4 py-2.5 flex items-center gap-3 hover:bg-theme-surface-hover transition-colors text-left"
      >
        {/* Expand Icon */}
        <span className="text-theme-tertiary">
          {isExpanded ? (
            <ChevronDown className="w-4 h-4" />
          ) : (
            <ChevronRight className="w-4 h-4" />
          )}
        </span>

        {/* Status Icon */}
        <span className={config.text}>
          {React.createElement(config.icon, {
            className: `w-4 h-4 ${run.status === 'running' ? 'animate-spin' : ''}`
          })}
        </span>

        {/* Run Number */}
        <span className="font-medium text-theme-primary w-28 truncate">
          #{run.run_number}
        </span>

        {/* Pipeline Name */}
        <span className="text-sm text-theme-secondary flex-1 truncate hidden sm:block">
          {run.pipeline_name || 'Pipeline'}
        </span>

        {/* Trigger */}
        <span className="text-xs text-theme-tertiary px-2 py-0.5 bg-theme-surface-secondary rounded hidden md:block">
          {getTriggerLabel(run.trigger_type)}
        </span>

        {/* Branch */}
        {run.branch && (
          <span className="text-xs text-theme-tertiary hidden lg:flex items-center gap-1">
            <GitBranch className="w-3 h-3" />
            {run.branch}
          </span>
        )}

        {/* Duration */}
        <span className="text-xs text-theme-tertiary w-16 text-right hidden sm:block">
          {formatDuration(run.duration_seconds)}
        </span>

        {/* Time */}
        <span className="text-xs text-theme-tertiary w-20 text-right">
          {formatTimeAgo(run.created_at)}
        </span>

        {/* Status Badge (mobile) */}
        <span className="sm:hidden">
          <StatusBadge status={run.status} />
        </span>
      </button>

      {/* Expanded Details */}
      {isExpanded && (
        <div className="px-4 pb-3 pt-1 ml-7 border-t border-theme bg-theme-surface">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm mb-3">
            <div>
              <p className="text-theme-tertiary text-xs">Status</p>
              <StatusBadge status={run.status} />
            </div>
            <div>
              <p className="text-theme-tertiary text-xs">Trigger</p>
              <p className="text-theme-primary">{getTriggerLabel(run.trigger_type)}</p>
            </div>
            <div>
              <p className="text-theme-tertiary text-xs">Duration</p>
              <p className="text-theme-primary">{formatDuration(run.duration_seconds)}</p>
            </div>
            <div>
              <p className="text-theme-tertiary text-xs">Started</p>
              <p className="text-theme-primary">{run.started_at ? formatTimeAgo(run.started_at) : '-'}</p>
            </div>
          </div>

          {/* Progress for running */}
          {run.current_step && run.status === 'running' && (
            <div className="mb-3 p-2 bg-theme-surface-secondary rounded">
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-secondary">
                  Step: {run.current_step.name}
                </span>
                <div className="flex items-center gap-2">
                  <div className="w-24 h-1.5 bg-theme-secondary/20 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-theme-info rounded-full transition-all"
                      style={{ width: `${run.progress_percentage}%` }}
                    />
                  </div>
                  <span className="text-xs text-theme-tertiary">
                    {run.progress_percentage}%
                  </span>
                </div>
              </div>
            </div>
          )}

          {/* Error message */}
          {run.error_message && (
            <div className="mb-3 p-2 bg-theme-error/10 rounded text-sm text-theme-error">
              {run.error_message}
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center justify-between">
            <Button
              onClick={(e) => {
                e.stopPropagation();
                onNavigate();
              }}
              variant="secondary"
              size="sm"
            >
              <ExternalLink className="w-3 h-3 mr-1" />
              View Details
            </Button>

            <div className="flex items-center gap-2">
              {(run.status === 'pending' || run.status === 'running') && (
                <Button
                  onClick={(e) => {
                    e.stopPropagation();
                    onCancel();
                  }}
                  variant="secondary"
                  size="sm"
                >
                  <XCircle className="w-3 h-3 mr-1" />
                  Cancel
                </Button>
              )}
              {(run.status === 'failure' || run.status === 'cancelled') && (
                <Button
                  onClick={(e) => {
                    e.stopPropagation();
                    onRetry();
                  }}
                  variant="primary"
                  size="sm"
                >
                  <RefreshCw className="w-3 h-3 mr-1" />
                  Retry
                </Button>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export const RunHistory: React.FC<RunHistoryProps> = ({
  runs,
  loading,
  onCancel,
  onRetry,
}) => {
  const navigate = useNavigate();
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const toggleExpand = (id: string) => {
    setExpandedId(expandedId === id ? null : id);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (runs.length === 0) {
    return (
      <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
        <Play className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">
          No Pipeline Runs Yet
        </h3>
        <p className="text-theme-secondary mb-4">
          Trigger a pipeline to see run history here.
        </p>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
      {/* Header */}
      <div className="px-4 py-2 bg-theme-surface-secondary border-b border-theme flex items-center gap-3 text-xs font-medium text-theme-tertiary">
        <span className="w-4" /> {/* Expand icon space */}
        <span className="w-4" /> {/* Status icon space */}
        <span className="w-28">Run</span>
        <span className="flex-1 hidden sm:block">Pipeline</span>
        <span className="hidden md:block w-20">Trigger</span>
        <span className="hidden lg:block w-24">Branch</span>
        <span className="w-16 text-right hidden sm:block">Duration</span>
        <span className="w-20 text-right">Time</span>
      </div>

      {/* Rows */}
      {runs.map((run) => (
        <RunRow
          key={run.id}
          run={run}
          isExpanded={expandedId === run.id}
          onToggle={() => toggleExpand(run.id)}
          onNavigate={() => navigate(`/app/automation/runs/${run.id}`)}
          onCancel={() => onCancel(run.id)}
          onRetry={() => onRetry(run.id)}
        />
      ))}
    </div>
  );
};

export default RunHistory;
