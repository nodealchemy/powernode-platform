import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Server, Search, RefreshCw, Play, Trash2, Activity, Cpu } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAuth } from '@/shared/hooks/useAuth';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import type { GitRunner, RunnerStats, PaginationInfo } from '@/features/git-providers/types';

const StatusBadge: React.FC<{ status: string; busy: boolean }> = ({ status, busy }) => {
  const getStatusStyles = () => {
    if (busy) return 'bg-theme-warning/10 text-theme-warning';
    switch (status) {
      case 'online':
        return 'bg-theme-success/10 text-theme-success';
      case 'offline':
        return 'bg-theme-error/10 text-theme-error';
      default:
        return 'bg-theme-secondary/10 text-theme-secondary';
    }
  };

  return (
    <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${getStatusStyles()}`}>
      <span className={`w-1.5 h-1.5 rounded-full mr-1.5 ${
        busy ? 'bg-theme-warning' :
        status === 'online' ? 'bg-theme-success animate-pulse' :
        'bg-theme-error'
      }`} />
      {busy ? 'Busy' : status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  );
};

const RunnerCard: React.FC<{
  runner: GitRunner;
  onClick: () => void;
  onDelete?: () => void;
  canDelete?: boolean;
}> = ({ runner, onClick, onDelete, canDelete }) => (
  <div
    className="bg-theme-surface rounded-lg p-4 border border-theme hover:border-theme-primary transition-colors cursor-pointer"
    onClick={onClick}
  >
    <div className="flex items-start justify-between mb-3">
      <div className="flex items-center gap-3">
        <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${
          runner.status === 'online' ? 'bg-theme-success/10' : 'bg-theme-secondary/10'
        }`}>
          <Server className={`w-5 h-5 ${
            runner.status === 'online' ? 'text-theme-success' : 'text-theme-secondary'
          }`} />
        </div>
        <div>
          <h3 className="font-medium text-theme-primary">{runner.name}</h3>
          <p className="text-xs text-theme-tertiary">ID: {runner.external_id}</p>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <StatusBadge status={runner.status} busy={runner.busy} />
        {canDelete && onDelete && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onDelete();
            }}
            className="text-theme-secondary hover:text-theme-error p-1"
          >
            <Trash2 className="w-4 h-4" />
          </button>
        )}
      </div>
    </div>

    {/* Labels */}
    {runner.labels && runner.labels.length > 0 && (
      <div className="flex flex-wrap gap-1 mb-3">
        {runner.labels.slice(0, 5).map((label, idx) => (
          <span
            key={idx}
            className="inline-flex items-center px-2 py-0.5 rounded text-xs bg-theme-primary/10 text-theme-primary"
          >
            {label}
          </span>
        ))}
        {runner.labels.length > 5 && (
          <span className="text-xs text-theme-tertiary">+{runner.labels.length - 5} more</span>
        )}
      </div>
    )}

    {/* Stats */}
    <div className="flex items-center justify-between text-xs text-theme-tertiary">
      <div className="flex items-center gap-3">
        {runner.os && <span className="flex items-center gap-1"><Cpu className="w-3 h-3" />{runner.os}</span>}
        {runner.architecture && <span>{runner.architecture}</span>}
      </div>
      <div className="flex items-center gap-3">
        <span className="flex items-center gap-1">
          <Activity className="w-3 h-3" />
          {runner.total_jobs_run} jobs
        </span>
        <span className="text-theme-success">{runner.success_rate.toFixed(0)}% success</span>
      </div>
    </div>
  </div>
);

const StatsCards: React.FC<{ stats: RunnerStats }> = ({ stats }) => (
  <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
    <div className="bg-theme-surface rounded-lg p-4 border border-theme">
      <div className="flex items-center gap-2 text-theme-secondary mb-1">
        <Server className="w-4 h-4" />
        <span className="text-sm">Total</span>
      </div>
      <p className="text-2xl font-bold text-theme-primary">{stats.total}</p>
    </div>
    <div className="bg-theme-surface rounded-lg p-4 border border-theme">
      <div className="flex items-center gap-2 text-theme-success mb-1">
        <span className="w-2 h-2 rounded-full bg-theme-success animate-pulse" />
        <span className="text-sm">Online</span>
      </div>
      <p className="text-2xl font-bold text-theme-success">{stats.online}</p>
    </div>
    <div className="bg-theme-surface rounded-lg p-4 border border-theme">
      <div className="flex items-center gap-2 text-theme-warning mb-1">
        <Activity className="w-4 h-4" />
        <span className="text-sm">Busy</span>
      </div>
      <p className="text-2xl font-bold text-theme-warning">{stats.busy}</p>
    </div>
    <div className="bg-theme-surface rounded-lg p-4 border border-theme">
      <div className="flex items-center gap-2 text-theme-error mb-1">
        <span className="w-2 h-2 rounded-full bg-theme-error" />
        <span className="text-sm">Offline</span>
      </div>
      <p className="text-2xl font-bold text-theme-error">{stats.offline}</p>
    </div>
  </div>
);

const RunnersPageContent: React.FC = () => {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const { currentUser } = useAuth();
  const [runners, setRunners] = useState<GitRunner[]>([]);
  const [stats, setStats] = useState<RunnerStats | null>(null);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [page, setPage] = useState(1);

  const canManageRunners = currentUser?.permissions?.includes('git.runners.manage');

  const fetchRunners = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getRunners({
        page,
        per_page: 20,
        search: searchQuery || undefined,
        status: statusFilter || undefined,
      });
      setRunners(data.runners);
      setStats(data.stats);
      setPagination(data.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch runners');
    } finally {
      setLoading(false);
    }
  }, [page, searchQuery, statusFilter]);

  useEffect(() => {
    fetchRunners();
  }, [fetchRunners]);

  const handleSync = async () => {
    try {
      setSyncing(true);
      const result = await gitProvidersApi.syncRunners();
      showNotification(`Synced ${result.synced_count} runners from providers`, 'success');
      fetchRunners();
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to sync runners', 'error');
    } finally {
      setSyncing(false);
    }
  };

  const handleDelete = async (runner: GitRunner) => {
    if (!window.confirm(`Are you sure you want to delete runner "${runner.name}"?`)) {
      return;
    }
    try {
      await gitProvidersApi.deleteRunner(runner.id);
      showNotification('Runner deleted successfully', 'success');
      fetchRunners();
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to delete runner', 'error');
    }
  };

  const breadcrumbs = [
    { label: 'CI/CD', href: '/app/ci-cd', icon: Play },
    { label: 'Runners' }
  ];

  const actions = [
    {
      id: 'sync',
      label: syncing ? 'Syncing...' : 'Sync Runners',
      onClick: handleSync,
      variant: 'primary' as const,
      icon: RefreshCw,
      disabled: syncing
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: fetchRunners,
      variant: 'secondary' as const,
      icon: RefreshCw
    }
  ];

  return (
    <PageContainer
      title="CI/CD Runners"
      description="Manage self-hosted runners for GitHub Actions and Gitea Actions"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Stats Cards */}
        {stats && <StatsCards stats={stats} />}

        {/* Filters */}
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
            <Input
              type="text"
              placeholder="Search runners..."
              value={searchQuery}
              onChange={(e) => {
                setSearchQuery(e.target.value);
                setPage(1);
              }}
              className="pl-10"
            />
          </div>
          <select
            value={statusFilter}
            onChange={(e) => {
              setStatusFilter(e.target.value);
              setPage(1);
            }}
            className="px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary"
          >
            <option value="">All Statuses</option>
            <option value="online">Online</option>
            <option value="offline">Offline</option>
            <option value="busy">Busy</option>
          </select>
        </div>

        {/* Error State */}
        {error && (
          <div className="bg-theme-error/10 border border-theme-error rounded-lg p-4">
            <p className="text-theme-error">{error}</p>
            <Button onClick={fetchRunners} variant="secondary" size="sm" className="mt-2">
              Try Again
            </Button>
          </div>
        )}

        {/* Loading State */}
        {loading && (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner size="lg" />
            <span className="ml-3 text-theme-secondary">Loading runners...</span>
          </div>
        )}

        {/* Empty State */}
        {!loading && !error && runners.length === 0 && (
          <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
            <Server className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">No Runners Found</h3>
            <p className="text-theme-secondary mb-4">
              {searchQuery || statusFilter
                ? 'Try adjusting your filters.'
                : 'Sync runners from your Git providers or add self-hosted runners to get started.'}
            </p>
            {!searchQuery && !statusFilter && (
              <Button onClick={handleSync} variant="primary">
                <RefreshCw className="w-4 h-4 mr-2" />
                Sync Runners
              </Button>
            )}
          </div>
        )}

        {/* Runner Grid */}
        {!loading && !error && runners.length > 0 && (
          <>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {runners.map((runner) => (
                <RunnerCard
                  key={runner.id}
                  runner={runner}
                  onClick={() => navigate(`/app/ci-cd/runners/${runner.id}`)}
                  onDelete={() => handleDelete(runner)}
                  canDelete={canManageRunners}
                />
              ))}
            </div>

            {/* Pagination */}
            {pagination && pagination.total_pages > 1 && (
              <div className="flex items-center justify-between pt-4 border-t border-theme">
                <p className="text-sm text-theme-tertiary">
                  Showing {runners.length} of {pagination.total_count} runners
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
        )}
      </div>
    </PageContainer>
  );
};

export const RunnersPage: React.FC = () => (
  <PageErrorBoundary>
    <RunnersPageContent />
  </PageErrorBoundary>
);

export default RunnersPage;
