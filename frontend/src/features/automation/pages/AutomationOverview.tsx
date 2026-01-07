import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  Zap, Layers, History, Server, FileCode,
  Play, CheckCircle, XCircle, Clock, AlertTriangle,
  ArrowRight, Loader2, X, BookOpen
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { ciCdPipelinesApi, ciCdPipelineRunsApi } from '@/services/ciCdApi';

type PipelineType = 'all' | 'ai' | 'git';

interface PipelineStats {
  total: number;
  active: number;
  running: number;
  failed: number;
}

interface RecentRun {
  id: string;
  pipelineName: string;
  pipelineType: 'ai' | 'git';
  status: 'running' | 'success' | 'failure' | 'pending';
  startedAt: string;
  duration?: string;
  trigger: string;
}

export function AutomationOverview() {
  const navigate = useNavigate();
  const [typeFilter, setTypeFilter] = useState<PipelineType>('all');
  const [stats, setStats] = useState<PipelineStats>({ total: 0, active: 0, running: 0, failed: 0 });
  const [recentRuns, setRecentRuns] = useState<RecentRun[]>([]);
  const [loading, setLoading] = useState(true);
  const [showOnboarding, setShowOnboarding] = useState(() => {
    return localStorage.getItem('automation_onboarding_dismissed') !== 'true';
  });

  const dismissOnboarding = () => {
    setShowOnboarding(false);
    localStorage.setItem('automation_onboarding_dismissed', 'true');
  };

  const pageActions: PageAction[] = [
    {
      id: 'new-pipeline',
      label: 'New Pipeline',
      onClick: () => navigate('/app/automation/pipelines/new'),
      variant: 'primary',
      icon: Zap
    }
  ];

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);

        // Fetch pipelines and runs in parallel
        const [pipelinesResponse, runsResponse] = await Promise.all([
          ciCdPipelinesApi.getAll().catch(() => ({ pipelines: [], stats: null })),
          ciCdPipelineRunsApi.getAll({ per_page: 10 }).catch(() => ({ pipeline_runs: [] }))
        ]);

        // Calculate stats from pipelines
        const pipelines = pipelinesResponse.pipelines || [];
        const pipelineStats: PipelineStats = {
          total: pipelines.length,
          active: pipelines.filter((p: { is_active?: boolean }) => p.is_active).length,
          running: 0,
          failed: 0
        };

        // Map recent runs - CiCdPipelineRun uses pipeline_name, pipeline_slug, not nested pipeline object
        const runs = runsResponse.pipeline_runs || [];
        const mappedRuns: RecentRun[] = runs.slice(0, 10).map((run) => {
          // Count running and failed
          if (run.status === 'running') pipelineStats.running++;
          if (run.status === 'failure') pipelineStats.failed++;

          return {
            id: run.id,
            pipelineName: run.pipeline_name || 'Unknown Pipeline',
            pipelineType: 'ai' as 'ai' | 'git', // Default to ai, can be determined by pipeline_slug if needed
            status: mapRunStatus(run.status),
            startedAt: formatTimeAgo(run.started_at || undefined),
            duration: run.duration_seconds ? formatDuration(run.duration_seconds) : undefined,
            trigger: run.trigger_type || 'manual'
          };
        });

        setStats(pipelineStats);
        setRecentRuns(mappedRuns);
      } catch (error) {
        // Keep default empty state on error
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, []);

  const mapRunStatus = (status: string): RecentRun['status'] => {
    switch (status) {
      case 'running': return 'running';
      case 'completed': case 'success': return 'success';
      case 'failure': case 'failed': case 'error': return 'failure';
      default: return 'pending';
    }
  };

  const formatTimeAgo = (dateStr?: string): string => {
    if (!dateStr) return 'Unknown';
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays}d ago`;
  };

  const formatDuration = (seconds: number): string => {
    if (seconds < 60) return `${seconds}s`;
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    if (mins < 60) return `${mins}m ${secs}s`;
    const hours = Math.floor(mins / 60);
    return `${hours}h ${mins % 60}m`;
  };

  const filteredRuns = typeFilter === 'all'
    ? recentRuns
    : recentRuns.filter(run => run.pipelineType === typeFilter);

  const getStatusIcon = (status: RecentRun['status']) => {
    switch (status) {
      case 'success':
        return <CheckCircle className="w-4 h-4 text-theme-success" />;
      case 'failure':
        return <XCircle className="w-4 h-4 text-theme-danger" />;
      case 'running':
        return <Play className="w-4 h-4 text-theme-info animate-pulse" />;
      case 'pending':
        return <Clock className="w-4 h-4 text-theme-secondary" />;
    }
  };

  const getTypeLabel = (type: 'ai' | 'git') => {
    return type === 'ai' ? (
      <span className="px-2 py-0.5 text-xs rounded-full bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300">
        AI-Powered
      </span>
    ) : (
      <span className="px-2 py-0.5 text-xs rounded-full bg-blue-100 text-theme-info dark:bg-blue-900/30 dark:text-blue-300">
        Git-Native
      </span>
    );
  };

  if (loading) {
    return (
      <PageContainer
        title="Automation"
        description="Pipeline automation overview and recent activity"
        actions={pageActions}
      >
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Automation"
      description="Pipeline automation overview and recent activity"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Automation' }
      ]}
      actions={pageActions}
    >
      {/* Onboarding Banner - Show when no pipelines and not dismissed */}
      {stats.total === 0 && showOnboarding && (
        <div className="mb-6 bg-gradient-to-r from-purple-50 to-blue-50 dark:from-purple-900/20 dark:to-blue-900/20 border border-purple-200 dark:border-purple-800 rounded-lg p-6 relative">
          <button
            onClick={dismissOnboarding}
            className="absolute top-3 right-3 p-1 text-theme-secondary hover:text-theme-primary rounded-md hover:bg-theme-surface transition-colors"
            aria-label="Dismiss"
          >
            <X className="w-4 h-4" />
          </button>
          <div className="flex items-start gap-4">
            <div className="p-3 bg-purple-100 dark:bg-purple-900/40 rounded-lg shrink-0">
              <Zap className="w-6 h-6 text-theme-interactive-primary dark:text-purple-400" />
            </div>
            <div className="flex-1">
              <h3 className="text-lg font-semibold text-theme-primary mb-1">
                Welcome to Automation!
              </h3>
              <p className="text-theme-secondary mb-4">
                Pipelines automate your CI/CD workflows - from AI-powered code review to deployment.
                Create your first pipeline to get started.
              </p>
              <div className="flex items-center gap-3">
                <button
                  onClick={() => navigate('/app/automation/pipelines/new')}
                  className="inline-flex items-center gap-2 px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover transition-colors"
                >
                  <Zap className="w-4 h-4" />
                  Create Your First Pipeline
                </button>
                <Link
                  to="/app/automation/templates"
                  className="inline-flex items-center gap-2 px-4 py-2 text-theme-primary hover:bg-theme-surface rounded-lg transition-colors"
                >
                  <BookOpen className="w-4 h-4" />
                  View Examples
                </Link>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-bg-subtle rounded-lg">
              <Layers className="w-5 h-5 text-theme-primary" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Total Pipelines</p>
              <p className="text-2xl font-semibold text-theme-primary">{stats.total}</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-green-100 dark:bg-green-900/30 rounded-lg">
              <CheckCircle className="w-5 h-5 text-theme-success dark:text-green-400" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Active</p>
              <p className="text-2xl font-semibold text-theme-primary">{stats.active}</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-blue-100 dark:bg-blue-900/30 rounded-lg">
              <Play className="w-5 h-5 text-theme-info dark:text-blue-400" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Running Now</p>
              <p className="text-2xl font-semibold text-theme-primary">{stats.running}</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-red-100 dark:bg-red-900/30 rounded-lg">
              <AlertTriangle className="w-5 h-5 text-theme-danger dark:text-red-400" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Failed (24h)</p>
              <p className="text-2xl font-semibold text-theme-primary">{stats.failed}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Quick Links */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <Link
          to="/app/automation/pipelines"
          className="flex items-center justify-between p-4 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors group"
        >
          <div className="flex items-center gap-3">
            <Layers className="w-5 h-5 text-theme-secondary group-hover:text-theme-primary" />
            <span className="font-medium text-theme-primary">Pipelines</span>
          </div>
          <ArrowRight className="w-4 h-4 text-theme-secondary group-hover:text-theme-primary" />
        </Link>

        <Link
          to="/app/automation/runners"
          className="flex items-center justify-between p-4 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors group"
        >
          <div className="flex items-center gap-3">
            <Server className="w-5 h-5 text-theme-secondary group-hover:text-theme-primary" />
            <span className="font-medium text-theme-primary">Runners</span>
          </div>
          <ArrowRight className="w-4 h-4 text-theme-secondary group-hover:text-theme-primary" />
        </Link>

        <Link
          to="/app/automation/templates"
          className="flex items-center justify-between p-4 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors group"
        >
          <div className="flex items-center gap-3">
            <FileCode className="w-5 h-5 text-theme-secondary group-hover:text-theme-primary" />
            <span className="font-medium text-theme-primary">Templates</span>
          </div>
          <ArrowRight className="w-4 h-4 text-theme-secondary group-hover:text-theme-primary" />
        </Link>
      </div>

      {/* Recent Runs */}
      <div className="bg-theme-surface border border-theme rounded-lg">
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <div className="flex items-center gap-3">
            <History className="w-5 h-5 text-theme-secondary" />
            <h2 className="font-semibold text-theme-primary">Recent Runs</h2>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setTypeFilter('all')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                typeFilter === 'all'
                  ? 'bg-theme-primary text-white'
                  : 'text-theme-secondary hover:bg-theme-bg-subtle'
              }`}
            >
              All
            </button>
            <button
              onClick={() => setTypeFilter('ai')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                typeFilter === 'ai'
                  ? 'bg-theme-accent text-white'
                  : 'text-theme-secondary hover:bg-theme-bg-subtle'
              }`}
            >
              AI-Powered
            </button>
            <button
              onClick={() => setTypeFilter('git')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                typeFilter === 'git'
                  ? 'bg-theme-info text-white'
                  : 'text-theme-secondary hover:bg-theme-bg-subtle'
              }`}
            >
              Git-Native
            </button>
          </div>
        </div>

        <div className="divide-y divide-theme">
          {filteredRuns.length === 0 ? (
            <div className="p-8 text-center">
              <History className="w-12 h-12 mx-auto mb-3 text-theme-secondary opacity-50" />
              <p className="text-theme-secondary">No recent pipeline runs</p>
              <p className="text-sm text-theme-tertiary mt-1">
                Create a pipeline to get started with automation
              </p>
            </div>
          ) : (
            filteredRuns.map((run) => (
              <Link
                key={run.id}
                to={`/app/automation/runs/${run.id}`}
                className="flex items-center justify-between p-4 hover:bg-theme-bg-subtle transition-colors"
              >
                <div className="flex items-center gap-4">
                  {getStatusIcon(run.status)}
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-theme-primary">{run.pipelineName}</span>
                      {getTypeLabel(run.pipelineType)}
                    </div>
                    <p className="text-sm text-theme-secondary">
                      Triggered by {run.trigger} • {run.startedAt}
                    </p>
                  </div>
                </div>
                <div className="text-right">
                  {run.duration && (
                    <p className="text-sm text-theme-primary">{run.duration}</p>
                  )}
                  {run.status === 'running' && (
                    <p className="text-sm text-theme-info">In progress...</p>
                  )}
                </div>
              </Link>
            ))
          )}
        </div>

        {filteredRuns.length > 0 && (
          <div className="p-4 border-t border-theme">
            <Link
              to="/app/automation/runs"
              className="text-sm text-theme-primary hover:underline flex items-center gap-1"
            >
              View all runs
              <ArrowRight className="w-3 h-3" />
            </Link>
          </div>
        )}
      </div>
    </PageContainer>
  );
}

export default AutomationOverview;
