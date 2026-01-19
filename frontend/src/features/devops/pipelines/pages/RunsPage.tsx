import React, { useState } from 'react';
import { RefreshCw, Filter } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { RunHistory } from '../components/RunHistory';
import { usePipelineRuns } from '../hooks/usePipelineRuns';
import type { CiCdPipelineRunStatus, CiCdTriggerType } from '@/types/devops-pipelines';

const RunsPageContent: React.FC = () => {
  const [statusFilter, setStatusFilter] = useState<CiCdPipelineRunStatus | 'all'>('all');
  const [triggerFilter, setTriggerFilter] = useState<CiCdTriggerType | 'all'>('all');
  const [page, setPage] = useState(1);

  const {
    runs,
    meta,
    loading,
    refresh,
    cancelRun,
    retryRun,
  } = usePipelineRuns({
    status: statusFilter === 'all' ? undefined : statusFilter,
    trigger_type: triggerFilter === 'all' ? undefined : triggerFilter,
    page,
    per_page: 20,
  });

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Automation', href: '/app/automation' },
    { label: 'Runs' }
  ];

  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'primary' as const,
      icon: RefreshCw
    }
  ];

  return (
    <PageContainer
      title="Pipeline Runs"
      description="View and manage pipeline execution history"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Filters */}
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex flex-wrap items-center gap-4">
            <div className="flex items-center gap-2">
              <Filter className="w-4 h-4 text-theme-secondary" />
              <span className="text-sm text-theme-secondary">Filters:</span>
            </div>

            <div className="flex items-center gap-2">
              <label className="text-sm text-theme-tertiary">Status:</label>
              <select
                value={statusFilter}
                onChange={(e) => {
                  setStatusFilter(e.target.value as CiCdPipelineRunStatus | 'all');
                  setPage(1);
                }}
                className="px-3 py-1.5 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
              >
                <option value="all">All</option>
                <option value="pending">Pending</option>
                <option value="running">Running</option>
                <option value="success">Success</option>
                <option value="failed">Failed</option>
                <option value="cancelled">Cancelled</option>
              </select>
            </div>

            <div className="flex items-center gap-2">
              <label className="text-sm text-theme-tertiary">Trigger:</label>
              <select
                value={triggerFilter}
                onChange={(e) => {
                  setTriggerFilter(e.target.value as CiCdTriggerType | 'all');
                  setPage(1);
                }}
                className="px-3 py-1.5 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
              >
                <option value="all">All</option>
                <option value="manual">Manual</option>
                <option value="webhook">Webhook</option>
                <option value="schedule">Schedule</option>
                <option value="retry">Retry</option>
              </select>
            </div>

            {(statusFilter !== 'all' || triggerFilter !== 'all') && (
              <Button
                onClick={() => {
                  setStatusFilter('all');
                  setTriggerFilter('all');
                  setPage(1);
                }}
                variant="ghost"
                size="sm"
              >
                Clear Filters
              </Button>
            )}
          </div>

          {/* Status Counts */}
          {meta?.status_counts && (
            <div className="mt-4 pt-4 border-t border-theme flex items-center gap-4 text-xs">
              {Object.entries(meta.status_counts).map(([status, count]) => (
                <button
                  key={status}
                  onClick={() => {
                    setStatusFilter(status as CiCdPipelineRunStatus);
                    setPage(1);
                  }}
                  className={`px-2 py-1 rounded transition-colors ${
                    statusFilter === status
                      ? 'bg-theme-primary/10 text-theme-primary'
                      : 'text-theme-secondary hover:text-theme-primary'
                  }`}
                >
                  {status}: {count}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Run History */}
        <RunHistory
          runs={runs}
          loading={loading}
          onCancel={cancelRun}
          onRetry={retryRun}
        />

        {/* Pagination */}
        {meta && meta.total_pages > 1 && (
          <div className="flex items-center justify-between">
            <p className="text-sm text-theme-secondary">
              Showing {runs.length} of {meta.total} runs
            </p>
            <div className="flex items-center gap-2">
              <Button
                onClick={() => setPage(Math.max(1, page - 1))}
                variant="secondary"
                size="sm"
                disabled={page === 1}
              >
                Previous
              </Button>
              <span className="text-sm text-theme-secondary">
                Page {page} of {meta.total_pages}
              </span>
              <Button
                onClick={() => setPage(Math.min(meta.total_pages, page + 1))}
                variant="secondary"
                size="sm"
                disabled={page === meta.total_pages}
              >
                Next
              </Button>
            </div>
          </div>
        )}
      </div>
    </PageContainer>
  );
};

export const RunsPage: React.FC = () => (
  <PageErrorBoundary>
    <RunsPageContent />
  </PageErrorBoundary>
);

export default RunsPage;
