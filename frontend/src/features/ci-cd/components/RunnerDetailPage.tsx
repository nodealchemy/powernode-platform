import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Server, Play, RefreshCw, Trash2, Copy, Clock, Activity,
  Cpu, Tag, CheckCircle, XCircle, AlertCircle, ArrowLeft
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAuth } from '@/shared/hooks/useAuth';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import type { GitRunnerDetail } from '@/features/git-providers/types';

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

const InfoCard: React.FC<{
  label: string;
  value: string | number | undefined;
  icon?: React.ElementType;
  className?: string;
}> = ({ label, value, icon: Icon, className = '' }) => (
  <div className={`bg-theme-surface rounded-lg p-4 border border-theme ${className}`}>
    <div className="flex items-center gap-2 text-theme-tertiary mb-1">
      {Icon && <Icon className="w-4 h-4" />}
      <span className="text-sm">{label}</span>
    </div>
    <p className="text-lg font-semibold text-theme-primary">{value ?? '-'}</p>
  </div>
);

const LabelsEditor: React.FC<{
  labels: string[];
  onSave: (labels: string[]) => Promise<void>;
  canEdit: boolean;
}> = ({ labels, onSave, canEdit }) => {
  const [editing, setEditing] = useState(false);
  const [newLabels, setNewLabels] = useState(labels.join(', '));
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    setSaving(true);
    try {
      const parsed = newLabels.split(',').map(l => l.trim()).filter(Boolean);
      await onSave(parsed);
      setEditing(false);
    } finally {
      setSaving(false);
    }
  };

  if (!editing) {
    return (
      <div className="bg-theme-surface rounded-lg p-4 border border-theme">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2 text-theme-tertiary">
            <Tag className="w-4 h-4" />
            <span className="text-sm font-medium">Labels</span>
          </div>
          {canEdit && (
            <Button onClick={() => setEditing(true)} variant="secondary" size="sm">
              Edit
            </Button>
          )}
        </div>
        <div className="flex flex-wrap gap-2">
          {labels.length > 0 ? (
            labels.map((label, idx) => (
              <span
                key={idx}
                className="inline-flex items-center px-3 py-1 rounded-lg text-sm bg-theme-primary/10 text-theme-primary"
              >
                {label}
              </span>
            ))
          ) : (
            <span className="text-theme-tertiary text-sm">No labels</span>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface rounded-lg p-4 border border-theme">
      <div className="flex items-center gap-2 text-theme-tertiary mb-3">
        <Tag className="w-4 h-4" />
        <span className="text-sm font-medium">Edit Labels</span>
      </div>
      <textarea
        value={newLabels}
        onChange={(e) => setNewLabels(e.target.value)}
        className="w-full px-3 py-2 bg-theme-bg border border-theme rounded-lg text-theme-primary mb-3"
        rows={3}
        placeholder="Enter labels separated by commas..."
      />
      <div className="flex gap-2">
        <Button onClick={handleSave} variant="primary" size="sm" disabled={saving}>
          {saving ? 'Saving...' : 'Save'}
        </Button>
        <Button onClick={() => setEditing(false)} variant="secondary" size="sm">
          Cancel
        </Button>
      </div>
    </div>
  );
};

const TokenDisplay: React.FC<{
  title: string;
  description: string;
  onGenerate: () => Promise<{ token: string; expires_at?: string }>;
  canGenerate: boolean;
}> = ({ title, description, onGenerate, canGenerate }) => {
  const [token, setToken] = useState<string | null>(null);
  const [expiresAt, setExpiresAt] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const { showNotification } = useNotifications();

  const handleGenerate = async () => {
    setLoading(true);
    try {
      const result = await onGenerate();
      setToken(result.token);
      setExpiresAt(result.expires_at || null);
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to generate token', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleCopy = () => {
    if (token) {
      navigator.clipboard.writeText(token);
      showNotification('Token copied to clipboard', 'success');
    }
  };

  return (
    <div className="bg-theme-surface rounded-lg p-4 border border-theme">
      <h4 className="font-medium text-theme-primary mb-1">{title}</h4>
      <p className="text-sm text-theme-tertiary mb-3">{description}</p>

      {token ? (
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <code className="flex-1 px-3 py-2 bg-theme-bg border border-theme rounded text-sm text-theme-primary font-mono truncate">
              {token}
            </code>
            <Button onClick={handleCopy} variant="secondary" size="sm">
              <Copy className="w-4 h-4 mr-1" />
              Copy
            </Button>
          </div>
          {expiresAt && (
            <p className="text-xs text-theme-tertiary">
              Expires: {new Date(expiresAt).toLocaleString()}
            </p>
          )}
        </div>
      ) : (
        <Button
          onClick={handleGenerate}
          variant="secondary"
          size="sm"
          disabled={!canGenerate || loading}
        >
          {loading ? 'Generating...' : 'Generate Token'}
        </Button>
      )}
    </div>
  );
};

const RunnerDetailPageContent: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const { currentUser } = useAuth();
  const [runner, setRunner] = useState<GitRunnerDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const canManageRunners = currentUser?.permissions?.includes('git.runners.manage');
  const canGenerateTokens = currentUser?.permissions?.includes('git.runners.token');

  const fetchRunner = useCallback(async () => {
    if (!id) return;
    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getRunner(id);
      setRunner(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch runner');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchRunner();
  }, [fetchRunner]);

  const handleDelete = async () => {
    if (!runner) return;
    if (!window.confirm(`Are you sure you want to delete runner "${runner.name}"? This action cannot be undone.`)) {
      return;
    }
    try {
      await gitProvidersApi.deleteRunner(runner.id);
      showNotification('Runner deleted successfully', 'success');
      navigate('/app/ci-cd/runners');
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to delete runner', 'error');
    }
  };

  const handleUpdateLabels = async (labels: string[]) => {
    if (!runner) return;
    try {
      const updated = await gitProvidersApi.updateRunnerLabels(runner.id, labels);
      setRunner(updated);
      showNotification('Labels updated successfully', 'success');
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to update labels', 'error');
      throw err;
    }
  };

  const breadcrumbs = [
    { label: 'CI/CD', href: '/app/ci-cd', icon: Play },
    { label: 'Runners', href: '/app/ci-cd/runners' },
    { label: runner?.name || 'Runner Details' }
  ];

  const actions = runner ? [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: fetchRunner,
      variant: 'secondary' as const,
      icon: RefreshCw
    },
    ...(canManageRunners ? [{
      id: 'delete',
      label: 'Delete Runner',
      onClick: handleDelete,
      variant: 'danger' as const,
      icon: Trash2
    }] : [])
  ] : [];

  if (loading) {
    return (
      <PageContainer title="Runner Details" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
          <span className="ml-3 text-theme-secondary">Loading runner...</span>
        </div>
      </PageContainer>
    );
  }

  if (error || !runner) {
    return (
      <PageContainer title="Runner Details" breadcrumbs={breadcrumbs}>
        <div className="bg-theme-error/10 border border-theme-error rounded-lg p-6 text-center">
          <AlertCircle className="w-12 h-12 text-theme-error mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">Failed to Load Runner</h3>
          <p className="text-theme-secondary mb-4">{error || 'Runner not found'}</p>
          <div className="flex gap-2 justify-center">
            <Button onClick={() => navigate('/app/ci-cd/runners')} variant="secondary">
              <ArrowLeft className="w-4 h-4 mr-2" />
              Back to Runners
            </Button>
            <Button onClick={fetchRunner} variant="primary">
              <RefreshCw className="w-4 h-4 mr-2" />
              Try Again
            </Button>
          </div>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={runner.name}
      description={`Runner ID: ${runner.external_id}`}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Header with Status */}
        <div className="bg-theme-surface rounded-lg p-6 border border-theme">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-4">
              <div className={`w-14 h-14 rounded-xl flex items-center justify-center ${
                runner.status === 'online' ? 'bg-theme-success/10' : 'bg-theme-secondary/10'
              }`}>
                <Server className={`w-7 h-7 ${
                  runner.status === 'online' ? 'text-theme-success' : 'text-theme-secondary'
                }`} />
              </div>
              <div>
                <h2 className="text-xl font-semibold text-theme-primary">{runner.name}</h2>
                <p className="text-sm text-theme-tertiary">
                  {runner.provider_type} • {runner.runner_scope} runner
                </p>
              </div>
            </div>
            <StatusBadge status={runner.status} busy={runner.busy} />
          </div>

          {runner.repository && (
            <div className="mt-4 pt-4 border-t border-theme">
              <span className="text-sm text-theme-tertiary">Repository: </span>
              <span className="text-sm text-theme-primary font-medium">{runner.repository.full_name}</span>
            </div>
          )}
        </div>

        {/* Stats Grid */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <InfoCard label="Total Jobs" value={runner.total_jobs_run} icon={Activity} />
          <InfoCard
            label="Successful"
            value={runner.successful_jobs}
            icon={CheckCircle}
            className="text-theme-success"
          />
          <InfoCard
            label="Failed"
            value={runner.failed_jobs}
            icon={XCircle}
            className="text-theme-error"
          />
          <InfoCard
            label="Success Rate"
            value={`${runner.success_rate.toFixed(1)}%`}
            icon={Activity}
          />
        </div>

        {/* System Info */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <InfoCard label="Operating System" value={runner.os} icon={Cpu} />
          <InfoCard label="Architecture" value={runner.architecture} />
          <InfoCard label="Version" value={runner.version} />
          <InfoCard
            label="Last Seen"
            value={runner.last_seen_at ? new Date(runner.last_seen_at).toLocaleString() : 'Never'}
            icon={Clock}
          />
        </div>

        {/* Labels */}
        <LabelsEditor
          labels={runner.labels}
          onSave={handleUpdateLabels}
          canEdit={canManageRunners ?? false}
        />

        {/* Tokens Section */}
        {canGenerateTokens && (
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-theme-primary">Runner Tokens</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <TokenDisplay
                title="Registration Token"
                description="Use this token to register a new runner with the same scope."
                onGenerate={() => gitProvidersApi.getRunnerRegistrationToken(runner.id)}
                canGenerate={canGenerateTokens}
              />
              <TokenDisplay
                title="Removal Token"
                description="Use this token to remove the runner from the provider."
                onGenerate={() => gitProvidersApi.getRunnerRemovalToken(runner.id)}
                canGenerate={canGenerateTokens}
              />
            </div>
          </div>
        )}

        {/* Metadata */}
        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <h4 className="text-sm font-medium text-theme-tertiary mb-3">Runner Metadata</h4>
          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <span className="text-theme-tertiary">Created:</span>{' '}
              <span className="text-theme-primary">{new Date(runner.created_at).toLocaleString()}</span>
            </div>
            <div>
              <span className="text-theme-tertiary">Updated:</span>{' '}
              <span className="text-theme-primary">{new Date(runner.updated_at).toLocaleString()}</span>
            </div>
            <div>
              <span className="text-theme-tertiary">External ID:</span>{' '}
              <span className="text-theme-primary font-mono">{runner.external_id}</span>
            </div>
            <div>
              <span className="text-theme-tertiary">Credential ID:</span>{' '}
              <span className="text-theme-primary font-mono">{runner.credential_id}</span>
            </div>
          </div>
        </div>
      </div>
    </PageContainer>
  );
};

export const RunnerDetailPage: React.FC = () => (
  <PageErrorBoundary>
    <RunnerDetailPageContent />
  </PageErrorBoundary>
);

export default RunnerDetailPage;
