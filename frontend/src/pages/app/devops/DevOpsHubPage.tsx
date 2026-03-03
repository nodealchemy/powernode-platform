import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  GitBranch,
  FolderGit2,
  Server,
  Workflow,
  Container,
  HardDrive,
  Puzzle,
  Activity,
  CheckCircle,
  RefreshCw,
  ArrowRight,
  AlertTriangle,
  Play,
  Zap
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { logger } from '@/shared/utils/logger';
import { devopsOverviewApi } from '@/services/devopsOverviewApi';
import type { DevopsOverviewResponse } from '@/services/devopsOverviewApi';

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

interface SectionCard {
  id: string;
  name: string;
  description: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
  stats: Array<{ label: string; value: string | number }>;
  status: 'success' | 'warning' | 'error' | 'neutral';
}

export function DevOpsHubPage() {
  const navigate = useNavigate();
  usePageWebSocket({
    pageType: 'devops',
    onDataUpdate: () => { loadStats(true); }
  });

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [data, setData] = useState<DevopsOverviewResponse | null>(null);

  const loadStats = async (showRefreshing = false) => {
    if (showRefreshing) setRefreshing(true);
    else setLoading(true);

    try {
      const overview = await devopsOverviewApi.getOverview(showRefreshing);
      setData(overview);
    } catch (error) {
      logger.error('Failed to load DevOps overview', error);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    loadStats();
  }, []);

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'DevOps' }
  ];

  const actions = [
    {
      id: 'refresh',
      label: refreshing ? 'Refreshing...' : 'Refresh',
      onClick: () => loadStats(true),
      variant: 'secondary' as const,
      icon: RefreshCw,
      disabled: refreshing
    }
  ];

  if (loading || !data) {
    return (
      <PageContainer title="DevOps Overview" description="Infrastructure and development operations" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
          <span className="ml-3 text-theme-secondary">Loading DevOps dashboard...</span>
        </div>
      </PageContainer>
    );
  }

  const { source_control: sc, ci_cd: cicd, infrastructure: infra, connections: conns, alerts: serverAlerts } = data;

  const totalRunners = cicd.runners.total;
  const successRuns = cicd.pipeline_runs.successful;
  const failedRuns = cicd.pipeline_runs.failed;
  const totalStatusRuns = successRuns + failedRuns;
  const totalConnections = conns.integrations.total + conns.webhooks.total + conns.api_keys.total;

  // Build section cards for navigation
  const sectionCards: SectionCard[] = [
    {
      id: 'source-control',
      name: 'Source Control',
      description: 'Git providers, repositories, and commit activity',
      href: '/app/devops/source-control',
      icon: GitBranch,
      stats: [
        { label: 'Providers', value: `${sc.providers.active} / ${sc.providers.total}` },
        { label: 'Repositories', value: sc.repositories.total },
      ],
      status: sc.providers.active > 0 ? 'success' : 'neutral',
    },
    {
      id: 'ci-cd',
      name: 'CI/CD',
      description: 'Pipelines, runs, and self-hosted runners',
      href: '/app/devops/ci-cd',
      icon: Workflow,
      stats: [
        { label: 'Pipelines', value: `${cicd.pipelines.active} active` },
        { label: 'Runners', value: `${cicd.runners.online} online` },
      ],
      status: cicd.runners.offline > 0 ? 'warning' : (cicd.pipelines.active > 0 ? 'success' : 'neutral'),
    },
    {
      id: 'connections',
      name: 'Connections',
      description: 'Integrations, webhooks, and API keys',
      href: '/app/devops/connections',
      icon: Puzzle,
      stats: [
        { label: 'Integrations', value: conns.integrations.total },
        { label: 'Webhooks', value: conns.webhooks.total },
      ],
      status: conns.integrations.errored > 0 ? 'error' : (conns.integrations.active > 0 ? 'success' : 'neutral'),
    },
    {
      id: 'sandboxes',
      name: 'Sandboxes',
      description: 'Container execution and resource quotas',
      href: '/app/devops/sandboxes',
      icon: Container,
      stats: [
        { label: 'Active', value: infra.containers.active },
        { label: 'Success Rate', value: infra.containers.total > 0 ? `${Math.round(infra.containers.success_rate)}%` : '-' },
      ],
      status: infra.containers.active > 0 ? 'success' : 'neutral',
    },
    {
      id: 'swarm',
      name: 'Swarm',
      description: 'Docker Swarm clusters and orchestration',
      href: '/app/devops/swarm',
      icon: Server,
      stats: [
        { label: 'Clusters', value: infra.swarm.clusters },
        { label: 'Connected', value: infra.swarm.connected },
      ],
      status: infra.swarm.clusters > 0 && infra.swarm.connected < infra.swarm.clusters ? 'error' : (infra.swarm.connected > 0 ? 'success' : 'neutral'),
    },
    {
      id: 'docker',
      name: 'Docker',
      description: 'Docker hosts, containers, and images',
      href: '/app/devops/docker',
      icon: HardDrive,
      stats: [
        { label: 'Hosts', value: infra.docker.hosts },
        { label: 'Connected', value: infra.docker.connected },
      ],
      status: infra.docker.hosts > 0 && infra.docker.connected < infra.docker.hosts ? 'error' : (infra.docker.connected > 0 ? 'success' : 'neutral'),
    },
  ];

  // Map server alerts to UI alerts with navigation links
  const alertHrefMap: Record<string, string> = {
    source_control: '/app/devops/source-control',
    ci_cd: '/app/devops/ci-cd',
    connections: '/app/devops/connections',
    infrastructure: '/app/devops/sandboxes',
  };

  return (
    <PageContainer
      title="DevOps Overview"
      description="Infrastructure, pipelines, and development operations dashboard"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Alerts banner */}
        {serverAlerts.length > 0 && (
          <div className="bg-theme-warning/10 border border-theme-warning/30 rounded-lg p-4">
            <h3 className="font-semibold text-theme-warning flex items-center gap-2 mb-3">
              <AlertTriangle className="w-5 h-5" />
              Attention Required
            </h3>
            <div className="space-y-2">
              {serverAlerts.map((alert, idx) => (
                <div key={idx} className="flex items-center justify-between text-sm">
                  <span className={alert.level === 'error' ? 'text-theme-error' : 'text-theme-secondary'}>
                    {alert.message}
                  </span>
                  <button onClick={() => navigate(alertHrefMap[alert.section] || '/app/devops')} className="text-theme-primary hover:underline">
                    Review
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Key Metrics — top-level numbers across all DevOps */}
        <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-8 gap-4">
          <StatCard
            title="Git Providers"
            value={sc.providers.active}
            subtitle={`${sc.providers.total} configured`}
            icon={GitBranch}
            status={sc.providers.active > 0 ? 'success' : 'neutral'}
            onClick={() => navigate('/app/devops/source-control/providers')}
          />
          <StatCard
            title="Repositories"
            value={sc.repositories.total}
            subtitle={`${sc.repositories.with_webhook} with hooks`}
            icon={FolderGit2}
            status={sc.repositories.total > 0 ? 'success' : 'neutral'}
            onClick={() => navigate('/app/devops/source-control/repositories')}
          />
          <StatCard
            title="Pipelines"
            value={cicd.pipelines.active}
            subtitle={`${cicd.pipelines.total} total`}
            icon={Workflow}
            status={cicd.pipelines.active > 0 ? 'success' : 'neutral'}
            onClick={() => navigate('/app/devops/ci-cd/pipelines')}
          />
          <StatCard
            title="Runners"
            value={cicd.runners.online}
            subtitle={`${totalRunners} total`}
            icon={Play}
            status={cicd.runners.online > 0 ? 'success' : (totalRunners > 0 ? 'warning' : 'neutral')}
            onClick={() => navigate('/app/devops/ci-cd/runners')}
          />
          <StatCard
            title="Swarm"
            value={infra.swarm.connected}
            subtitle={`${infra.swarm.clusters} cluster${infra.swarm.clusters !== 1 ? 's' : ''}`}
            icon={Server}
            status={infra.swarm.clusters > 0 && infra.swarm.connected < infra.swarm.clusters ? 'error' : (infra.swarm.connected > 0 ? 'success' : 'neutral')}
            onClick={() => navigate('/app/devops/swarm')}
          />
          <StatCard
            title="Docker"
            value={infra.docker.connected}
            subtitle={`${infra.docker.hosts} host${infra.docker.hosts !== 1 ? 's' : ''}`}
            icon={HardDrive}
            status={infra.docker.hosts > 0 && infra.docker.connected < infra.docker.hosts ? 'error' : (infra.docker.connected > 0 ? 'success' : 'neutral')}
            onClick={() => navigate('/app/devops/docker')}
          />
          <StatCard
            title="Containers"
            value={infra.containers.active}
            subtitle={`${infra.containers.total} total`}
            icon={Container}
            status={infra.containers.active > 0 ? 'success' : 'neutral'}
            onClick={() => navigate('/app/devops/sandboxes')}
          />
          <StatCard
            title="Connections"
            value={totalConnections}
            subtitle={conns.integrations.errored > 0 ? `${conns.integrations.errored} errors` : `${conns.integrations.active} active`}
            icon={Puzzle}
            status={conns.integrations.errored > 0 ? 'error' : (totalConnections > 0 ? 'success' : 'neutral')}
            onClick={() => navigate('/app/devops/connections')}
          />
        </div>

        {/* Status Panels */}
        <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
          {/* Runner Health */}
          <div className="bg-theme-surface border border-theme rounded-lg p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <Activity className="w-5 h-5" />
                Runner Health
              </h3>
              <button onClick={() => navigate('/app/devops/ci-cd/runners')} className="text-sm text-theme-primary hover:underline">
                View all
              </button>
            </div>
            {totalRunners > 0 ? (
              <div className="space-y-3">
                <div className="flex flex-wrap items-center gap-x-4 gap-y-1">
                  <StatusIndicator label="Online" value={cicd.runners.online} total={totalRunners} type="success" />
                  <StatusIndicator label="Busy" value={cicd.runners.busy} total={totalRunners} type="warning" />
                  <StatusIndicator label="Offline" value={cicd.runners.offline} total={totalRunners} type="error" />
                </div>
                <div className="h-2 bg-theme-secondary/20 rounded-full overflow-hidden flex">
                  <div className="bg-theme-success transition-all" style={{ width: `${(cicd.runners.online / totalRunners) * 100}%` }} />
                  <div className="bg-theme-warning transition-all" style={{ width: `${(cicd.runners.busy / totalRunners) * 100}%` }} />
                  <div className="bg-theme-error transition-all" style={{ width: `${(cicd.runners.offline / totalRunners) * 100}%` }} />
                </div>
              </div>
            ) : (
              <div className="text-center py-4">
                <Server className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
                <p className="text-sm text-theme-secondary">No runners configured</p>
              </div>
            )}
          </div>

          {/* Pipeline Success Rate */}
          <div className="bg-theme-surface border border-theme rounded-lg p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <CheckCircle className="w-5 h-5" />
                Pipeline Runs
              </h3>
              <button onClick={() => navigate('/app/devops/ci-cd')} className="text-sm text-theme-primary hover:underline">
                View all
              </button>
            </div>
            {cicd.pipeline_runs.total > 0 ? (
              <div className="space-y-3">
                <div className="grid grid-cols-3 gap-2 text-center">
                  <div>
                    <p className="text-xl font-bold text-theme-success">{successRuns}</p>
                    <p className="text-[10px] text-theme-tertiary">Passed</p>
                  </div>
                  <div>
                    <p className="text-xl font-bold text-theme-error">{failedRuns}</p>
                    <p className="text-[10px] text-theme-tertiary">Failed</p>
                  </div>
                  <div>
                    <p className="text-xl font-bold text-theme-primary">{cicd.pipeline_runs.running}</p>
                    <p className="text-[10px] text-theme-tertiary">Running</p>
                  </div>
                </div>
                {totalStatusRuns > 0 && (
                  <>
                    <div className="h-2 bg-theme-secondary/20 rounded-full overflow-hidden flex">
                      <div className="bg-theme-success transition-all" style={{ width: `${(successRuns / totalStatusRuns) * 100}%` }} />
                      <div className="bg-theme-error transition-all" style={{ width: `${(failedRuns / totalStatusRuns) * 100}%` }} />
                    </div>
                    <p className="text-center text-xs text-theme-secondary">
                      {cicd.pipeline_runs.success_rate}% success rate
                    </p>
                  </>
                )}
              </div>
            ) : (
              <div className="text-center py-4">
                <Workflow className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
                <p className="text-sm text-theme-secondary">No pipeline runs yet</p>
              </div>
            )}
          </div>

          {/* Container Execution */}
          <div className="bg-theme-surface border border-theme rounded-lg p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <Container className="w-5 h-5" />
                Container Execution
              </h3>
              <button onClick={() => navigate('/app/devops/sandboxes')} className="text-sm text-theme-primary hover:underline">
                View all
              </button>
            </div>
            {infra.containers.total > 0 ? (
              <div className="space-y-3">
                <div className="grid grid-cols-3 gap-2 text-center">
                  <div>
                    <p className="text-xl font-bold text-theme-primary">{infra.containers.total}</p>
                    <p className="text-[10px] text-theme-tertiary">Total</p>
                  </div>
                  <div>
                    <p className="text-xl font-bold text-theme-success">{infra.containers.completed}</p>
                    <p className="text-[10px] text-theme-tertiary">Completed</p>
                  </div>
                  <div>
                    <p className="text-xl font-bold text-theme-error">{infra.containers.failed}</p>
                    <p className="text-[10px] text-theme-tertiary">Failed</p>
                  </div>
                </div>
                <div className="h-2 bg-theme-secondary/20 rounded-full overflow-hidden flex">
                  {infra.containers.finished > 0 && (
                    <>
                      <div className="bg-theme-success transition-all" style={{ width: `${(infra.containers.completed / infra.containers.finished) * 100}%` }} />
                      <div className="bg-theme-error transition-all" style={{ width: `${(infra.containers.failed / infra.containers.finished) * 100}%` }} />
                    </>
                  )}
                </div>
                <p className="text-center text-xs text-theme-secondary">
                  {Math.round(infra.containers.success_rate)}% success rate
                </p>
              </div>
            ) : (
              <div className="text-center py-4">
                <Container className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
                <p className="text-sm text-theme-secondary">No container executions</p>
              </div>
            )}
          </div>

          {/* Webhook Deliveries */}
          <div className="bg-theme-surface border border-theme rounded-lg p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <Zap className="w-5 h-5" />
                Webhooks Today
              </h3>
              <button onClick={() => navigate('/app/devops/connections/webhooks')} className="text-sm text-theme-primary hover:underline">
                View all
              </button>
            </div>
            {(conns.webhooks.processed_today + conns.webhooks.failed_today) > 0 ? (
              <div className="space-y-3">
                <div className="grid grid-cols-3 gap-2 text-center">
                  <div>
                    <p className="text-xl font-bold text-theme-primary">{conns.webhooks.processed_today + conns.webhooks.failed_today}</p>
                    <p className="text-[10px] text-theme-tertiary">Total</p>
                  </div>
                  <div>
                    <p className="text-xl font-bold text-theme-success">{conns.webhooks.processed_today}</p>
                    <p className="text-[10px] text-theme-tertiary">Processed</p>
                  </div>
                  <div>
                    <p className="text-xl font-bold text-theme-error">{conns.webhooks.failed_today}</p>
                    <p className="text-[10px] text-theme-tertiary">Failed</p>
                  </div>
                </div>
                {conns.webhooks.failed_today > 0 && (
                  <div className="flex items-center gap-2 p-2 bg-theme-error/10 rounded text-xs text-theme-error">
                    <AlertTriangle className="w-3.5 h-3.5" />
                    <span>{conns.webhooks.failed_today} failed</span>
                  </div>
                )}
              </div>
            ) : (
              <div className="text-center py-4">
                <CheckCircle className="w-8 h-8 text-theme-success mx-auto mb-2" />
                <p className="text-sm text-theme-secondary">No webhook activity today</p>
              </div>
            )}
          </div>
        </div>

        {/* Section Navigation Cards */}
        <div>
          <h3 className="font-semibold text-theme-primary mb-4">DevOps Sections</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {sectionCards.map((section) => {
              const SectionIcon = section.icon;
              const statusColors = {
                success: 'border-theme-success/30',
                warning: 'border-theme-warning/30',
                error: 'border-theme-error/30',
                neutral: 'border-theme',
              };
              return (
                <div
                  key={section.id}
                  onClick={() => navigate(section.href)}
                  className={`bg-theme-surface border ${statusColors[section.status]} rounded-lg p-5 cursor-pointer hover:border-theme-primary transition-colors group`}
                >
                  <div className="flex items-start justify-between mb-3">
                    <div className="flex items-center gap-3">
                      <div className="p-2 rounded-lg bg-theme-primary/10">
                        <SectionIcon className="w-5 h-5 text-theme-primary" />
                      </div>
                      <div>
                        <h4 className="font-medium text-theme-primary">{section.name}</h4>
                        <p className="text-xs text-theme-tertiary">{section.description}</p>
                      </div>
                    </div>
                    <ArrowRight className="w-4 h-4 text-theme-tertiary group-hover:text-theme-primary transition-colors" />
                  </div>
                  <div className="flex items-center gap-4 pl-12">
                    {section.stats.map((stat, idx) => (
                      <div key={idx} className="text-xs">
                        <span className="text-theme-tertiary">{stat.label}: </span>
                        <span className="font-medium text-theme-primary">{stat.value}</span>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </PageContainer>
  );
}

export default DevOpsHubPage;
