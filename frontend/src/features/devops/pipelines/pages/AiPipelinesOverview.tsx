import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Play, FileText, Settings, RefreshCw, Clock, Activity, CheckCircle, XCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PipelineStatsCards } from '../components/PipelineStatsCards';
import { usePipelines } from '../hooks/usePipelines';
import { usePipelineRuns } from '../hooks/usePipelineRuns';
import { usePromptTemplates } from '../hooks/usePromptTemplates';
import type { CiCdPipeline, CiCdPipelineRun, CiCdPipelineRunStatus } from '@/types/devops-pipelines';

const getStatusConfig = (status: CiCdPipelineRunStatus) => {
  const configs: Record<CiCdPipelineRunStatus, { bg: string; text: string; icon: React.ElementType }> = {
    pending: { bg: 'bg-theme-warning/10', text: 'text-theme-warning', icon: Clock },
    queued: { bg: 'bg-theme-warning/10', text: 'text-theme-warning', icon: Clock },
    running: { bg: 'bg-theme-info/10', text: 'text-theme-info', icon: Activity },
    success: { bg: 'bg-theme-success/10', text: 'text-theme-success', icon: CheckCircle },
    failure: { bg: 'bg-theme-error/10', text: 'text-theme-error', icon: XCircle },
    cancelled: { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', icon: XCircle },
  };
  return configs[status] || configs.pending;
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

const RecentRunRow: React.FC<{ run: CiCdPipelineRun; onClick: () => void }> = ({ run, onClick }) => {
  const config = getStatusConfig(run.status);
  const Icon = config.icon;

  return (
    <button
      onClick={onClick}
      className="w-full flex items-center justify-between p-3 hover:bg-theme-surface-hover rounded-lg transition-colors text-left"
    >
      <div className="flex items-center gap-3 min-w-0 flex-1">
        <div className={`p-1.5 rounded ${config.bg}`}>
          <Icon className={`w-4 h-4 ${config.text} ${run.status === 'running' ? 'animate-spin' : ''}`} />
        </div>
        <div className="min-w-0">
          <p className="text-sm font-medium text-theme-primary truncate">
            {run.pipeline_name || 'Pipeline'} #{run.run_number}
          </p>
          <p className="text-xs text-theme-tertiary truncate">
            {run.trigger_type} • {run.branch || 'N/A'}
          </p>
        </div>
      </div>
      <span className="text-xs text-theme-tertiary">{formatTimeAgo(run.created_at)}</span>
    </button>
  );
};

const PipelineCard: React.FC<{ pipeline: CiCdPipeline; onClick: () => void }> = ({ pipeline, onClick }) => (
  <button
    onClick={onClick}
    className="w-full bg-theme-surface rounded-lg p-4 border border-theme hover:border-theme-primary transition-colors text-left"
  >
    <div className="flex items-center gap-3">
      <div className="p-2 bg-theme-primary/10 rounded-lg">
        <Play className="w-4 h-4 text-theme-primary" />
      </div>
      <div>
        <p className="font-medium text-theme-primary">{pipeline.name}</p>
        <p className="text-xs text-theme-tertiary">{pipeline.step_count} steps • {pipeline.run_count} runs</p>
      </div>
    </div>
  </button>
);

const AiPipelinesOverviewContent: React.FC = () => {
  const navigate = useNavigate();
  const { pipelines, meta: pipelineMeta, loading: pipelinesLoading, refresh: refreshPipelines } = usePipelines();
  const { runs, loading: runsLoading, refresh: refreshRuns } = usePipelineRuns({ per_page: 10 });
  const { templates, loading: templatesLoading } = usePromptTemplates();

  const loading = pipelinesLoading || runsLoading || templatesLoading;

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Automation' }
  ];

  const actions = [
    {
      id: 'pipelines',
      label: 'Pipelines',
      onClick: () => navigate('/app/devops/pipelines'),
      variant: 'secondary' as const,
      icon: Play
    },
    {
      id: 'prompts',
      label: 'Prompts',
      onClick: () => navigate('/app/ai/prompts'),
      variant: 'secondary' as const,
      icon: FileText
    },
    {
      id: 'settings',
      label: 'Settings',
      onClick: () => navigate('/app/devops'),
      variant: 'secondary' as const,
      icon: Settings
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: () => {
        refreshPipelines();
        refreshRuns();
      },
      variant: 'primary' as const,
      icon: RefreshCw
    }
  ];

  return (
    <PageContainer
      title="AI Pipelines Overview"
      description="AI-powered CI/CD pipeline management and orchestration"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Stats */}
        <PipelineStatsCards stats={pipelineMeta} loading={loading} />

        {/* Main Content Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Recent Runs */}
          <div className="bg-theme-surface rounded-lg border border-theme">
            <div className="p-4 border-b border-theme flex items-center justify-between">
              <h3 className="font-medium text-theme-primary">Recent Runs</h3>
              <Button
                onClick={() => navigate('/app/devops/pipelines')}
                variant="ghost"
                size="sm"
              >
                View All
              </Button>
            </div>
            <div className="p-2">
              {loading ? (
                <div className="flex items-center justify-center py-8">
                  <LoadingSpinner size="md" />
                </div>
              ) : runs.length > 0 ? (
                <div className="space-y-1">
                  {runs.slice(0, 8).map((run) => (
                    <RecentRunRow
                      key={run.id}
                      run={run}
                      onClick={() => navigate(`/app/devops/pipelines/${run.id}`)}
                    />
                  ))}
                </div>
              ) : (
                <p className="text-center text-theme-secondary py-8">No recent runs</p>
              )}
            </div>
          </div>

          {/* Pipelines */}
          <div className="bg-theme-surface rounded-lg border border-theme">
            <div className="p-4 border-b border-theme flex items-center justify-between">
              <h3 className="font-medium text-theme-primary">Pipelines</h3>
              <Button
                onClick={() => navigate('/app/devops/pipelines')}
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
              ) : pipelines.length > 0 ? (
                <div className="space-y-3">
                  {pipelines.slice(0, 5).map((pipeline) => (
                    <PipelineCard
                      key={pipeline.id}
                      pipeline={pipeline}
                      onClick={() => navigate(`/app/devops/pipelines/${pipeline.id}`)}
                    />
                  ))}
                </div>
              ) : (
                <div className="text-center py-8">
                  <Play className="w-10 h-10 text-theme-secondary mx-auto mb-3" />
                  <p className="text-theme-secondary mb-3">No pipelines yet</p>
                  <Button
                    onClick={() => navigate('/app/devops/pipelines/new')}
                    variant="primary"
                    size="sm"
                  >
                    Create Pipeline
                  </Button>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Quick Stats Row */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Prompt Templates</p>
                <p className="text-2xl font-semibold text-theme-primary mt-1">
                  {loading ? '-' : templates.length}
                </p>
              </div>
              <div className="p-3 bg-theme-primary/10 rounded-lg">
                <FileText className="w-6 h-6 text-theme-primary" />
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Active Pipelines</p>
                <p className="text-2xl font-semibold text-theme-primary mt-1">
                  {loading ? '-' : pipelineMeta?.active_count || 0}
                </p>
              </div>
              <div className="p-3 bg-theme-success/10 rounded-lg">
                <Activity className="w-6 h-6 text-theme-success" />
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Total Runs</p>
                <p className="text-2xl font-semibold text-theme-primary mt-1">
                  {loading ? '-' : pipelineMeta?.total_runs || 0}
                </p>
              </div>
              <div className="p-3 bg-theme-info/10 rounded-lg">
                <Play className="w-6 h-6 text-theme-info" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </PageContainer>
  );
};

export const AiPipelinesOverview: React.FC = () => (
  <PageErrorBoundary>
    <AiPipelinesOverviewContent />
  </PageErrorBoundary>
);

export default AiPipelinesOverview;
