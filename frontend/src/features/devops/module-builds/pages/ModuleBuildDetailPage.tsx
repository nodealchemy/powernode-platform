import React from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, RefreshCw, CheckCircle2, Circle, Layers, GitCommit, Package } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { DataTable, type DataTableColumn } from '@/shared/components/ui/DataTable';
import { useAuth } from '@/shared/hooks/useAuth';
import { useModuleBuildBatch } from '../hooks';
import { BatchStatusBadge } from '../components/BatchStatusBadge';
import { CancelBatchButton } from '../components/CancelBatchButton';
import type { ModuleBuildMember } from '../types';

const formatTimestamp = (value: string | null): string => (value ? new Date(value).toLocaleString() : '—');

const shortSha = (sha: string | null): string => (sha ? sha.slice(0, 10) : '—');

/** dispatched → awaiting_signature → publishing → completed/failed/cancelled AASM ladder. */
const TimestampLadder: React.FC<{
  dispatchedAt: string | null;
  awaitingSignatureAt: string | null;
  publishingAt: string | null;
  completedAt: string | null;
  failedAt: string | null;
  cancelledAt: string | null;
}> = ({ dispatchedAt, awaitingSignatureAt, publishingAt, completedAt, failedAt, cancelledAt }) => {
  const failed = !!failedAt;
  const cancelled = !cancelledAt ? false : !failed;
  const terminal = failed
    ? { label: 'Failed', ts: failedAt }
    : cancelled
      ? { label: 'Cancelled', ts: cancelledAt }
      : { label: 'Completed', ts: completedAt };
  const steps = [
    { label: 'Dispatched', ts: dispatchedAt },
    { label: 'Awaiting Signature', ts: awaitingSignatureAt },
    { label: 'Publishing', ts: publishingAt },
    terminal,
  ];

  return (
    <div className="flex flex-col sm:flex-row sm:items-start gap-4 sm:gap-0">
      {steps.map((step, idx) => (
        <div key={step.label} className="flex sm:flex-1 items-start gap-3 sm:flex-col sm:items-center sm:text-center">
          <div className="flex items-center sm:flex-col">
            {step.ts ? (
              <CheckCircle2
                className={`w-5 h-5 ${
                  step.label === 'Failed'
                    ? 'text-theme-error-fg'
                    : step.label === 'Cancelled'
                      ? 'text-theme-tertiary'
                      : 'text-theme-success-fg'
                }`}
              />
            ) : (
              <Circle className="w-5 h-5 text-theme-tertiary" />
            )}
            {idx < steps.length - 1 && (
              <div className="hidden sm:block w-full h-px bg-theme mt-2.5" style={{ minWidth: '2rem' }} />
            )}
          </div>
          <div>
            <p className={`text-sm font-medium ${step.ts ? 'text-theme-primary' : 'text-theme-tertiary'}`}>{step.label}</p>
            <p className="text-xs text-theme-tertiary">{formatTimestamp(step.ts)}</p>
          </div>
        </div>
      ))}
    </div>
  );
};

const formatBytes = (bytes: number | null): string => {
  if (!bytes && bytes !== 0) return '—';
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB'];
  let value = bytes / 1024;
  let unitIdx = 0;
  while (value >= 1024 && unitIdx < units.length - 1) {
    value /= 1024;
    unitIdx += 1;
  }
  return `${value.toFixed(1)} ${units[unitIdx]}`;
};

const ModuleMembersTable: React.FC<{ modules: ModuleBuildMember[] }> = ({ modules }) => {
  const columns: DataTableColumn<ModuleBuildMember>[] = [
    { key: 'module', header: 'Module', render: (m) => <span className="font-medium text-theme-primary">{m.module}</span> },
    { key: 'architecture', header: 'Arch', render: (m) => m.architecture || '—' },
    { key: 'tag', header: 'Tag', render: (m) => <span className="font-mono text-xs">{m.tag || '—'}</span> },
    { key: 'state', header: 'State', render: (m) => <span className="capitalize">{m.state}</span> },
    { key: 'attempts', header: 'Attempts', render: (m) => m.attempts },
    {
      key: 'task',
      header: 'Task',
      render: (m) =>
        m.task ? (
          <div className="text-xs">
            <p className="capitalize text-theme-primary">{m.task.status}</p>
            {m.task.progress != null && <p className="text-theme-tertiary">{m.task.progress}%</p>}
          </div>
        ) : (
          <span className="text-theme-tertiary">—</span>
        ),
    },
    {
      key: 'error',
      header: 'Error',
      render: (m) =>
        m.error || m.task?.error_message ? (
          <span className="text-theme-error-fg text-xs">{m.error || m.task?.error_message}</span>
        ) : (
          <span className="text-theme-tertiary">—</span>
        ),
    },
    {
      key: 'artifact',
      header: 'Artifact',
      render: (m) =>
        m.artifact ? (
          <div className="text-xs">
            <p className="text-theme-primary">v{m.artifact.version_number} · {formatBytes(m.artifact.size_bytes)}</p>
            <p className="text-theme-tertiary">{m.artifact.signed ? 'signed' : 'unsigned'} · {m.artifact.promotion_state}</p>
          </div>
        ) : (
          <span className="text-theme-tertiary">—</span>
        ),
    },
    {
      key: 'parity',
      header: 'Parity',
      render: (m) =>
        m.parity != null ? (
          <span className="text-xs font-mono text-theme-secondary">
            {typeof m.parity === 'object' ? JSON.stringify(m.parity) : String(m.parity)}
          </span>
        ) : (
          <span className="text-theme-tertiary">—</span>
        ),
    },
  ];

  return (
    <DataTable
      columns={columns}
      data={modules}
      emptyState={{ icon: Package, title: 'No module rows', description: 'This batch has no planned modules yet.' }}
    />
  );
};

export const ModuleBuildDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { currentUser } = useAuth();
  const { batch, loading, error, refresh } = useModuleBuildBatch(id || null);

  const canRead = currentUser?.permissions?.includes('system.module_builds.read');

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'DevOps', href: '/app/devops' },
    { label: 'CI/CD', href: '/app/devops/ci-cd' },
    { label: 'Module Builds', href: '/app/devops/ci-cd/module-builds' },
  ];

  if (!canRead) {
    return (
      <PageContainer title="Forbidden" breadcrumbs={[...breadcrumbs, { label: 'Forbidden' }]}>
        <p className="text-theme-secondary">You don't have permission to view module build batches.</p>
      </PageContainer>
    );
  }

  if (loading) {
    return (
      <PageContainer title="Loading..." breadcrumbs={[...breadcrumbs, { label: 'Loading...' }]}>
        <div className="flex items-center justify-center h-64">
          <RefreshCw className="w-8 h-8 animate-spin text-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  if (error || !batch) {
    return (
      <PageContainer
        title="Batch Not Found"
        breadcrumbs={[...breadcrumbs, { label: 'Not Found' }]}
        actions={[
          {
            id: 'back',
            label: 'Back to Module Builds',
            onClick: () => navigate('/app/devops/ci-cd/module-builds'),
            icon: ArrowLeft,
            variant: 'outline',
          },
        ]}
      >
        <div className="text-center py-12">
          <p className="text-theme-secondary">{error || 'The requested module build batch could not be found.'}</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={`Module Build ${batch.id.slice(0, 8)}`}
      description={`${batch.trigger} build — ${batch.planned_count} module${batch.planned_count === 1 ? '' : 's'} planned`}
      breadcrumbs={[...breadcrumbs, { label: batch.id.slice(0, 8) }]}
      actions={[
        {
          id: 'back',
          label: 'Back',
          onClick: () => navigate('/app/devops/ci-cd/module-builds'),
          icon: ArrowLeft,
          variant: 'outline',
        },
        {
          id: 'refresh',
          label: 'Refresh',
          onClick: refresh,
          icon: RefreshCw,
          variant: 'secondary',
        },
      ]}
    >
      <div className="space-y-6">
        {/* Status Header */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div className="flex items-center gap-4">
              <div>
                <div className="flex items-center gap-2 mb-1">
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
                </div>
                <div className="flex items-center gap-2 text-xs text-theme-secondary font-mono">
                  <GitCommit className="w-3.5 h-3.5" />
                  {shortSha(batch.base_sha)} → {shortSha(batch.head_sha)}
                </div>
              </div>
            </div>
            <CancelBatchButton batch={batch} onCancelled={refresh} />
          </div>
        </div>

        {/* Error message */}
        {batch.error_message && (
          <div className="bg-theme-error-fg/10 border border-theme-error-border rounded-lg p-4">
            <p className="text-sm font-medium text-theme-error-fg mb-1">Error</p>
            <p className="text-sm text-theme-error-fg">{batch.error_message}</p>
          </div>
        )}

        {/* Timestamp Ladder */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Build Progress</h3>
          <TimestampLadder
            cancelledAt={batch.cancelled_at}
            dispatchedAt={batch.dispatched_at}
            awaitingSignatureAt={batch.awaiting_signature_at}
            publishingAt={batch.publishing_at}
            completedAt={batch.completed_at}
            failedAt={batch.failed_at}
          />
        </div>

        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <p className="text-sm text-theme-secondary mb-1">Planned</p>
            <p className="text-2xl font-bold text-theme-primary">{batch.planned_count}</p>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <p className="text-sm text-theme-success-fg mb-1">Succeeded</p>
            <p className="text-2xl font-bold text-theme-success-fg">{batch.succeeded_count}</p>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <p className="text-sm text-theme-error-fg mb-1">Failed</p>
            <p className="text-2xl font-bold text-theme-error-fg">{batch.failed_count}</p>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <p className="text-sm text-theme-secondary mb-1">Created</p>
            <p className="text-sm font-medium text-theme-primary">{formatTimestamp(batch.created_at)}</p>
          </div>
        </div>

        {/* Package context */}
        {batch.package_context && (
          <div className="bg-theme-surface rounded-lg border border-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Package Context</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
              {Object.entries(batch.package_context)
                .filter(([, value]) => value != null)
                .map(([key, value]) => (
                  <div key={key} className="flex justify-between py-2 border-b border-theme">
                    <span className="text-theme-secondary capitalize">{key.replace(/_/g, ' ')}</span>
                    <span className="text-theme-primary font-medium font-mono text-xs">
                      {Array.isArray(value) ? value.join(', ') : String(value)}
                    </span>
                  </div>
                ))}
            </div>
          </div>
        )}

        {/* Module members */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Modules ({batch.modules.length})</h3>
          <ModuleMembersTable modules={batch.modules} />
        </div>
      </div>
    </PageContainer>
  );
};

export default ModuleBuildDetailPage;
