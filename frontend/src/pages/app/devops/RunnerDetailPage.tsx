import React, { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { ArrowLeft, Server, Trash2, RefreshCw, Activity, Cpu, Clock, CheckCircle, XCircle, Tag, Copy, Key } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAuth } from '@/shared/hooks/useAuth';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { gitProvidersApi } from '@/features/devops/git/services/gitProvidersApi';
import { useRunner } from '@/features/devops/git/hooks/useRunners';
import { RunnerLabelEditor } from '@/features/devops/git/components/RunnerLabelEditor';

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
    <span className={`inline-flex items-center px-3 py-1.5 rounded-full text-sm font-medium ${getStatusStyles()}`}>
      <span className={`w-2 h-2 rounded-full mr-2 ${
        busy ? 'bg-theme-warning' :
        status === 'online' ? 'bg-theme-success animate-pulse' :
        'bg-theme-error'
      }`} />
      {busy ? 'Busy' : status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  );
};

export const RunnerDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const { currentUser } = useAuth();
  const { confirm, ConfirmationDialog } = useConfirmation();

  const { runner, loading, refresh: loadRunner, updateLabels } = useRunner(id || null);
  const [deleting, setDeleting] = useState(false);
  const [savingLabels, setSavingLabels] = useState(false);

  usePageWebSocket({
    pageType: 'devops',
    subscribeToDevops: true,
    onDataUpdate: () => {
      loadRunner();
    }
  });

  const canManageRunners = currentUser?.permissions?.includes('git.runners.manage');

  const handleDelete = () => {
    if (!runner) return;

    confirm({
      title: 'Delete Runner',
      message: `Are you sure you want to delete runner "${runner.name}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        setDeleting(true);
        try {
          await gitProvidersApi.deleteRunner(runner.id);
          showNotification('Runner deleted successfully', 'success');
          navigate('/app/devops/ci-cd/runners');
        } catch (_error) {
          showNotification('Failed to delete runner', 'error');
        } finally {
          setDeleting(false);
        }
      }
    });
  };

  const handleCopyId = () => {
    if (runner) {
      navigator.clipboard.writeText(runner.external_id);
      showNotification('Runner ID copied to clipboard', 'success');
    }
  };

  const handleGetRemovalToken = async () => {
    if (!runner) return;

    try {
      const result = await gitProvidersApi.getRunnerRemovalToken(runner.id);
      navigator.clipboard.writeText(result.token);
      showNotification('Removal token copied to clipboard', 'success');
    } catch (_error) {
      showNotification('Failed to get removal token', 'error');
    }
  };

  const handleGetRegistrationToken = async () => {
    if (!runner) return;

    try {
      const result = await gitProvidersApi.getRunnerRegistrationToken(runner.id);
      navigator.clipboard.writeText(result.token);
      showNotification('Registration token copied to clipboard', 'success');
    } catch (_error) {
      showNotification('Failed to get registration token', 'error');
    }
  };

  const handleLabelsChange = async (newLabels: string[]) => {
    try {
      setSavingLabels(true);
      await updateLabels(newLabels);
      showNotification('Labels updated successfully', 'success');
    } catch (_error) {
      showNotification('Failed to update labels', 'error');
    } finally {
      setSavingLabels(false);
    }
  };

  if (loading) {
    return (
      <PageContainer
        title="Loading..."
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'DevOps', href: '/app/devops' },
          { label: 'Runners', href: '/app/devops/ci-cd/runners' },
          { label: 'Loading...' },
        ]}
      >
        <div className="flex items-center justify-center h-64">
          <RefreshCw className="w-8 h-8 animate-spin text-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  if (!runner) {
    return (
      <PageContainer
        title="Runner Not Found"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'DevOps', href: '/app/devops' },
          { label: 'Runners', href: '/app/devops/ci-cd/runners' },
          { label: 'Not Found' },
        ]}
        actions={[
          {
            id: 'back',
            label: 'Back to Runners',
            onClick: () => navigate('/app/devops/ci-cd/runners'),
            icon: ArrowLeft,
            variant: 'outline',
          },
        ]}
      >
        <div className="text-center py-12">
          <p className="text-theme-secondary">The requested runner could not be found.</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={runner.name}
      description={`DevOps Runner - ${runner.provider_type}`}
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'DevOps', href: '/app/devops' },
        { label: 'Runners', href: '/app/devops/ci-cd/runners' },
        { label: runner.name },
      ]}
      actions={[
        {
          id: 'back',
          label: 'Back',
          onClick: () => navigate('/app/devops/ci-cd/runners'),
          icon: ArrowLeft,
          variant: 'outline',
        },
        {
          id: 'refresh',
          label: 'Refresh',
          onClick: loadRunner,
          icon: RefreshCw,
          variant: 'secondary',
        },
        ...(canManageRunners ? [
          {
            id: 'delete',
            label: deleting ? 'Deleting...' : 'Delete',
            onClick: handleDelete,
            icon: Trash2,
            variant: 'danger' as const,
            disabled: deleting,
          },
        ] : []),
      ]}
    >
      <div className="space-y-6">
        {/* Status Header */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex items-start justify-between">
            <div className="flex items-center gap-4">
              <div className={`w-16 h-16 rounded-lg flex items-center justify-center ${
                runner.status === 'online' ? 'bg-theme-success/10' : 'bg-theme-secondary/10'
              }`}>
                <Server className={`w-8 h-8 ${
                  runner.status === 'online' ? 'text-theme-success' : 'text-theme-secondary'
                }`} />
              </div>
              <div>
                <h2 className="text-xl font-semibold text-theme-primary">{runner.name}</h2>
                <div className="flex items-center gap-2 mt-1">
                  <span className="text-sm text-theme-secondary font-mono">{runner.external_id}</span>
                  <button onClick={handleCopyId} className="text-theme-secondary hover:text-theme-primary">
                    <Copy className="w-4 h-4" />
                  </button>
                </div>
              </div>
            </div>
            <StatusBadge status={runner.status} busy={runner.busy} />
          </div>
        </div>

        {/* Stats Cards */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center gap-2 text-theme-secondary mb-1">
              <Activity className="w-4 h-4" />
              <span className="text-sm">Total Jobs</span>
            </div>
            <p className="text-2xl font-bold text-theme-primary">{runner.total_jobs_run}</p>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center gap-2 text-theme-success mb-1">
              <CheckCircle className="w-4 h-4" />
              <span className="text-sm">Successful</span>
            </div>
            <p className="text-2xl font-bold text-theme-success">{runner.successful_jobs}</p>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center gap-2 text-theme-error mb-1">
              <XCircle className="w-4 h-4" />
              <span className="text-sm">Failed</span>
            </div>
            <p className="text-2xl font-bold text-theme-error">{runner.failed_jobs}</p>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center gap-2 text-theme-secondary mb-1">
              <Activity className="w-4 h-4" />
              <span className="text-sm">Success Rate</span>
            </div>
            <p className="text-2xl font-bold text-theme-primary">{runner.success_rate.toFixed(1)}%</p>
          </div>
        </div>

        {/* System Information */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Cpu className="w-5 h-5" />
            System Information
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
            <div className="flex justify-between py-2 border-b border-theme">
              <span className="text-theme-secondary">Operating System</span>
              <span className="text-theme-primary font-medium">{runner.os || 'Unknown'}</span>
            </div>
            <div className="flex justify-between py-2 border-b border-theme">
              <span className="text-theme-secondary">Architecture</span>
              <span className="text-theme-primary font-medium">{runner.architecture || 'Unknown'}</span>
            </div>
            <div className="flex justify-between py-2 border-b border-theme">
              <span className="text-theme-secondary">Version</span>
              <span className="text-theme-primary font-medium">{runner.version || 'Unknown'}</span>
            </div>
            <div className="flex justify-between py-2 border-b border-theme">
              <span className="text-theme-secondary">Provider</span>
              <span className="text-theme-primary font-medium">{runner.provider_type}</span>
            </div>
            <div className="flex justify-between py-2 border-b border-theme">
              <span className="text-theme-secondary">Scope</span>
              <span className="text-theme-primary font-medium capitalize">{runner.runner_scope}</span>
            </div>
            <div className="flex justify-between py-2 border-b border-theme">
              <span className="text-theme-secondary">Last Seen</span>
              <span className="text-theme-primary font-medium">
                {runner.last_seen_at ? new Date(runner.last_seen_at).toLocaleString() : 'Never'}
              </span>
            </div>
          </div>
        </div>

        {/* Labels */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Tag className="w-5 h-5" />
            Labels
          </h3>
          <RunnerLabelEditor
            labels={runner.labels || []}
            onLabelsChange={handleLabelsChange}
            canEdit={!!canManageRunners}
            saving={savingLabels}
          />
        </div>

        {/* Repository Info */}
        {runner.repository && (
          <div className="bg-theme-surface rounded-lg border border-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Repository</h3>
            <p className="text-theme-primary">{runner.repository.full_name}</p>
            <p className="text-sm text-theme-secondary mt-1">ID: {runner.repository.id}</p>
          </div>
        )}

        {/* Timestamps */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Clock className="w-5 h-5" />
            Timestamps
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
            <div className="flex justify-between py-2 border-b border-theme">
              <span className="text-theme-secondary">Created</span>
              <span className="text-theme-primary font-medium">
                {new Date(runner.created_at).toLocaleString()}
              </span>
            </div>
            <div className="flex justify-between py-2 border-b border-theme">
              <span className="text-theme-secondary">Updated</span>
              <span className="text-theme-primary font-medium">
                {new Date(runner.updated_at).toLocaleString()}
              </span>
            </div>
          </div>
        </div>

        {/* Actions */}
        {canManageRunners && (
          <div className="bg-theme-surface rounded-lg border border-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Actions</h3>
            <div className="flex flex-wrap gap-2">
              <Button variant="outline" size="sm" onClick={handleGetRegistrationToken}>
                <Key className="w-4 h-4 mr-2" />
                Get Registration Token
              </Button>
              <Button variant="outline" size="sm" onClick={handleGetRemovalToken}>
                <Key className="w-4 h-4 mr-2" />
                Get Removal Token
              </Button>
            </div>
          </div>
        )}
      </div>
      {ConfirmationDialog}
    </PageContainer>
  );
};

export default RunnerDetailPage;
