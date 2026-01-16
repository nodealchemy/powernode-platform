import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Play, Edit, Copy, Download, Trash2, RefreshCw, Settings, Activity, Clock, CheckCircle, XCircle, AlertCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAuth } from '@/shared/hooks/useAuth';
import { devopsPipelinesApi, devopsPipelineRunsApi } from '@/services/devopsPipelinesApi';
import type { CiCdPipeline, CiCdPipelineRun } from '@/types/devops-pipelines';

const StatusBadge: React.FC<{ status: string }> = ({ status }) => {
  const config: Record<string, { color: string; icon: React.ElementType }> = {
    success: { color: 'text-theme-success bg-theme-success/10', icon: CheckCircle },
    failure: { color: 'text-theme-error bg-theme-error/10', icon: XCircle },
    running: { color: 'text-theme-info bg-theme-info/10', icon: RefreshCw },
    pending: { color: 'text-theme-warning bg-theme-warning/10', icon: Clock },
    queued: { color: 'text-theme-secondary bg-theme-surface-hover', icon: Clock },
    cancelled: { color: 'text-theme-secondary bg-theme-surface-hover', icon: AlertCircle },
  };

  const { color, icon: Icon } = config[status] || config.pending;

  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${color}`}>
      <Icon className={`w-3.5 h-3.5 ${status === 'running' ? 'animate-spin' : ''}`} />
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  );
};

export const PipelineDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const { currentUser } = useAuth();

  const [pipeline, setPipeline] = useState<CiCdPipeline | null>(null);
  const [runs, setRuns] = useState<CiCdPipelineRun[]>([]);
  const [loading, setLoading] = useState(true);
  const [triggering, setTriggering] = useState(false);

  const canEdit = currentUser?.permissions?.includes('devops.pipelines.write') || false;

  const loadPipeline = useCallback(async () => {
    if (!id) return;

    setLoading(true);
    try {
      const [pipelineData, runsData] = await Promise.all([
        devopsPipelinesApi.getById(id, true),
        devopsPipelineRunsApi.getAll({ pipeline_id: id, per_page: 10 }),
      ]);
      setPipeline(pipelineData);
      setRuns(runsData.pipeline_runs || []);
    } catch (error) {
      showNotification('Failed to load pipeline', 'error');
    } finally {
      setLoading(false);
    }
  }, [id, showNotification]);

  useEffect(() => {
    loadPipeline();
  }, [loadPipeline]);

  const handleTrigger = async () => {
    if (!id) return;

    setTriggering(true);
    try {
      const run = await devopsPipelinesApi.trigger(id);
      showNotification('Pipeline triggered successfully', 'success');
      navigate(`/app/devops/pipelines/${id}/runs/${run.id}`);
    } catch (error) {
      showNotification('Failed to trigger pipeline', 'error');
    } finally {
      setTriggering(false);
    }
  };

  const handleDuplicate = async () => {
    if (!id) return;

    try {
      const newPipeline = await devopsPipelinesApi.duplicate(id);
      showNotification('Pipeline duplicated successfully', 'success');
      navigate(`/app/devops/pipelines/${newPipeline.id}`);
    } catch (error) {
      showNotification('Failed to duplicate pipeline', 'error');
    }
  };

  const handleExportYaml = async () => {
    if (!id) return;

    try {
      const result = await devopsPipelinesApi.exportYaml(id);
      const blob = new Blob([result.yaml], { type: 'text/yaml' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${result.pipeline_name.toLowerCase().replace(/\s+/g, '-')}.yaml`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      showNotification('Pipeline YAML exported', 'success');
    } catch (error) {
      showNotification('Failed to export pipeline', 'error');
    }
  };

  const handleDelete = async () => {
    if (!id || !pipeline) return;

    if (!confirm(`Are you sure you want to delete "${pipeline.name}"? This action cannot be undone.`)) {
      return;
    }

    try {
      await devopsPipelinesApi.delete(id);
      showNotification('Pipeline deleted', 'success');
      navigate('/app/devops/pipelines');
    } catch (error) {
      showNotification('Failed to delete pipeline', 'error');
    }
  };

  if (loading) {
    return (
      <PageContainer
        title="Loading..."
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'DevOps', href: '/app/devops' },
          { label: 'Pipelines', href: '/app/devops/pipelines' },
          { label: 'Loading...' },
        ]}
      >
        <div className="flex items-center justify-center h-64">
          <RefreshCw className="w-8 h-8 animate-spin text-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  if (!pipeline) {
    return (
      <PageContainer
        title="Pipeline Not Found"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'DevOps', href: '/app/devops' },
          { label: 'Pipelines', href: '/app/devops/pipelines' },
          { label: 'Not Found' },
        ]}
        actions={[
          {
            id: 'back',
            label: 'Back to Pipelines',
            onClick: () => navigate('/app/devops/pipelines'),
            icon: ArrowLeft,
            variant: 'outline',
          },
        ]}
      >
        <div className="text-center py-12">
          <p className="text-theme-secondary">The requested pipeline could not be found.</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={pipeline.name}
      description={pipeline.description || 'CI/CD Pipeline'}
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'DevOps', href: '/app/devops' },
        { label: 'Pipelines', href: '/app/devops/pipelines' },
        { label: pipeline.name },
      ]}
      actions={[
        {
          id: 'back',
          label: 'Back',
          onClick: () => navigate('/app/devops/pipelines'),
          icon: ArrowLeft,
          variant: 'outline',
        },
        {
          id: 'trigger',
          label: triggering ? 'Triggering...' : 'Run Pipeline',
          onClick: handleTrigger,
          icon: Play,
          variant: 'primary',
          disabled: triggering || !pipeline.is_active,
        },
        ...(canEdit ? [
          {
            id: 'edit',
            label: 'Edit',
            onClick: () => navigate(`/app/devops/pipelines/${id}/edit`),
            icon: Edit,
            variant: 'outline' as const,
          },
        ] : []),
      ]}
    >
      <div className="space-y-6">
        {/* Pipeline Info Cards */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="text-sm text-theme-secondary mb-1">Status</div>
            <div className="flex items-center gap-2">
              <span className={`w-2 h-2 rounded-full ${pipeline.is_active ? 'bg-theme-success' : 'bg-theme-secondary'}`} />
              <span className="font-medium text-theme-primary">
                {pipeline.is_active ? 'Active' : 'Inactive'}
              </span>
            </div>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="text-sm text-theme-secondary mb-1">Total Runs</div>
            <div className="text-2xl font-bold text-theme-primary">{pipeline.run_count}</div>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="text-sm text-theme-secondary mb-1">Steps</div>
            <div className="text-2xl font-bold text-theme-primary">{pipeline.step_count}</div>
          </div>
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="text-sm text-theme-secondary mb-1">Success Rate</div>
            <div className="text-2xl font-bold text-theme-primary">
              {pipeline.success_rate !== null ? `${Math.round(pipeline.success_rate)}%` : 'N/A'}
            </div>
          </div>
        </div>

        {/* Quick Actions */}
        {canEdit && (
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" size="sm" onClick={handleDuplicate}>
              <Copy className="w-4 h-4 mr-2" />
              Duplicate
            </Button>
            <Button variant="outline" size="sm" onClick={handleExportYaml}>
              <Download className="w-4 h-4 mr-2" />
              Export YAML
            </Button>
            <Button variant="outline" size="sm" onClick={handleDelete} className="text-theme-error hover:bg-theme-error/10">
              <Trash2 className="w-4 h-4 mr-2" />
              Delete
            </Button>
          </div>
        )}

        {/* Pipeline Steps */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Settings className="w-5 h-5" />
            Pipeline Steps
          </h3>
          {pipeline.steps && pipeline.steps.length > 0 ? (
            <div className="space-y-2">
              {pipeline.steps.map((step, index) => (
                <div
                  key={step.id}
                  className="flex items-center gap-3 p-3 bg-theme-surface-hover rounded-lg"
                >
                  <span className="w-6 h-6 flex items-center justify-center bg-theme-primary/10 text-theme-primary rounded-full text-sm font-medium">
                    {index + 1}
                  </span>
                  <div className="flex-1">
                    <div className="font-medium text-theme-primary">{step.name}</div>
                    <div className="text-sm text-theme-secondary">{step.step_type}</div>
                  </div>
                  <span className={`px-2 py-0.5 rounded text-xs ${step.is_active ? 'bg-theme-success/10 text-theme-success' : 'bg-theme-secondary/10 text-theme-secondary'}`}>
                    {step.is_active ? 'Active' : 'Disabled'}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-theme-secondary text-center py-4">No steps configured</p>
          )}
        </div>

        {/* Recent Runs */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-theme-primary flex items-center gap-2">
              <Activity className="w-5 h-5" />
              Recent Runs
            </h3>
            <Button
              variant="outline"
              size="sm"
              onClick={() => navigate(`/app/devops/pipelines/${id}/runs`)}
            >
              View All Runs
            </Button>
          </div>
          {runs.length > 0 ? (
            <div className="space-y-2">
              {runs.map((run) => (
                <div
                  key={run.id}
                  onClick={() => navigate(`/app/devops/pipelines/${id}/runs/${run.id}`)}
                  className="flex items-center gap-4 p-3 bg-theme-surface-hover rounded-lg hover:bg-theme-surface-active cursor-pointer transition-colors"
                >
                  <span className="text-sm font-mono text-theme-secondary">#{run.run_number}</span>
                  <StatusBadge status={run.status} />
                  <span className="text-sm text-theme-secondary flex-1">
                    {run.trigger_type === 'manual' ? 'Manual trigger' : run.trigger_type}
                  </span>
                  {run.duration_seconds && (
                    <span className="text-sm text-theme-secondary">
                      {run.duration_seconds}s
                    </span>
                  )}
                  <span className="text-sm text-theme-secondary">
                    {new Date(run.created_at).toLocaleDateString()}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-theme-secondary text-center py-4">No runs yet</p>
          )}
        </div>

        {/* Configuration Details */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Configuration</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
            <div>
              <span className="text-theme-secondary">Type:</span>
              <span className="ml-2 text-theme-primary">{pipeline.pipeline_type}</span>
            </div>
            <div>
              <span className="text-theme-secondary">Timeout:</span>
              <span className="ml-2 text-theme-primary">{pipeline.timeout_minutes} minutes</span>
            </div>
            <div>
              <span className="text-theme-secondary">Concurrent Runs:</span>
              <span className="ml-2 text-theme-primary">{pipeline.allow_concurrent ? 'Allowed' : 'Not allowed'}</span>
            </div>
            <div>
              <span className="text-theme-secondary">Version:</span>
              <span className="ml-2 text-theme-primary">v{pipeline.version}</span>
            </div>
          </div>
        </div>
      </div>
    </PageContainer>
  );
};

export default PipelineDetailPage;
