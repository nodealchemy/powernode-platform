import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Play,
  Activity,
  CheckCircle,
  Server,
  RefreshCw,
  ArrowRight,
  AlertTriangle,
  XCircle,
  Clock
} from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { logger } from '@/shared/utils/logger';
import { devopsPipelinesApi, devopsPipelineRunsApi } from '@/services/devopsPipelinesApi';
import { runnersApi } from '@/features/devops/git/services/git/runnersApi';
import type { RunnerStats } from '@/features/devops/git/types';
import type { DevopsPipelineRun } from '@/types/devops-pipelines';

interface CiCdStats {
  totalPipelines: number;
  activePipelines: number;
  totalRuns: number;
  runners: RunnerStats | null;
  statusCounts: Record<string, number>;
}

const StatCard: React.FC<{
  title: string;
  value: string | number;
  subtitle?: string;
  icon: React.ComponentType<{ className?: string }>;
  status?: 'success' | 'warning' | 'error' | 'neutral';
  onClick?: () => void;
}> = ({ title, value, subtitle, icon: Icon, status = 'neutral', onClick }) => {
  const statusColors = {
    success: 'text-theme-success',
    warning: 'text-theme-warning',
    error: 'text-theme-error',
    neutral: 'text-theme-primary'
  };

  const statusBgColors = {
    success: 'bg-theme-success/10',
    warning: 'bg-theme-warning/10',
    error: 'bg-theme-error/10',
    neutral: 'bg-theme-primary/10'
  };

  return (
    <div
      onClick={onClick}
      className={`bg-theme-surface border border-theme rounded-lg p-4 ${onClick ? 'cursor-pointer hover:border-theme-primary transition-colors' : ''}`}
    >
      <div className="flex items-start justify-between">
        <div>
          <p className="text-sm text-theme-secondary">{title}</p>
          <p className={`text-2xl font-bold mt-1 ${statusColors[status]}`}>{value}</p>
          {subtitle && <p className="text-xs text-theme-tertiary mt-1">{subtitle}</p>}
        </div>
        <div className={`p-2 rounded-lg ${statusBgColors[status]}`}>
          <Icon className={`w-5 h-5 ${statusColors[status]}`} />
        </div>
      </div>
    </div>
  );
};

const StatusIndicator: React.FC<{
  label: string;
  value: number;
  total: number;
  type: 'success' | 'warning' | 'error';
}> = ({ label, value, total, type }) => {
  const colors = {
    success: 'bg-theme-success',
    warning: 'bg-theme-warning',
    error: 'bg-theme-error'
  };

  const percentage = total > 0 ? Math.round((value / total) * 100) : 0;

  return (
    <div className="flex items-center gap-2">
      <span className={`w-2 h-2 rounded-full ${colors[type]}`} />
      <span className="text-sm text-theme-secondary">{label}:</span>
      <span className="text-sm font-medium text-theme-primary">{value}</span>
      <span className="text-xs text-theme-tertiary">({percentage}%)</span>
    </div>
  );
};

const runStatusConfig: Record<string, { icon: React.ComponentType<{ className?: string }>; color: string }> = {
  completed: { icon: CheckCircle, color: 'text-theme-success' },
  success: { icon: CheckCircle, color: 'text-theme-success' },
  running: { icon: Activity, color: 'text-theme-info' },
  pending: { icon: Clock, color: 'text-theme-warning' },
  queued: { icon: Clock, color: 'text-theme-warning' },
  failed: { icon: XCircle, color: 'text-theme-error' },
  cancelled: { icon: XCircle, color: 'text-theme-tertiary' },
};

export function CiCdOverviewTab() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [stats, setStats] = useState<CiCdStats>({
    totalPipelines: 0,
    activePipelines: 0,
    totalRuns: 0,
    runners: null,
    statusCounts: {},
  });
  const [recentRuns, setRecentRuns] = useState<DevopsPipelineRun[]>([]);

  const loadStats = async (showRefreshing = false) => {
    if (showRefreshing) setRefreshing(true);
    else setLoading(true);

    try {
      const [pipelinesData, runsData, runnersData] = await Promise.all([
        devopsPipelinesApi.getAll().catch(() => ({ pipelines: [], meta: { total: 0, active_count: 0, total_runs: 0 } })),
        devopsPipelineRunsApi.getAll({ per_page: 5 }).catch(() => ({ pipeline_runs: [], meta: { total: 0, page: 1, per_page: 5, total_pages: 0, status_counts: {} } })),
        runnersApi.getRunners({ per_page: 1 }).catch(() => ({ runners: [], stats: { total: 0, online: 0, offline: 0, busy: 0 }, pagination: { total_count: 0 } })),
      ]);

      setStats({
        totalPipelines: pipelinesData.meta.total,
        activePipelines: pipelinesData.meta.active_count,
        totalRuns: pipelinesData.meta.total_runs,
        runners: runnersData.stats,
        statusCounts: runsData.meta.status_counts,
      });
      setRecentRuns(runsData.pipeline_runs);
    } catch (error) {
      logger.error('Failed to load CI/CD stats', error);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    loadStats();
  }, []);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
        <span className="ml-3 text-theme-secondary">Loading CI/CD dashboard...</span>
      </div>
    );
  }

  const totalRunners = stats.runners?.total || 0;
  const successCount = (stats.statusCounts['completed'] || 0) + (stats.statusCounts['success'] || 0);
  const failedCount = stats.statusCounts['failed'] || 0;
  const cancelledCount = stats.statusCounts['cancelled'] || 0;
  const totalStatusRuns = successCount + failedCount + cancelledCount;

  const quickLinks = [
    { id: 'pipelines', name: 'Pipelines', description: 'View and manage CI/CD pipelines', href: '/app/devops/ci-cd/pipelines' },
    { id: 'runners', name: 'Runners', description: 'Manage self-hosted runners', href: '/app/devops/ci-cd/runners' },
    { id: 'new-pipeline', name: 'Create Pipeline', description: 'Set up a new CI/CD pipeline', href: '/app/devops/ci-cd/pipelines/new' },
  ];

  return (
    <div className="space-y-6">
      {/* Header with refresh */}
      <div className="flex items-center justify-between">
        <h3 className="font-semibold text-theme-primary">Key Metrics</h3>
        <button
          onClick={() => loadStats(true)}
          disabled={refreshing}
          className="flex items-center gap-1.5 text-sm text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${refreshing ? 'animate-spin' : ''}`} />
          {refreshing ? 'Refreshing...' : 'Refresh'}
        </button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard
          title="Total Pipelines"
          value={stats.totalPipelines}
          subtitle={`${stats.activePipelines} active`}
          icon={Play}
          status={stats.totalPipelines > 0 ? 'success' : 'neutral'}
          onClick={() => navigate('/app/devops/ci-cd/pipelines')}
        />
        <StatCard
          title="Active Pipelines"
          value={stats.activePipelines}
          subtitle={`of ${stats.totalPipelines} total`}
          icon={Activity}
          status={stats.activePipelines > 0 ? 'success' : 'neutral'}
          onClick={() => navigate('/app/devops/ci-cd/pipelines')}
        />
        <StatCard
          title="Total Runs"
          value={stats.totalRuns}
          icon={CheckCircle}
          status={stats.totalRuns > 0 ? 'success' : 'neutral'}
        />
        <StatCard
          title="Runners Online"
          value={`${stats.runners?.online || 0} / ${totalRunners}`}
          subtitle={stats.runners?.busy ? `${stats.runners.busy} busy` : undefined}
          icon={Server}
          status={stats.runners?.online ? (stats.runners.online > 0 ? 'success' : 'warning') : 'neutral'}
          onClick={() => navigate('/app/devops/ci-cd/runners')}
        />
      </div>

      {/* Status Panels */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Runner Health */}
        <div className="bg-theme-surface border border-theme rounded-lg p-5">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-semibold text-theme-primary flex items-center gap-2">
              <Server className="w-5 h-5" />
              Runner Health
            </h3>
            <button
              onClick={() => navigate('/app/devops/ci-cd/runners')}
              className="text-sm text-theme-primary hover:underline"
            >
              View all
            </button>
          </div>
          {stats.runners && totalRunners > 0 ? (
            <div className="space-y-3">
              <div className="flex items-center gap-4">
                <StatusIndicator label="Online" value={stats.runners.online} total={totalRunners} type="success" />
                <StatusIndicator label="Busy" value={stats.runners.busy} total={totalRunners} type="warning" />
                <StatusIndicator label="Offline" value={stats.runners.offline} total={totalRunners} type="error" />
              </div>
              <div className="h-2 bg-theme-secondary/20 rounded-full overflow-hidden flex">
                <div
                  className="bg-theme-success transition-all"
                  style={{ width: `${(stats.runners.online / totalRunners) * 100}%` }}
                />
                <div
                  className="bg-theme-warning transition-all"
                  style={{ width: `${(stats.runners.busy / totalRunners) * 100}%` }}
                />
                <div
                  className="bg-theme-error transition-all"
                  style={{ width: `${(stats.runners.offline / totalRunners) * 100}%` }}
                />
              </div>
            </div>
          ) : (
            <div className="text-center py-4">
              <Server className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
              <p className="text-sm text-theme-secondary">No runners configured</p>
              <button
                onClick={() => navigate('/app/devops/ci-cd/runners')}
                className="text-sm text-theme-primary hover:underline mt-1"
              >
                Sync runners
              </button>
            </div>
          )}
        </div>

        {/* Recent Runs */}
        <div className="bg-theme-surface border border-theme rounded-lg p-5">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-semibold text-theme-primary flex items-center gap-2">
              <Activity className="w-5 h-5" />
              Recent Runs
            </h3>
            <button
              onClick={() => navigate('/app/devops/ci-cd/pipelines')}
              className="text-sm text-theme-primary hover:underline"
            >
              View all
            </button>
          </div>
          {recentRuns.length > 0 ? (
            <div className="space-y-2">
              {recentRuns.map((run) => {
                const config = runStatusConfig[run.status] || runStatusConfig['pending'];
                const StatusIcon = config.icon;
                return (
                  <div
                    key={run.id}
                    onClick={() => run.pipeline_name && navigate(`/app/devops/ci-cd/pipelines/${run.id}`)}
                    className="flex items-center justify-between py-1.5 cursor-pointer hover:bg-theme-surface-hover rounded px-2 -mx-2 transition-colors"
                  >
                    <div className="flex items-center gap-2 min-w-0">
                      <StatusIcon className={`w-4 h-4 flex-shrink-0 ${config.color}`} />
                      <span className="text-sm text-theme-primary truncate">
                        {run.pipeline_name || `Run #${run.run_number}`}
                      </span>
                    </div>
                    <span className={`text-xs flex-shrink-0 ${config.color}`}>
                      {run.status}
                    </span>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="text-center py-4">
              <Play className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
              <p className="text-sm text-theme-secondary">No pipeline runs yet</p>
              <button
                onClick={() => navigate('/app/devops/ci-cd/pipelines/new')}
                className="text-sm text-theme-primary hover:underline mt-1"
              >
                Create a pipeline
              </button>
            </div>
          )}
        </div>

        {/* Pipeline Success Rate */}
        <div className="bg-theme-surface border border-theme rounded-lg p-5">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-semibold text-theme-primary flex items-center gap-2">
              <CheckCircle className="w-5 h-5" />
              Pipeline Success Rate
            </h3>
          </div>
          {totalStatusRuns > 0 ? (
            <div className="space-y-3">
              <div className="grid grid-cols-3 gap-4 text-center">
                <div>
                  <p className="text-2xl font-bold text-theme-success">{successCount}</p>
                  <p className="text-xs text-theme-tertiary">Successful</p>
                </div>
                <div>
                  <p className="text-2xl font-bold text-theme-error">{failedCount}</p>
                  <p className="text-xs text-theme-tertiary">Failed</p>
                </div>
                <div>
                  <p className="text-2xl font-bold text-theme-tertiary">{cancelledCount}</p>
                  <p className="text-xs text-theme-tertiary">Cancelled</p>
                </div>
              </div>
              <div className="h-2 bg-theme-secondary/20 rounded-full overflow-hidden flex">
                <div
                  className="bg-theme-success transition-all"
                  style={{ width: `${(successCount / totalStatusRuns) * 100}%` }}
                />
                <div
                  className="bg-theme-error transition-all"
                  style={{ width: `${(failedCount / totalStatusRuns) * 100}%` }}
                />
                <div
                  className="bg-theme-tertiary transition-all"
                  style={{ width: `${(cancelledCount / totalStatusRuns) * 100}%` }}
                />
              </div>
              <div className="text-center text-sm text-theme-secondary">
                {totalStatusRuns > 0 ? Math.round((successCount / totalStatusRuns) * 100) : 0}% success rate
              </div>
            </div>
          ) : (
            <div className="text-center py-4">
              <CheckCircle className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
              <p className="text-sm text-theme-secondary">No run data available</p>
            </div>
          )}
        </div>
      </div>

      {/* Quick Links */}
      <div>
        <h3 className="font-semibold text-theme-primary mb-4">Quick Access</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {quickLinks.map((link) => (
            <div
              key={link.id}
              onClick={() => navigate(link.href)}
              className="bg-theme-surface border border-theme rounded-lg p-4 cursor-pointer hover:border-theme-primary transition-colors"
            >
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="font-medium text-theme-primary">{link.name}</h4>
                  <p className="text-xs text-theme-tertiary mt-1">{link.description}</p>
                </div>
                <ArrowRight className="w-4 h-4 text-theme-tertiary" />
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Alerts */}
      {stats.runners && stats.runners.offline > 0 && (
        <div className="bg-theme-warning/10 border border-theme-warning/30 rounded-lg p-4">
          <h3 className="font-semibold text-theme-warning flex items-center gap-2 mb-3">
            <AlertTriangle className="w-5 h-5" />
            Attention Required
          </h3>
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">
              {stats.runners.offline} runner{stats.runners.offline > 1 ? 's' : ''} offline
            </span>
            <button
              onClick={() => navigate('/app/devops/ci-cd/runners')}
              className="text-theme-primary hover:underline"
            >
              Check status
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export default CiCdOverviewTab;
