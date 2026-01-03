import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Play, GitBranch, Webhook, RefreshCw, ExternalLink, Clock } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PipelineStatsCards } from './PipelineStatsCards';
import { useCICDDashboard } from '../hooks/useCICDDashboard';
import type { GitPipeline } from '../types';
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
    <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${config.bg} ${config.text}`}>
      {config.label}
    </span>
  );
};

const formatDuration = (seconds: number): string => {
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

const PipelineRow: React.FC<{ pipeline: GitPipeline; onClick: () => void }> = ({ pipeline, onClick }) => (
  <button
    onClick={onClick}
    className="w-full flex items-center justify-between p-3 hover:bg-theme-surface-hover rounded-lg transition-colors text-left"
  >
    <div className="flex items-center gap-3 min-w-0 flex-1">
      <Play className="w-4 h-4 text-theme-secondary flex-shrink-0" />
      <div className="min-w-0">
        <p className="text-sm font-medium text-theme-primary truncate">{pipeline.name}</p>
        <p className="text-xs text-theme-tertiary truncate">
          {pipeline.branch_name} • {pipeline.short_sha || pipeline.sha?.slice(0, 7)}
        </p>
      </div>
    </div>
    <div className="flex items-center gap-3">
      {pipeline.duration_seconds && (
        <span className="text-xs text-theme-tertiary flex items-center gap-1">
          <Clock className="w-3 h-3" />
          {formatDuration(pipeline.duration_seconds)}
        </span>
      )}
      <StatusBadge status={pipeline.status} conclusion={pipeline.conclusion} />
      <span className="text-xs text-theme-tertiary">{formatTimeAgo(pipeline.created_at)}</span>
    </div>
  </button>
);

const RepositoryCard: React.FC<{ repository: GitRepository; onClick: () => void }> = ({ repository, onClick }) => (
  <button
    onClick={onClick}
    className="w-full bg-theme-surface rounded-lg p-4 border border-theme hover:border-theme-primary transition-colors text-left"
  >
    <div className="flex items-start justify-between">
      <div className="flex items-center gap-3">
        <GitBranch className="w-5 h-5 text-theme-primary" />
        <div>
          <p className="font-medium text-theme-primary">{repository.name}</p>
          <p className="text-xs text-theme-tertiary">{repository.full_name}</p>
        </div>
      </div>
      {repository.web_url && (
        <a
          href={repository.web_url}
          target="_blank"
          rel="noopener noreferrer"
          onClick={(e) => e.stopPropagation()}
          className="text-theme-secondary hover:text-theme-primary"
        >
          <ExternalLink className="w-4 h-4" />
        </a>
      )}
    </div>
    <div className="mt-3 flex items-center gap-4 text-xs text-theme-tertiary">
      <span>{repository.provider_type}</span>
      <span className={repository.webhook_configured ? 'text-theme-success' : 'text-theme-warning'}>
        {repository.webhook_configured ? 'Webhook active' : 'No webhook'}
      </span>
    </div>
  </button>
);

const CICDDashboardPageContent: React.FC = () => {
  const navigate = useNavigate();
  const { repositories = [], recentPipelines = [], globalStats, loading, error, refresh } = useCICDDashboard();

  const breadcrumbs = [
    { label: 'CI/CD', icon: Play },
    { label: 'Dashboard' }
  ];

  const actions = [
    {
      id: 'repositories',
      label: 'All Repositories',
      onClick: () => navigate('/app/ci-cd/repositories'),
      variant: 'secondary' as const,
      icon: GitBranch
    },
    {
      id: 'webhooks',
      label: 'Webhook Events',
      onClick: () => navigate('/app/ci-cd/webhooks'),
      variant: 'secondary' as const,
      icon: Webhook
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'primary' as const,
      icon: RefreshCw
    }
  ];

  if (error) {
    return (
      <PageContainer
        title="CI/CD Dashboard"
        description="Pipeline overview and recent activity"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
        <div className="bg-theme-error/10 border border-theme-error rounded-lg p-4">
          <p className="text-theme-error">{error}</p>
          <Button onClick={refresh} variant="secondary" size="sm" className="mt-2">
            Try Again
          </Button>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="CI/CD Dashboard"
      description="Pipeline overview and recent activity"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Global Stats */}
        <PipelineStatsCards stats={globalStats} loading={loading} />

        {/* Empty State */}
        {!loading && repositories.length === 0 && (
          <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
            <GitBranch className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">No Repositories Connected</h3>
            <p className="text-theme-secondary mb-4">
              Connect repositories from your Git providers to start tracking pipelines.
            </p>
            <Button onClick={() => navigate('/app/system/git-providers')} variant="primary">
              Configure Git Providers
            </Button>
          </div>
        )}

        {/* Main Content */}
        {repositories.length > 0 && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Recent Pipelines */}
            <div className="bg-theme-surface rounded-lg border border-theme">
              <div className="p-4 border-b border-theme">
                <h3 className="font-medium text-theme-primary">Recent Pipelines</h3>
              </div>
              <div className="p-2">
                {loading ? (
                  <div className="flex items-center justify-center py-8">
                    <LoadingSpinner size="md" />
                  </div>
                ) : recentPipelines.length > 0 ? (
                  <div className="space-y-1">
                    {recentPipelines.slice(0, 10).map((pipeline) => (
                      <PipelineRow
                        key={pipeline.id}
                        pipeline={pipeline}
                        onClick={() => navigate(`/app/ci-cd/repositories/${pipeline.repository_id}/pipelines/${pipeline.id}`)}
                      />
                    ))}
                  </div>
                ) : (
                  <p className="text-center text-theme-secondary py-8">No recent pipelines</p>
                )}
              </div>
            </div>

            {/* Repositories */}
            <div className="bg-theme-surface rounded-lg border border-theme">
              <div className="p-4 border-b border-theme flex items-center justify-between">
                <h3 className="font-medium text-theme-primary">Repositories</h3>
                <Button
                  onClick={() => navigate('/app/ci-cd/repositories')}
                  variant="ghost"
                  size="sm"
                >
                  View All
                </Button>
              </div>
              <div className="p-4">
                {loading ? (
                  <div className="flex items-center justify-center py-8">
                    <LoadingSpinner size="md" />
                  </div>
                ) : (
                  <div className="space-y-3">
                    {repositories.slice(0, 6).map((repo) => (
                      <RepositoryCard
                        key={repo.id}
                        repository={repo}
                        onClick={() => navigate(`/app/ci-cd/repositories/${repo.id}`)}
                      />
                    ))}
                  </div>
                )}
              </div>
            </div>
          </div>
        )}
      </div>
    </PageContainer>
  );
};

export const CICDDashboardPage: React.FC = () => (
  <PageErrorBoundary>
    <CICDDashboardPageContent />
  </PageErrorBoundary>
);

export default CICDDashboardPage;
