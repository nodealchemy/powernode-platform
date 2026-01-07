import React, { useState, useMemo } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  Plus, RefreshCw, Search, Filter, Play, Pause, Clock,
  CheckCircle, XCircle, MoreVertical, Brain, GitBranch,
  Calendar, Zap, Layers, FileCode, Copy, Trash2
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePipelines } from '@/features/cicd/hooks/usePipelines';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { CiCdPipeline } from '@/types/cicd';

type StatusFilter = 'all' | 'active' | 'inactive';

const StatusBadge: React.FC<{ isActive: boolean }> = ({ isActive }) => (
  <span
    className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${
      isActive
        ? 'bg-green-100 text-theme-success dark:bg-green-900/30 dark:text-green-300'
        : 'bg-theme-surface-secondary text-theme-secondary'
    }`}
  >
    {isActive ? (
      <>
        <CheckCircle className="w-3 h-3" />
        Active
      </>
    ) : (
      <>
        <Pause className="w-3 h-3" />
        Inactive
      </>
    )}
  </span>
);

const TriggerBadge: React.FC<{ triggers: CiCdPipeline['triggers'] }> = ({ triggers }) => {
  const getTriggerInfo = () => {
    if (triggers.schedule?.length) return {
      icon: Calendar,
      label: 'Scheduled',
      description: 'Runs automatically on a schedule (cron)'
    };
    if (triggers.push?.branches?.length || triggers.pull_request?.length) return {
      icon: GitBranch,
      label: 'Git Event',
      description: 'Runs when code is pushed or PRs are opened'
    };
    if (triggers.workflow_dispatch) return {
      icon: Zap,
      label: 'Webhook',
      description: 'Runs when triggered by external API call'
    };
    return {
      icon: Play,
      label: 'Manual',
      description: 'Run pipeline manually from dashboard'
    };
  };

  const { icon: Icon, label, description } = getTriggerInfo();

  return (
    <span
      className="inline-flex items-center gap-1 text-xs text-theme-tertiary cursor-help"
      title={description}
    >
      <Icon className="w-3 h-3" />
      {label}
    </span>
  );
};

const formatTimeAgo = (dateString: string | null): string => {
  if (!dateString) return 'Never';
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

const getLastRunStatus = (lastRun: CiCdPipeline['last_run']) => {
  if (!lastRun) return null;

  const statusConfig: Record<string, { icon: typeof CheckCircle; className: string }> = {
    success: { icon: CheckCircle, className: 'text-theme-success' },
    failure: { icon: XCircle, className: 'text-theme-error' },
    running: { icon: Play, className: 'text-theme-info animate-pulse' },
    pending: { icon: Clock, className: 'text-theme-warning' },
    cancelled: { icon: XCircle, className: 'text-theme-tertiary' },
  };

  const config = statusConfig[lastRun.status] || statusConfig.pending;
  const Icon = config.icon;

  return <Icon className={`w-4 h-4 ${config.className}`} />;
};

interface PipelineCardProps {
  pipeline: CiCdPipeline;
  onTrigger: () => void;
  onDuplicate: () => void;
  onDelete: () => void;
  onExportYaml: () => void;
  onClick: () => void;
}

const PipelineCard: React.FC<PipelineCardProps> = ({
  pipeline,
  onTrigger,
  onDuplicate,
  onDelete,
  onExportYaml,
  onClick,
}) => {
  const [showMenu, setShowMenu] = useState(false);

  const getPipelineTypeIcon = () => {
    // Check if pipeline has AI-related steps
    const hasAiSteps = pipeline.steps?.some(
      (step) => step.step_type === 'claude_execute'
    );
    return hasAiSteps ? (
      <Brain className="w-5 h-5 text-theme-accent" />
    ) : (
      <GitBranch className="w-5 h-5 text-theme-info" />
    );
  };

  return (
    <div className="bg-theme-surface rounded-lg border border-theme hover:border-theme-primary transition-colors">
      <button onClick={onClick} className="w-full p-4 text-left">
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-surface-secondary rounded-lg">
              {getPipelineTypeIcon()}
            </div>
            <div>
              <h3 className="font-medium text-theme-primary">{pipeline.name}</h3>
              <p className="text-xs text-theme-tertiary font-mono">{pipeline.slug}</p>
            </div>
          </div>
          <StatusBadge isActive={pipeline.is_active} />
        </div>

        {pipeline.description && (
          <p className="mt-3 text-sm text-theme-secondary line-clamp-2">
            {pipeline.description}
          </p>
        )}

        <div className="mt-4 flex items-center gap-4 text-xs text-theme-tertiary flex-wrap">
          <span className="flex items-center gap-1">
            <Play className="w-3 h-3" />
            {pipeline.run_count || 0} runs
          </span>
          {pipeline.success_rate !== null && pipeline.success_rate !== undefined && (
            <span
              className={`flex items-center gap-1 ${
                pipeline.success_rate >= 80
                  ? 'text-theme-success dark:text-green-400'
                  : pipeline.success_rate >= 50
                    ? 'text-theme-warning dark:text-yellow-400'
                    : 'text-theme-danger dark:text-red-400'
              }`}
              title={`Success rate over last ${pipeline.run_count || 0} runs`}
            >
              <CheckCircle className="w-3 h-3" />
              {Math.round(pipeline.success_rate)}%
            </span>
          )}
          <span className="flex items-center gap-1">
            {getLastRunStatus(pipeline.last_run)}
            <span className="ml-1">
              {formatTimeAgo(pipeline.last_run?.started_at || null)}
            </span>
          </span>
          <span>{pipeline.step_count || 0} steps</span>
          <TriggerBadge triggers={pipeline.triggers} />
        </div>
      </button>

      <div className="px-4 pb-4 flex items-center justify-between border-t border-theme pt-3">
        <Button
          onClick={(e) => {
            e.stopPropagation();
            onTrigger();
          }}
          variant="primary"
          size="sm"
          disabled={!pipeline.is_active}
        >
          <Play className="w-4 h-4 mr-1" />
          Trigger
        </Button>

        <div className="relative">
          <Button
            onClick={(e) => {
              e.stopPropagation();
              setShowMenu(!showMenu);
            }}
            variant="ghost"
            size="sm"
          >
            <MoreVertical className="w-4 h-4" />
          </Button>

          {showMenu && (
            <>
              <div
                className="fixed inset-0 z-10"
                onClick={() => setShowMenu(false)}
              />
              <div className="absolute right-0 top-full mt-1 w-48 bg-theme-surface rounded-lg shadow-lg border border-theme z-20">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onExportYaml();
                    setShowMenu(false);
                  }}
                  className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-surface-secondary flex items-center gap-2"
                >
                  <FileCode className="w-4 h-4" />
                  Export YAML
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onDuplicate();
                    setShowMenu(false);
                  }}
                  className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-surface-secondary flex items-center gap-2"
                >
                  <Copy className="w-4 h-4" />
                  Duplicate
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onDelete();
                    setShowMenu(false);
                  }}
                  className="w-full px-4 py-2 text-left text-sm text-theme-danger hover:bg-red-50 dark:hover:bg-red-900/20 flex items-center gap-2"
                >
                  <Trash2 className="w-4 h-4" />
                  Delete
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

const PipelinesPageContent: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { showNotification } = useNotifications();

  const {
    pipelines,
    meta,
    loading,
    refresh,
    triggerPipeline,
    duplicatePipeline,
    deletePipeline,
    exportPipelineYaml,
  } = usePipelines();

  const [searchQuery, setSearchQuery] = useState('');
  const statusFilter = (searchParams.get('status') as StatusFilter) || 'all';

  const filteredPipelines = useMemo(() => {
    return pipelines.filter((pipeline) => {
      const matchesStatus =
        statusFilter === 'all' ||
        (statusFilter === 'active' && pipeline.is_active) ||
        (statusFilter === 'inactive' && !pipeline.is_active);

      const matchesSearch =
        searchQuery === '' ||
        pipeline.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        pipeline.slug.toLowerCase().includes(searchQuery.toLowerCase()) ||
        pipeline.description?.toLowerCase().includes(searchQuery.toLowerCase());

      return matchesStatus && matchesSearch;
    });
  }, [pipelines, statusFilter, searchQuery]);

  const setFilter = (key: string, value: string) => {
    const newParams = new URLSearchParams(searchParams);
    if (value === 'all') {
      newParams.delete(key);
    } else {
      newParams.set(key, value);
    }
    setSearchParams(newParams);
  };

  const handleExportYaml = async (id: string) => {
    const result = await exportPipelineYaml(id);
    if (result) {
      const blob = new Blob([result.yaml], { type: 'text/yaml' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${result.pipeline_name}.yml`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      showNotification('Pipeline YAML exported', 'success');
    }
  };

  const handleDelete = async (id: string) => {
    if (
      window.confirm(
        'Are you sure you want to delete this pipeline? This action cannot be undone.'
      )
    ) {
      await deletePipeline(id);
    }
  };

  const handleTrigger = async (id: string) => {
    const result = await triggerPipeline(id);
    if (result) {
      navigate(`/app/automation/runs/${result.id}`);
    }
  };

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'secondary',
      icon: RefreshCw,
    },
    {
      id: 'create',
      label: 'Create Pipeline',
      onClick: () => navigate('/app/automation/pipelines/new'),
      variant: 'primary',
      icon: Plus,
    },
  ];

  return (
    <PageContainer
      title="Pipelines"
      description="Manage AI-powered CI/CD automation pipelines"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Automation', href: '/app/automation' },
        { label: 'Pipelines' },
      ]}
      actions={pageActions}
    >
      <div className="space-y-6">
        {/* Stats Bar */}
        {meta && (
          <div className="grid grid-cols-3 gap-4">
            <div className="bg-theme-surface rounded-lg border border-theme p-4">
              <p className="text-sm text-theme-secondary">Total Pipelines</p>
              <p className="text-2xl font-semibold text-theme-primary">{meta.total}</p>
            </div>
            <div className="bg-theme-surface rounded-lg border border-theme p-4">
              <p className="text-sm text-theme-secondary">Active</p>
              <p className="text-2xl font-semibold text-theme-success">{meta.active_count}</p>
            </div>
            <div className="bg-theme-surface rounded-lg border border-theme p-4">
              <p className="text-sm text-theme-secondary">Total Runs</p>
              <p className="text-2xl font-semibold text-theme-primary">{meta.total_runs}</p>
            </div>
          </div>
        )}

        {/* Filters */}
        <div className="flex flex-col md:flex-row gap-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-secondary" />
            <input
              type="text"
              placeholder="Search pipelines..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-theme-surface border border-theme rounded-lg focus:outline-none focus:ring-2 focus:ring-theme-accent text-theme-primary"
            />
          </div>

          <div className="flex items-center gap-2">
            <Filter className="w-4 h-4 text-theme-secondary" />
            <select
              value={statusFilter}
              onChange={(e) => setFilter('status', e.target.value)}
              className="px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            >
              <option value="all">All ({pipelines.length})</option>
              <option value="active">
                Active ({pipelines.filter((p) => p.is_active).length})
              </option>
              <option value="inactive">
                Inactive ({pipelines.filter((p) => !p.is_active).length})
              </option>
            </select>
          </div>
        </div>

        {/* Pipeline Grid */}
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner size="lg" />
          </div>
        ) : filteredPipelines.length === 0 ? (
          <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
            <Layers className="w-12 h-12 text-theme-secondary mx-auto mb-4 opacity-50" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">
              {searchQuery || statusFilter !== 'all'
                ? 'No pipelines match your filters'
                : 'No Pipelines Yet'}
            </h3>
            <p className="text-theme-secondary mb-4">
              {searchQuery || statusFilter !== 'all'
                ? 'Try adjusting your search or filters'
                : 'Create your first AI-powered CI/CD pipeline to automate your workflows'}
            </p>
            {!searchQuery && statusFilter === 'all' && (
              <Button
                onClick={() => navigate('/app/automation/pipelines/new')}
                variant="primary"
              >
                <Plus className="w-4 h-4 mr-2" />
                Create Pipeline
              </Button>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {filteredPipelines.map((pipeline) => (
              <PipelineCard
                key={pipeline.id}
                pipeline={pipeline}
                onTrigger={() => handleTrigger(pipeline.id)}
                onDuplicate={() => duplicatePipeline(pipeline.id)}
                onDelete={() => handleDelete(pipeline.id)}
                onExportYaml={() => handleExportYaml(pipeline.id)}
                onClick={() => navigate(`/app/automation/pipelines/${pipeline.id}`)}
              />
            ))}
          </div>
        )}
      </div>
    </PageContainer>
  );
};

export function PipelinesPage() {
  return (
    <PageErrorBoundary>
      <PipelinesPageContent />
    </PageErrorBoundary>
  );
}

export default PipelinesPage;
