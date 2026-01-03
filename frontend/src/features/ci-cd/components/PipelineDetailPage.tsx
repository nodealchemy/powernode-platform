import React, { useState, useEffect, useCallback } from 'react';
import { useParams } from 'react-router-dom';
import {
  Play, GitBranch, RefreshCw, ExternalLink, Clock, User,
  XCircle, RotateCcw, Calendar, Hash
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import { useNotification } from '@/shared/hooks/useNotification';
import { JobsList } from './JobsList';
import { JobLogViewer } from './JobLogViewer';
import type { GitPipelineDetail, GitPipelineJob } from '../types';

const StatusBadge: React.FC<{ status: string; conclusion?: string; large?: boolean }> = ({
  status,
  conclusion,
  large = false,
}) => {
  const getStatusConfig = () => {
    if (status === 'completed') {
      switch (conclusion) {
        case 'success':
          return { bg: 'bg-theme-success/10', text: 'text-theme-success', label: 'Success' };
        case 'failure':
          return { bg: 'bg-theme-error/10', text: 'text-theme-error', label: 'Failed' };
        case 'cancelled':
          return { bg: 'bg-theme-warning/10', text: 'text-theme-warning', label: 'Cancelled' };
        case 'skipped':
          return { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', label: 'Skipped' };
        default:
          return { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', label: conclusion || 'Unknown' };
      }
    }
    switch (status) {
      case 'running':
        return { bg: 'bg-theme-info/10', text: 'text-theme-info', label: 'Running' };
      case 'pending':
        return { bg: 'bg-theme-warning/10', text: 'text-theme-warning', label: 'Pending' };
      case 'queued':
        return { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', label: 'Queued' };
      default:
        return { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', label: status };
    }
  };

  const config = getStatusConfig();
  const sizeClasses = large ? 'px-4 py-2 text-sm' : 'px-2.5 py-1 text-xs';

  return (
    <span className={`inline-flex items-center rounded-full font-medium ${config.bg} ${config.text} ${sizeClasses}`}>
      {config.label}
    </span>
  );
};

const formatDuration = (seconds: number): string => {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m ${Math.round(seconds % 60)}s`;
  return `${Math.round(seconds / 3600)}h ${Math.round((seconds % 3600) / 60)}m`;
};

const PipelineDetailPageContent: React.FC = () => {
  const { repositoryId, pipelineId } = useParams<{ repositoryId: string; pipelineId: string }>();
  const { showNotification } = useNotification();

  const [pipeline, setPipeline] = useState<GitPipelineDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedJob, setSelectedJob] = useState<GitPipelineJob | null>(null);

  const fetchPipeline = useCallback(async () => {
    if (!repositoryId || !pipelineId) return;

    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getPipeline(repositoryId, pipelineId);
      setPipeline(data);

      // Auto-select first job if none selected and jobs exist
      if (!selectedJob && data?.jobs && data.jobs.length > 0) {
        setSelectedJob(data.jobs[0]);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch pipeline');
    } finally {
      setLoading(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [repositoryId, pipelineId]); // Intentionally exclude selectedJob to prevent re-fetch on selection

  useEffect(() => {
    fetchPipeline();

    // Poll for updates if pipeline is running
    let pollInterval: NodeJS.Timeout | null = null;
    if (pipeline?.status === 'running' || pipeline?.status === 'pending') {
      pollInterval = setInterval(fetchPipeline, 10000);
    }

    return () => {
      if (pollInterval) {
        clearInterval(pollInterval);
      }
    };
  }, [fetchPipeline, pipeline?.status]);

  const handleCancelPipeline = async () => {
    if (!repositoryId || !pipelineId) return;
    try {
      await gitProvidersApi.cancelPipeline(repositoryId, pipelineId);
      showNotification('Pipeline cancelled', 'success');
      fetchPipeline();
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to cancel pipeline', 'error');
    }
  };

  const handleRetryPipeline = async () => {
    if (!repositoryId || !pipelineId) return;
    try {
      await gitProvidersApi.retryPipeline(repositoryId, pipelineId);
      showNotification('Pipeline retry started', 'success');
      fetchPipeline();
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to retry pipeline', 'error');
    }
  };

  const breadcrumbs = [
    { label: 'CI/CD', href: '/app/ci-cd', icon: Play },
    { label: 'Repositories', href: '/app/ci-cd/repositories' },
    { label: 'Repository', href: `/app/ci-cd/repositories/${repositoryId}` },
    { label: pipeline?.name || 'Pipeline' }
  ];

  const canCancel = pipeline?.status === 'running' || pipeline?.status === 'pending';
  const canRetry = pipeline?.status === 'completed' && pipeline?.conclusion === 'failure';

  const actions = [
    ...(canCancel ? [{
      id: 'cancel',
      label: 'Cancel',
      onClick: handleCancelPipeline,
      variant: 'danger' as const,
      icon: XCircle
    }] : []),
    ...(canRetry ? [{
      id: 'retry',
      label: 'Retry',
      onClick: handleRetryPipeline,
      variant: 'secondary' as const,
      icon: RotateCcw
    }] : []),
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: fetchPipeline,
      variant: 'primary' as const,
      icon: RefreshCw
    }
  ];

  if (error) {
    return (
      <PageContainer
        title="Pipeline Details"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
        <div className="bg-theme-error/10 border border-theme-error rounded-lg p-4">
          <p className="text-theme-error">{error}</p>
          <Button onClick={fetchPipeline} variant="secondary" size="sm" className="mt-2">
            Try Again
          </Button>
        </div>
      </PageContainer>
    );
  }

  if (loading && !pipeline) {
    return (
      <PageContainer
        title="Pipeline Details"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
          <span className="ml-3 text-theme-secondary">Loading pipeline details...</span>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={pipeline?.name || 'Pipeline Details'}
      description={`Run #${pipeline?.run_number || pipelineId}`}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Pipeline Header */}
        {pipeline && (
          <div className="bg-theme-surface rounded-lg p-6 border border-theme">
            <div className="flex items-start justify-between mb-4">
              <div className="flex items-center gap-4">
                <div className="w-14 h-14 rounded-lg bg-theme-primary/10 flex items-center justify-center">
                  <Play className="w-7 h-7 text-theme-primary" />
                </div>
                <div>
                  <h2 className="text-xl font-semibold text-theme-primary">{pipeline.name}</h2>
                  <p className="text-sm text-theme-tertiary mt-1">
                    {pipeline.trigger_event && `Triggered by ${pipeline.trigger_event}`}
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <StatusBadge status={pipeline.status} conclusion={pipeline.conclusion} large />
                {pipeline.web_url && (
                  <a
                    href={pipeline.web_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-theme-secondary hover:text-theme-primary"
                  >
                    <ExternalLink className="w-5 h-5" />
                  </a>
                )}
              </div>
            </div>

            {/* Metadata Grid */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 pt-4 border-t border-theme">
              <div className="flex items-center gap-2">
                <GitBranch className="w-4 h-4 text-theme-tertiary" />
                <div>
                  <p className="text-xs text-theme-tertiary">Branch</p>
                  <p className="text-sm text-theme-primary">{pipeline.branch_name}</p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <Hash className="w-4 h-4 text-theme-tertiary" />
                <div>
                  <p className="text-xs text-theme-tertiary">Commit</p>
                  <p className="text-sm text-theme-primary font-mono">{pipeline.short_sha || pipeline.sha?.slice(0, 7)}</p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <User className="w-4 h-4 text-theme-tertiary" />
                <div>
                  <p className="text-xs text-theme-tertiary">Actor</p>
                  <p className="text-sm text-theme-primary">{pipeline.actor_username || 'Unknown'}</p>
                </div>
              </div>
              {pipeline.duration_seconds && (
                <div className="flex items-center gap-2">
                  <Clock className="w-4 h-4 text-theme-tertiary" />
                  <div>
                    <p className="text-xs text-theme-tertiary">Duration</p>
                    <p className="text-sm text-theme-primary">{formatDuration(pipeline.duration_seconds)}</p>
                  </div>
                </div>
              )}
              <div className="flex items-center gap-2">
                <Calendar className="w-4 h-4 text-theme-tertiary" />
                <div>
                  <p className="text-xs text-theme-tertiary">Started</p>
                  <p className="text-sm text-theme-primary">
                    {pipeline.started_at
                      ? new Date(pipeline.started_at).toLocaleString()
                      : 'Not started'}
                  </p>
                </div>
              </div>
              {pipeline.completed_at && (
                <div className="flex items-center gap-2">
                  <Calendar className="w-4 h-4 text-theme-tertiary" />
                  <div>
                    <p className="text-xs text-theme-tertiary">Completed</p>
                    <p className="text-sm text-theme-primary">
                      {new Date(pipeline.completed_at).toLocaleString()}
                    </p>
                  </div>
                </div>
              )}
            </div>

          </div>
        )}

        {/* Jobs and Logs */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Jobs List */}
          <div className="bg-theme-surface rounded-lg border border-theme">
            <div className="p-4 border-b border-theme">
              <h3 className="font-medium text-theme-primary">Jobs</h3>
            </div>
            <div className="p-4">
              <JobsList
                jobs={pipeline?.jobs || []}
                selectedJobId={selectedJob?.id}
                onSelectJob={setSelectedJob}
                loading={loading && !pipeline}
              />
            </div>
          </div>

          {/* Log Viewer */}
          <div className="lg:col-span-2 bg-theme-surface rounded-lg border border-theme">
            <div className="p-4 border-b border-theme">
              <h3 className="font-medium text-theme-primary">
                {selectedJob ? `Logs: ${selectedJob.name}` : 'Job Logs'}
              </h3>
            </div>
            <div className="p-4">
              {selectedJob && repositoryId && pipelineId ? (
                <JobLogViewer
                  repositoryId={repositoryId}
                  pipelineId={pipelineId}
                  jobId={selectedJob.id}
                  jobName={selectedJob.name}
                  isJobRunning={selectedJob.status === 'running'}
                />
              ) : (
                <div className="h-96 flex items-center justify-center text-theme-secondary">
                  <p>Select a job to view its logs</p>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </PageContainer>
  );
};

export const PipelineDetailPage: React.FC = () => (
  <PageErrorBoundary>
    <PipelineDetailPageContent />
  </PageErrorBoundary>
);

export default PipelineDetailPage;
