import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  GitBranch, Play, RefreshCw, ExternalLink, Clock, Filter,
  XCircle, RotateCcw, ChevronDown
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import { useNotification } from '@/shared/hooks/useNotification';
import { PipelineStatsCards } from './PipelineStatsCards';
import type { GitPipeline, PipelineStats, PaginationInfo, PipelineFilters } from '../types';
import type { GitRepository } from '@/features/git-providers/types';

const StatusBadge: React.FC<{ status: string; conclusion?: string }> = ({ status, conclusion }) => {
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
  return (
    <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium ${config.bg} ${config.text}`}>
      {config.label}
    </span>
  );
};

const formatDuration = (seconds: number): string => {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m ${Math.round(seconds % 60)}s`;
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
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
};

interface PipelineRowProps {
  pipeline: GitPipeline;
  onClick: () => void;
  onCancel?: () => void;
  onRetry?: () => void;
}

const PipelineRow: React.FC<PipelineRowProps> = ({ pipeline, onClick, onCancel, onRetry }) => {
  const canCancel = pipeline.status === 'running' || pipeline.status === 'pending';
  const canRetry = pipeline.status === 'completed' && pipeline.conclusion === 'failure';

  return (
    <div
      className="flex items-center justify-between p-4 hover:bg-theme-surface-hover rounded-lg transition-colors cursor-pointer border-b border-theme last:border-b-0"
      onClick={onClick}
    >
      <div className="flex items-center gap-4 min-w-0 flex-1">
        <Play className="w-5 h-5 text-theme-secondary flex-shrink-0" />
        <div className="min-w-0">
          <p className="font-medium text-theme-primary truncate">{pipeline.name}</p>
          <div className="flex items-center gap-2 text-xs text-theme-tertiary mt-1">
            <span className="bg-theme-secondary/10 px-2 py-0.5 rounded">{pipeline.branch_name}</span>
            <span>{pipeline.short_sha || pipeline.sha?.slice(0, 7)}</span>
            {pipeline.actor_username && <span>by {pipeline.actor_username}</span>}
          </div>
        </div>
      </div>

      <div className="flex items-center gap-4">
        {pipeline.duration_seconds && (
          <div className="flex items-center gap-1 text-xs text-theme-tertiary">
            <Clock className="w-3.5 h-3.5" />
            {formatDuration(pipeline.duration_seconds)}
          </div>
        )}
        <StatusBadge status={pipeline.status} conclusion={pipeline.conclusion} />
        <span className="text-xs text-theme-tertiary min-w-[70px] text-right">
          {formatTimeAgo(pipeline.created_at)}
        </span>

        <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
          {canCancel && onCancel && (
            <Button onClick={onCancel} variant="ghost" size="sm" title="Cancel pipeline">
              <XCircle className="w-4 h-4" />
            </Button>
          )}
          {canRetry && onRetry && (
            <Button onClick={onRetry} variant="ghost" size="sm" title="Retry pipeline">
              <RotateCcw className="w-4 h-4" />
            </Button>
          )}
          {pipeline.web_url && (
            <a
              href={pipeline.web_url}
              target="_blank"
              rel="noopener noreferrer"
              className="p-2 text-theme-secondary hover:text-theme-primary"
              title="View on provider"
            >
              <ExternalLink className="w-4 h-4" />
            </a>
          )}
        </div>
      </div>
    </div>
  );
};

const RepositoryPipelinesPageContent: React.FC = () => {
  const { repositoryId } = useParams<{ repositoryId: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotification();

  const [repository, setRepository] = useState<GitRepository | null>(null);
  const [pipelines, setPipelines] = useState<GitPipeline[]>([]);
  const [stats, setStats] = useState<PipelineStats | null>(null);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState<PipelineFilters>({
    status: 'all',
    conclusion: 'all',
  });
  const [showFilters, setShowFilters] = useState(false);

  const fetchData = useCallback(async () => {
    if (!repositoryId) return;

    try {
      setLoading(true);
      setError(null);

      // Fetch repository details and pipelines in parallel
      const [repoData, pipelinesData] = await Promise.all([
        gitProvidersApi.getRepository(repositoryId),
        gitProvidersApi.getPipelines(repositoryId, {
          page,
          per_page: 20,
          status: filters.status !== 'all' ? filters.status : undefined,
          conclusion: filters.conclusion !== 'all' ? filters.conclusion : undefined,
          ref: filters.branch,
        }),
      ]);

      setRepository(repoData);
      setPipelines(pipelinesData.pipelines);
      setStats(pipelinesData.stats);
      setPagination(pipelinesData.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch data');
    } finally {
      setLoading(false);
    }
  }, [repositoryId, page, filters]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const handleCancelPipeline = async (pipelineId: string) => {
    if (!repositoryId) return;
    try {
      await gitProvidersApi.cancelPipeline(repositoryId, pipelineId);
      showNotification('Pipeline cancelled', 'success');
      fetchData();
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to cancel pipeline', 'error');
    }
  };

  const handleRetryPipeline = async (pipelineId: string) => {
    if (!repositoryId) return;
    try {
      await gitProvidersApi.retryPipeline(repositoryId, pipelineId);
      showNotification('Pipeline retry started', 'success');
      fetchData();
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to retry pipeline', 'error');
    }
  };

  const breadcrumbs = [
    { label: 'CI/CD', href: '/app/ci-cd', icon: Play },
    { label: 'Repositories', href: '/app/ci-cd/repositories' },
    { label: repository?.name || 'Repository' }
  ];

  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: fetchData,
      variant: 'primary' as const,
      icon: RefreshCw
    }
  ];

  if (error) {
    return (
      <PageContainer
        title="Repository Pipelines"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
        <div className="bg-theme-error/10 border border-theme-error rounded-lg p-4">
          <p className="text-theme-error">{error}</p>
          <Button onClick={fetchData} variant="secondary" size="sm" className="mt-2">
            Try Again
          </Button>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={repository?.name || 'Repository Pipelines'}
      description={repository?.full_name}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Repository Header */}
        {repository && (
          <div className="bg-theme-surface rounded-lg p-4 border border-theme">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-lg bg-theme-primary/10 flex items-center justify-center">
                  <GitBranch className="w-6 h-6 text-theme-primary" />
                </div>
                <div>
                  <h2 className="text-lg font-semibold text-theme-primary">{repository.name}</h2>
                  <p className="text-sm text-theme-tertiary">{repository.full_name}</p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-sm text-theme-tertiary capitalize">{repository.provider_type}</span>
                {repository.web_url && (
                  <a
                    href={repository.web_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-theme-secondary hover:text-theme-primary"
                  >
                    <ExternalLink className="w-5 h-5" />
                  </a>
                )}
              </div>
            </div>
          </div>
        )}

        {/* Stats */}
        <PipelineStatsCards stats={stats} loading={loading} />

        {/* Filters */}
        <div className="flex items-center justify-between">
          <Button
            onClick={() => setShowFilters(!showFilters)}
            variant="secondary"
            size="sm"
          >
            <Filter className="w-4 h-4 mr-2" />
            Filters
            <ChevronDown className={`w-4 h-4 ml-2 transition-transform ${showFilters ? 'rotate-180' : ''}`} />
          </Button>
          {(filters.status !== 'all' || filters.conclusion !== 'all' || filters.branch) && (
            <Button
              onClick={() => {
                setFilters({ status: 'all', conclusion: 'all' });
                setPage(1);
              }}
              variant="ghost"
              size="sm"
            >
              Clear Filters
            </Button>
          )}
        </div>

        {showFilters && (
          <div className="bg-theme-surface rounded-lg p-4 border border-theme flex flex-wrap gap-4">
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Status</label>
              <select
                value={filters.status || 'all'}
                onChange={(e) => {
                  setFilters({ ...filters, status: e.target.value as PipelineFilters['status'] });
                  setPage(1);
                }}
                className="bg-theme-surface border border-theme rounded-lg px-3 py-2 text-sm text-theme-primary"
              >
                <option value="all">All Statuses</option>
                <option value="pending">Pending</option>
                <option value="running">Running</option>
                <option value="completed">Completed</option>
                <option value="cancelled">Cancelled</option>
              </select>
            </div>
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Conclusion</label>
              <select
                value={filters.conclusion || 'all'}
                onChange={(e) => {
                  setFilters({ ...filters, conclusion: e.target.value as PipelineFilters['conclusion'] });
                  setPage(1);
                }}
                className="bg-theme-surface border border-theme rounded-lg px-3 py-2 text-sm text-theme-primary"
              >
                <option value="all">All Conclusions</option>
                <option value="success">Success</option>
                <option value="failure">Failure</option>
                <option value="cancelled">Cancelled</option>
                <option value="skipped">Skipped</option>
              </select>
            </div>
          </div>
        )}

        {/* Pipelines List */}
        <div className="bg-theme-surface rounded-lg border border-theme">
          <div className="p-4 border-b border-theme">
            <h3 className="font-medium text-theme-primary">Pipelines</h3>
          </div>
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <LoadingSpinner size="md" />
              <span className="ml-3 text-theme-secondary">Loading pipelines...</span>
            </div>
          ) : pipelines.length > 0 ? (
            <>
              <div className="divide-y divide-theme">
                {pipelines.map((pipeline) => (
                  <PipelineRow
                    key={pipeline.id}
                    pipeline={pipeline}
                    onClick={() => navigate(`/app/ci-cd/repositories/${repositoryId}/pipelines/${pipeline.id}`)}
                    onCancel={() => handleCancelPipeline(pipeline.id)}
                    onRetry={() => handleRetryPipeline(pipeline.id)}
                  />
                ))}
              </div>

              {/* Pagination */}
              {pagination && pagination.total_pages > 1 && (
                <div className="flex items-center justify-between p-4 border-t border-theme">
                  <p className="text-sm text-theme-tertiary">
                    Showing {pipelines.length} of {pagination.total_count} pipelines
                  </p>
                  <div className="flex items-center gap-2">
                    <Button
                      onClick={() => setPage((p) => Math.max(1, p - 1))}
                      disabled={page === 1}
                      variant="secondary"
                      size="sm"
                    >
                      Previous
                    </Button>
                    <span className="text-sm text-theme-secondary">
                      Page {page} of {pagination.total_pages}
                    </span>
                    <Button
                      onClick={() => setPage((p) => Math.min(pagination.total_pages, p + 1))}
                      disabled={page >= pagination.total_pages}
                      variant="secondary"
                      size="sm"
                    >
                      Next
                    </Button>
                  </div>
                </div>
              )}
            </>
          ) : (
            <div className="p-8 text-center">
              <Play className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
              <h3 className="text-lg font-medium text-theme-primary mb-2">No Pipelines Found</h3>
              <p className="text-theme-secondary">
                {filters.status !== 'all' || filters.conclusion !== 'all'
                  ? 'Try adjusting your filters.'
                  : 'No pipeline runs have been recorded for this repository yet.'}
              </p>
            </div>
          )}
        </div>
      </div>
    </PageContainer>
  );
};

export const RepositoryPipelinesPage: React.FC = () => (
  <PageErrorBoundary>
    <RepositoryPipelinesPageContent />
  </PageErrorBoundary>
);

export default RepositoryPipelinesPage;
