import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Package, RefreshCw, Layers } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useAuth } from '@/shared/hooks/useAuth';
import { useModuleBuildBatches } from '../hooks';
import { BatchStatusBadge } from '../components/BatchStatusBadge';
import { CancelBatchButton } from '../components/CancelBatchButton';
import type { ModuleBuildBatch, ModuleBuildBatchStatus } from '../types';

const STATUS_OPTIONS: ModuleBuildBatchStatus[] = [
  'planning', 'dispatched', 'awaiting_signature', 'publishing', 'complete', 'partial', 'failed', 'cancelled',
];
const TRIGGER_OPTIONS = ['push', 'manual', 'cve', 'package'];

const formatTimeAgo = (dateString: string): string => {
  const diffMs = Date.now() - new Date(dateString).getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);
  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  return `${diffDays}d ago`;
};

const ModuleSlugsCell: React.FC<{ slugs: string[] }> = ({ slugs }) => {
  if (slugs.length === 0) return <span className="text-theme-tertiary text-xs">—</span>;
  const shown = slugs.slice(0, 2);
  const rest = slugs.length - shown.length;
  return (
    <div className="flex flex-wrap items-center gap-1">
      {shown.map((slug) => (
        <span key={slug} className="inline-flex items-center px-2 py-0.5 rounded text-xs bg-theme-primary/10 text-theme-primary">
          {slug}
        </span>
      ))}
      {rest > 0 && <span className="text-xs text-theme-tertiary">+{rest} more</span>}
    </div>
  );
};

const ProgressCell: React.FC<{ batch: ModuleBuildBatch }> = ({ batch }) => (
  <span className="text-sm text-theme-primary">
    <span className="text-theme-success-fg">{batch.succeeded_count}</span>
    {batch.failed_count > 0 && <span className="text-theme-error-fg">/{batch.failed_count}</span>}
    <span className="text-theme-tertiary"> of {batch.planned_count}</span>
  </span>
);

const BatchRow: React.FC<{ batch: ModuleBuildBatch; onClick: () => void; onCancelled: () => void }> = ({
  batch,
  onClick,
  onCancelled,
}) => (
  <div
    className="px-4 py-3 border-b border-theme last:border-b-0 hover:bg-theme-surface-hover cursor-pointer transition-colors"
    onClick={onClick}
  >
    <div className="flex items-center gap-3">
      <BatchStatusBadge status={batch.status} />
      <span className="text-xs text-theme-tertiary px-2 py-0.5 bg-theme-surface-secondary rounded capitalize">
        {batch.trigger}
      </span>
      {batch.shadow && (
        <span className="inline-flex items-center gap-1 text-xs text-theme-info-fg px-2 py-0.5 bg-theme-info-fg/10 rounded">
          <Layers className="w-3 h-3" />
          Shadow
        </span>
      )}
      <div className="flex-1 min-w-0">
        <ModuleSlugsCell slugs={batch.module_slugs} />
      </div>
      <ProgressCell batch={batch} />
      <span className="text-xs text-theme-tertiary w-20 text-right">{formatTimeAgo(batch.created_at)}</span>
      <CancelBatchButton batch={batch} onCancelled={onCancelled} variant="icon" />
    </div>
    {batch.status === 'failed' && (
      <p className="mt-2 ml-1 text-xs text-theme-error-fg truncate">
        {/* index rows have no error_message field — surfaced on the detail page */}
        Build failed — open for details
      </p>
    )}
  </div>
);

interface ModuleBuildsPageProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

const ModuleBuildsPageContent: React.FC<ModuleBuildsPageProps> = ({ onActionsReady }) => {
  const navigate = useNavigate();
  const { currentUser } = useAuth();
  const [statusFilter, setStatusFilter] = useState('');
  const [triggerFilter, setTriggerFilter] = useState('');
  const [page, setPage] = useState(1);

  const canRead = currentUser?.permissions?.includes('system.module_builds.read');

  const { batches, meta, loading, error, refresh } = useModuleBuildBatches(
    { status: statusFilter || undefined, trigger: triggerFilter || undefined, page },
    canRead
  );

  useEffect(() => {
    const pageActions: PageAction[] = [
      { id: 'refresh', label: 'Refresh', onClick: refresh, variant: 'secondary' as const, icon: RefreshCw },
    ];
    onActionsReady?.(pageActions);
  }, [onActionsReady, refresh]);

  if (!canRead) {
    return (
      <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
        <p className="text-theme-secondary">You don't have permission to view module build batches.</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row gap-4">
        <select
          value={statusFilter}
          onChange={(e) => {
            setStatusFilter(e.target.value);
            setPage(1);
          }}
          className="px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary"
        >
          <option value="">All Statuses</option>
          {STATUS_OPTIONS.map((s) => (
            <option key={s} value={s}>{s.replace(/_/g, ' ')}</option>
          ))}
        </select>
        <select
          value={triggerFilter}
          onChange={(e) => {
            setTriggerFilter(e.target.value);
            setPage(1);
          }}
          className="px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary"
        >
          <option value="">All Triggers</option>
          {TRIGGER_OPTIONS.map((t) => (
            <option key={t} value={t} className="capitalize">{t}</option>
          ))}
        </select>
      </div>

      {error && (
        <div className="bg-theme-error-fg/10 border border-theme-error-border rounded-lg p-4">
          <p className="text-theme-error-fg">{error}</p>
          <Button onClick={refresh} variant="secondary" size="sm" className="mt-2">
            Try Again
          </Button>
        </div>
      )}

      {loading && (
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
          <span className="ml-3 text-theme-secondary">Loading module build batches...</span>
        </div>
      )}

      {!loading && !error && batches.length === 0 && (
        <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
          <Package className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">No Module Build Batches Found</h3>
          <p className="text-theme-secondary">
            {statusFilter || triggerFilter
              ? 'Try adjusting your filters.'
              : 'Module build batches appear here once a platform module build is dispatched.'}
          </p>
        </div>
      )}

      {!loading && !error && batches.length > 0 && (
        <>
          <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
            {batches.map((batch) => (
              <BatchRow
                key={batch.id}
                batch={batch}
                onClick={() => navigate(`/app/devops/ci-cd/module-builds/${batch.id}`)}
                onCancelled={refresh}
              />
            ))}
          </div>

          {meta && meta.total_pages > 1 && (
            <div className="flex items-center justify-between pt-4 border-t border-theme">
              <p className="text-sm text-theme-tertiary">
                Showing {batches.length} of {meta.total_count} batches
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
                  Page {meta.current_page} of {meta.total_pages}
                </span>
                <Button
                  onClick={() => setPage((p) => Math.min(meta.total_pages, p + 1))}
                  disabled={page >= meta.total_pages}
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
  );
};

export const ModuleBuildsPage: React.FC<ModuleBuildsPageProps> = ({ onActionsReady }) => (
  <PageErrorBoundary>
    <ModuleBuildsPageContent onActionsReady={onActionsReady} />
  </PageErrorBoundary>
);

export default ModuleBuildsPage;
