import React, { useState, useMemo } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import {
  Play, Clock, CheckCircle, XCircle, AlertCircle, RefreshCw,
  ChevronDown, ChevronRight, Terminal, GitBranch, GitCommit,
  ExternalLink, Copy, Check, ArrowLeft, Layers, Search, Filter,
  UserCheck, SkipForward
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePipelineRun } from '@/features/cicd/hooks/usePipelineRuns';
import type { CiCdPipelineRunStatus, CiCdStepExecutionStatus } from '@/types/cicd';

// Status configurations
const runStatusConfig: Record<CiCdPipelineRunStatus, { bg: string; text: string; icon: React.ElementType; label: string }> = {
  pending: { bg: 'bg-yellow-100 dark:bg-yellow-900/30', text: 'text-yellow-700 dark:text-yellow-300', icon: Clock, label: 'Pending' },
  queued: { bg: 'bg-yellow-100 dark:bg-yellow-900/30', text: 'text-yellow-700 dark:text-yellow-300', icon: Clock, label: 'Queued' },
  running: { bg: 'bg-blue-100 dark:bg-blue-900/30', text: 'text-theme-info dark:text-blue-300', icon: RefreshCw, label: 'Running' },
  success: { bg: 'bg-green-100 dark:bg-green-900/30', text: 'text-theme-success dark:text-green-300', icon: CheckCircle, label: 'Success' },
  failure: { bg: 'bg-red-100 dark:bg-red-900/30', text: 'text-theme-danger dark:text-red-300', icon: XCircle, label: 'Failed' },
  cancelled: { bg: 'bg-theme-surface-secondary', text: 'text-theme-secondary', icon: AlertCircle, label: 'Cancelled' },
};

const stepStatusConfig: Record<CiCdStepExecutionStatus, { bg: string; text: string; icon: React.ElementType }> = {
  pending: { bg: 'bg-yellow-100 dark:bg-yellow-900/30', text: 'text-yellow-700 dark:text-yellow-300', icon: Clock },
  running: { bg: 'bg-blue-100 dark:bg-blue-900/30', text: 'text-theme-info dark:text-blue-300', icon: RefreshCw },
  waiting_approval: { bg: 'bg-purple-100 dark:bg-purple-900/30', text: 'text-purple-700 dark:text-purple-300', icon: UserCheck },
  success: { bg: 'bg-green-100 dark:bg-green-900/30', text: 'text-theme-success dark:text-green-300', icon: CheckCircle },
  failure: { bg: 'bg-red-100 dark:bg-red-900/30', text: 'text-theme-danger dark:text-red-300', icon: XCircle },
  cancelled: { bg: 'bg-theme-surface-secondary', text: 'text-theme-secondary', icon: AlertCircle },
  skipped: { bg: 'bg-theme-surface-secondary', text: 'text-theme-secondary', icon: SkipForward },
};

// Format helpers
const formatDuration = (seconds: number | null): string => {
  if (!seconds) return '-';
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${Math.round(seconds % 60)}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
};

const formatDateTime = (dateString: string | null): string => {
  if (!dateString) return '-';
  return new Date(dateString).toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
};

const formatTimeAgo = (dateString: string | null): string => {
  if (!dateString) return '-';
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

// Run Status Badge
const RunStatusBadge: React.FC<{ status: CiCdPipelineRunStatus; large?: boolean }> = ({ status, large }) => {
  const config = runStatusConfig[status] || runStatusConfig.pending;
  const Icon = config.icon;

  return (
    <span className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full font-medium ${config.bg} ${config.text} ${large ? 'text-sm' : 'text-xs'}`}>
      <Icon className={`${large ? 'w-4 h-4' : 'w-3 h-3'} ${status === 'running' ? 'animate-spin' : ''}`} />
      {config.label}
    </span>
  );
};

// Step Execution Item
const StepExecutionItem: React.FC<{
  step: {
    step_id: string;
    step_name: string;
    step_type: string;
    status: string;
    started_at: string | null;
    completed_at: string | null;
    duration_seconds: number | null;
    logs: string;
    outputs: Record<string, unknown>;
    error_message: string | null;
  };
  index: number;
  defaultExpanded?: boolean;
}> = ({ step, index, defaultExpanded = false }) => {
  const [expanded, setExpanded] = useState(defaultExpanded);
  const [copiedLog, setCopiedLog] = useState(false);

  const statusConfig = stepStatusConfig[step.status as CiCdStepExecutionStatus] || stepStatusConfig.pending;
  const StatusIcon = statusConfig.icon;
  const hasLogs = step.logs && step.logs.trim().length > 0;
  const hasOutputs = step.outputs && Object.keys(step.outputs).length > 0;

  const handleCopyLog = async () => {
    if (step.logs) {
      await navigator.clipboard.writeText(step.logs);
      setCopiedLog(true);
      setTimeout(() => setCopiedLog(false), 2000);
    }
  };

  return (
    <div className="border border-theme rounded-lg overflow-hidden">
      {/* Step Header */}
      <div
        className={`flex items-center justify-between px-4 py-3 bg-theme-surface-secondary ${(hasLogs || hasOutputs) ? 'cursor-pointer hover:bg-theme-surface-tertiary' : ''}`}
        onClick={() => (hasLogs || hasOutputs) && setExpanded(!expanded)}
      >
        <div className="flex items-center gap-3">
          {(hasLogs || hasOutputs) ? (
            <button className="text-theme-secondary hover:text-theme-primary">
              {expanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
            </button>
          ) : (
            <div className="w-4" />
          )}
          <div className="w-6 h-6 rounded-full bg-theme-surface flex items-center justify-center text-xs font-medium text-theme-secondary">
            {index + 1}
          </div>
          <div>
            <span className="font-medium text-theme-primary">{step.step_name}</span>
            <span className="ml-2 px-2 py-0.5 text-xs rounded bg-theme-surface text-theme-tertiary">
              {step.step_type}
            </span>
          </div>
        </div>
        <div className={`flex items-center gap-1.5 px-2 py-1 rounded-full text-xs font-medium ${statusConfig.bg} ${statusConfig.text}`}>
          <StatusIcon className={`w-3 h-3 ${step.status === 'running' ? 'animate-spin' : ''}`} />
          {step.status}
        </div>
      </div>

      {/* Error Message */}
      {step.error_message && (
        <div className="px-4 py-3 bg-red-50 dark:bg-red-950/20 border-t border-theme">
          <p className="text-sm text-theme-danger dark:text-red-400">
            <strong>Error:</strong> {step.error_message}
          </p>
        </div>
      )}

      {/* Log Output */}
      {expanded && hasLogs && (
        <div className="border-t border-theme">
          <div className="flex items-center justify-between px-4 py-2 bg-theme-surface border-b border-theme">
            <div className="flex items-center gap-2 text-sm text-theme-secondary">
              <Terminal className="w-4 h-4" />
              Logs
            </div>
            <button
              onClick={(e) => {
                e.stopPropagation();
                handleCopyLog();
              }}
              className="flex items-center gap-1 text-xs text-theme-tertiary hover:text-theme-secondary"
            >
              {copiedLog ? (
                <>
                  <Check className="w-3 h-3 text-theme-success" />
                  Copied
                </>
              ) : (
                <>
                  <Copy className="w-3 h-3" />
                  Copy
                </>
              )}
            </button>
          </div>
          <pre className="p-4 bg-theme-bg-subtle text-xs font-mono text-theme-secondary overflow-x-auto whitespace-pre-wrap max-h-96">
            {step.logs}
          </pre>
        </div>
      )}

      {/* Step Outputs */}
      {expanded && hasOutputs && (
        <div className="border-t border-theme">
          <div className="flex items-center justify-between px-4 py-2 bg-theme-surface border-b border-theme">
            <div className="flex items-center gap-2 text-sm text-theme-secondary">
              <Layers className="w-4 h-4" />
              Outputs
            </div>
            <span className="text-xs text-theme-tertiary">
              {Object.keys(step.outputs).length} {Object.keys(step.outputs).length === 1 ? 'value' : 'values'}
            </span>
          </div>
          <div className="p-4 bg-theme-bg-subtle">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {Object.entries(step.outputs).map(([key, value]) => (
                <div key={key} className="flex flex-col">
                  <span className="text-xs text-theme-tertiary font-medium uppercase tracking-wide">
                    {key.replace(/_/g, ' ')}
                  </span>
                  <span className="text-sm text-theme-primary font-mono mt-0.5">
                    {typeof value === 'boolean' ? (
                      <span className={value ? 'text-theme-success dark:text-green-400' : 'text-theme-danger dark:text-red-400'}>
                        {value ? '✓ true' : '✗ false'}
                      </span>
                    ) : typeof value === 'object' ? (
                      JSON.stringify(value)
                    ) : (
                      String(value)
                    )}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

// Progress Bar Component
const ProgressBar: React.FC<{ progress: number; status: CiCdPipelineRunStatus }> = ({ progress, status }) => {
  const getColor = () => {
    if (status === 'success') return 'bg-theme-success';
    if (status === 'failure') return 'bg-theme-error';
    if (status === 'cancelled') return 'bg-theme-secondary';
    return 'bg-theme-info';
  };

  return (
    <div className="w-full">
      <div className="flex items-center justify-between text-sm mb-1">
        <span className="text-theme-secondary">Progress</span>
        <span className="text-theme-primary font-medium">{progress}%</span>
      </div>
      <div className="h-2 bg-theme-secondary/20 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-500 ${getColor()}`}
          style={{ width: `${progress}%` }}
        />
      </div>
    </div>
  );
};

// Step Execution Timeline Component
const StepExecutionTimeline: React.FC<{
  steps: Array<{
    step_name: string;
    step_type: string;
    status: string;
    duration_seconds: number | null;
  }>;
  totalDuration: number;
}> = ({ steps, totalDuration }) => {
  if (steps.length === 0 || totalDuration === 0) return null;

  // Find the slowest step
  const slowestIndex = steps.reduce(
    (maxIdx, step, idx, arr) =>
      (step.duration_seconds || 0) > (arr[maxIdx].duration_seconds || 0) ? idx : maxIdx,
    0
  );

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-theme-primary">Execution Timeline</h3>
        <span className="text-xs text-theme-tertiary">
          Total: {formatDuration(totalDuration)}
        </span>
      </div>
      <div className="space-y-2">
        {steps.map((step, index) => {
          const duration = step.duration_seconds || 0;
          const percentage = totalDuration > 0 ? (duration / totalDuration) * 100 : 0;
          const isSlowest = index === slowestIndex && steps.length > 1 && duration > 0;
          const statusConfig = stepStatusConfig[step.status as CiCdStepExecutionStatus] || stepStatusConfig.pending;

          return (
            <div key={index} className="flex items-center gap-3">
              <div className="w-32 shrink-0 flex items-center gap-2">
                <span className={`w-2 h-2 rounded-full ${statusConfig.bg}`} />
                <span className="text-xs text-theme-secondary truncate" title={step.step_name}>
                  {step.step_name}
                </span>
              </div>
              <div className="flex-1 h-5 bg-theme-secondary/10 rounded overflow-hidden relative">
                <div
                  className={`h-full rounded transition-all ${
                    step.status === 'success' ? 'bg-theme-success/70' :
                    step.status === 'failure' ? 'bg-theme-danger/70' :
                    step.status === 'running' ? 'bg-theme-info/70 animate-pulse' :
                    'bg-theme-secondary/30'
                  }`}
                  style={{ width: `${Math.max(percentage, 2)}%` }}
                />
                {isSlowest && (
                  <span className="absolute right-1 top-0.5 text-[10px] text-theme-tertiary">
                    slowest
                  </span>
                )}
              </div>
              <span className="w-16 text-xs text-theme-tertiary text-right shrink-0">
                {formatDuration(duration)}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
};

// Main Page Component
const RunDetailPageContent: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();

  // Log search and filter state
  const [logSearch, setLogSearch] = useState('');
  const [showErrorsOnly, setShowErrorsOnly] = useState(false);

  const {
    run,
    logs,
    loading,
    logsLoading,
    error,
    refresh,
    refreshLogs,
    cancelRun,
    retryRun,
  } = usePipelineRun(id || null);

  // Filter logs based on search and error-only filter
  const filteredLogs = useMemo(() => {
    let result = logs;

    // Filter by errors only
    if (showErrorsOnly) {
      result = result.filter(step =>
        step.status === 'failure' || step.error_message
      );
    }

    // Filter by search term
    if (logSearch.trim()) {
      const searchLower = logSearch.toLowerCase();
      result = result.filter(step =>
        step.step_name.toLowerCase().includes(searchLower) ||
        step.step_type.toLowerCase().includes(searchLower) ||
        (step.logs && step.logs.toLowerCase().includes(searchLower)) ||
        (step.error_message && step.error_message.toLowerCase().includes(searchLower))
      );
    }

    return result;
  }, [logs, logSearch, showErrorsOnly]);

  // WebSocket updates are handled by the usePipelineRun hook
  // No polling needed - updates come via WebSocket

  const handleCancel = async () => {
    const result = await cancelRun();
    if (result) {
      refresh();
    }
  };

  const handleRetry = async () => {
    const result = await retryRun();
    if (result) {
      navigate(`/app/automation/runs/${result.id}`);
    }
  };

  const pageActions: PageAction[] = [];

  if (run) {
    pageActions.push({
      id: 'refresh',
      label: 'Refresh',
      onClick: () => {
        refresh();
        refreshLogs();
      },
      variant: 'secondary',
      icon: RefreshCw,
    });

    if (run.status === 'pending' || run.status === 'running') {
      pageActions.push({
        id: 'cancel',
        label: 'Cancel',
        onClick: handleCancel,
        variant: 'secondary',
        icon: XCircle,
      });
    }

    if (run.status === 'failure' || run.status === 'cancelled') {
      pageActions.push({
        id: 'retry',
        label: 'Retry',
        onClick: handleRetry,
        variant: 'primary',
        icon: RefreshCw,
      });
    }
  }

  if (loading) {
    return (
      <PageContainer
        title="Run Details"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Automation', href: '/app/automation' },
          { label: 'Runs', href: '/app/automation/runs' },
          { label: 'Loading...' },
        ]}
      >
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      </PageContainer>
    );
  }

  if (error || !run) {
    return (
      <PageContainer
        title="Run Not Found"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Automation', href: '/app/automation' },
          { label: 'Runs', href: '/app/automation/runs' },
          { label: 'Not Found' },
        ]}
      >
        <div className="bg-theme-surface rounded-lg border border-theme p-8 text-center">
          <AlertCircle className="w-12 h-12 text-theme-danger mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">Run Not Found</h3>
          <p className="text-theme-secondary mb-4">{error || 'The requested pipeline run could not be found.'}</p>
          <Button onClick={() => navigate('/app/automation/runs')} variant="primary">
            Back to Runs
          </Button>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={`Run #${run.run_number}`}
      description={run.pipeline_name || 'Pipeline Run'}
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Automation', href: '/app/automation' },
        { label: 'Runs', href: '/app/automation/runs' },
        { label: `#${run.run_number}` },
      ]}
      actions={pageActions}
    >
      <div className="space-y-6">
        {/* Header Card */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
            <div className="flex items-start gap-4">
              <div className="p-3 bg-theme-surface-secondary rounded-lg">
                <Play className="w-6 h-6 text-theme-primary" />
              </div>
              <div>
                <div className="flex items-center gap-3 mb-1">
                  <h2 className="text-xl font-semibold text-theme-primary">
                    Run #{run.run_number}
                  </h2>
                  <RunStatusBadge status={run.status} large />
                </div>
                <Link
                  to={`/app/automation/pipelines/${run.pipeline_slug || ''}`}
                  className="text-theme-secondary hover:text-theme-primary hover:underline"
                >
                  {run.pipeline_name || 'Unknown Pipeline'}
                </Link>
              </div>
            </div>

            <div className="flex items-center gap-3">
              {run.external_run_url && (
                <a
                  href={run.external_run_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-1 text-sm text-theme-primary hover:underline"
                >
                  <ExternalLink className="w-4 h-4" />
                  View External
                </a>
              )}
            </div>
          </div>

          {/* Progress Bar */}
          <div className="mt-6">
            <ProgressBar progress={run.progress_percentage} status={run.status} />
          </div>

          {/* Current Step (if running) */}
          {run.current_step && (run.status === 'running' || run.status === 'pending') && (
            <div className="mt-4 p-3 bg-blue-50 dark:bg-blue-950/20 rounded-lg">
              <p className="text-sm text-theme-info dark:text-blue-300">
                <strong>Current Step:</strong> {run.current_step.name} ({run.current_step.step_type})
              </p>
            </div>
          )}

          {/* Error Message */}
          {run.error_message && (
            <div className="mt-4 p-3 bg-red-50 dark:bg-red-950/20 rounded-lg">
              <p className="text-sm text-theme-danger dark:text-red-300">
                <strong>Error:</strong> {run.error_message}
              </p>
            </div>
          )}
        </div>

        {/* Details Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <p className="text-sm text-theme-tertiary mb-1">Trigger</p>
            <p className="font-medium text-theme-primary capitalize">{run.trigger_type}</p>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <p className="text-sm text-theme-tertiary mb-1">Started</p>
            <p className="font-medium text-theme-primary">{formatTimeAgo(run.started_at)}</p>
            <p className="text-xs text-theme-secondary">{formatDateTime(run.started_at)}</p>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <p className="text-sm text-theme-tertiary mb-1">Duration</p>
            <p className="font-medium text-theme-primary">{formatDuration(run.duration_seconds)}</p>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <p className="text-sm text-theme-tertiary mb-1">Steps Executed</p>
            <p className="font-medium text-theme-primary">{run.step_execution_count}</p>
          </div>
        </div>

        {/* Git Context */}
        {(run.branch || run.commit_sha || run.pr_number) && (
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <h3 className="text-sm font-medium text-theme-primary mb-3">Git Context</h3>
            <div className="flex flex-wrap items-center gap-4 text-sm">
              {run.branch && (
                <div className="flex items-center gap-2">
                  <GitBranch className="w-4 h-4 text-theme-secondary" />
                  <span className="text-theme-secondary">Branch:</span>
                  <span className="font-mono text-theme-primary">{run.branch}</span>
                </div>
              )}
              {run.commit_sha && (
                <div className="flex items-center gap-2">
                  <GitCommit className="w-4 h-4 text-theme-secondary" />
                  <span className="text-theme-secondary">Commit:</span>
                  <code className="px-2 py-0.5 bg-theme-surface-secondary rounded text-xs font-mono text-theme-primary">
                    {run.commit_sha.substring(0, 7)}
                  </code>
                </div>
              )}
              {run.pr_number && (
                <div className="flex items-center gap-2">
                  <span className="text-theme-secondary">PR:</span>
                  <span className="font-medium text-theme-primary">#{run.pr_number}</span>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Step Execution Timeline */}
        {logs.length > 0 && run.duration_seconds && run.duration_seconds > 0 && (
          <StepExecutionTimeline
            steps={logs.map(l => ({
              step_name: l.step_name,
              step_type: l.step_type,
              status: l.status,
              duration_seconds: l.duration_seconds,
            }))}
            totalDuration={run.duration_seconds}
          />
        )}

        {/* Step Executions */}
        <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
          <div className="px-4 py-3 border-b border-theme">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <Layers className="w-5 h-5 text-theme-secondary" />
                <h3 className="font-medium text-theme-primary">Step Executions</h3>
                {filteredLogs.length !== logs.length && (
                  <span className="text-xs text-theme-tertiary">
                    ({filteredLogs.length} of {logs.length})
                  </span>
                )}
              </div>
              {logsLoading && (
                <span className="text-xs text-theme-tertiary flex items-center gap-1">
                  <RefreshCw className="w-3 h-3 animate-spin" />
                  Loading logs...
                </span>
              )}
            </div>

            {/* Search and Filter Controls */}
            {logs.length > 0 && (
              <div className="flex flex-col sm:flex-row gap-3">
                {/* Search Input */}
                <div className="relative flex-1">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
                  <input
                    type="text"
                    value={logSearch}
                    onChange={(e) => setLogSearch(e.target.value)}
                    placeholder="Search steps, logs, errors..."
                    className="w-full pl-9 pr-3 py-2 text-sm bg-theme-surface-secondary border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary/20"
                  />
                  {logSearch && (
                    <button
                      onClick={() => setLogSearch('')}
                      className="absolute right-3 top-1/2 -translate-y-1/2 text-theme-tertiary hover:text-theme-secondary"
                    >
                      <XCircle className="w-4 h-4" />
                    </button>
                  )}
                </div>

                {/* Error Filter Toggle */}
                <label className="flex items-center gap-2 cursor-pointer shrink-0">
                  <div className="relative">
                    <input
                      type="checkbox"
                      checked={showErrorsOnly}
                      onChange={(e) => setShowErrorsOnly(e.target.checked)}
                      className="sr-only"
                    />
                    <div className={`w-9 h-5 rounded-full transition-colors ${showErrorsOnly ? 'bg-theme-danger' : 'bg-theme-secondary/30'}`}>
                      <div className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${showErrorsOnly ? 'translate-x-4' : ''}`} />
                    </div>
                  </div>
                  <span className="text-sm text-theme-secondary flex items-center gap-1">
                    <Filter className="w-3 h-3" />
                    Errors only
                  </span>
                </label>
              </div>
            )}
          </div>

          <div className="p-4 space-y-3">
            {filteredLogs.length === 0 && logs.length === 0 ? (
              <div className="text-center py-8">
                <Terminal className="w-12 h-12 text-theme-secondary mx-auto mb-3 opacity-50" />
                <p className="text-theme-secondary">No step executions yet</p>
                <p className="text-sm text-theme-tertiary mt-1">
                  Steps will appear here as the pipeline runs
                </p>
              </div>
            ) : filteredLogs.length === 0 ? (
              <div className="text-center py-8">
                <Search className="w-12 h-12 text-theme-secondary mx-auto mb-3 opacity-50" />
                <p className="text-theme-secondary">No matching steps found</p>
                <p className="text-sm text-theme-tertiary mt-1">
                  Try adjusting your search or filter criteria
                </p>
                <button
                  onClick={() => {
                    setLogSearch('');
                    setShowErrorsOnly(false);
                  }}
                  className="mt-3 text-sm text-theme-primary hover:underline"
                >
                  Clear filters
                </button>
              </div>
            ) : (
              filteredLogs.map((step, index) => (
                <StepExecutionItem
                  key={step.step_id}
                  step={step}
                  index={index}
                  defaultExpanded={step.status === 'failure' || step.status === 'failed' || (index === filteredLogs.length - 1 && run.status === 'running')}
                />
              ))
            )}
          </div>
        </div>

        {/* Outputs (if available) */}
        {run.outputs && Object.keys(run.outputs).length > 0 && (
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <h3 className="text-sm font-medium text-theme-primary mb-3">Outputs</h3>
            <pre className="p-3 bg-theme-surface-secondary rounded text-xs font-mono text-theme-secondary overflow-x-auto">
              {JSON.stringify(run.outputs, null, 2)}
            </pre>
          </div>
        )}

        {/* Artifacts (if available) */}
        {run.artifacts && Object.keys(run.artifacts).length > 0 && (
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <h3 className="text-sm font-medium text-theme-primary mb-3">Artifacts</h3>
            <pre className="p-3 bg-theme-surface-secondary rounded text-xs font-mono text-theme-secondary overflow-x-auto">
              {JSON.stringify(run.artifacts, null, 2)}
            </pre>
          </div>
        )}

        {/* Back Link */}
        <div className="flex items-center gap-4">
          <Button
            onClick={() => navigate(-1)}
            variant="ghost"
          >
            <ArrowLeft className="w-4 h-4 mr-2" />
            Back
          </Button>
          <Link
            to="/app/automation/runs"
            className="text-sm text-theme-secondary hover:text-theme-primary"
          >
            View All Runs
          </Link>
        </div>
      </div>
    </PageContainer>
  );
};

export function RunDetailPage() {
  return (
    <PageErrorBoundary>
      <RunDetailPageContent />
    </PageErrorBoundary>
  );
}

export default RunDetailPage;
