import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  GitBranch,
  FolderGit2,
  Server,
  Link2,
  Puzzle,
  Key,
  Activity,
  CheckCircle,
  RefreshCw,
  ArrowRight,
  AlertTriangle,
  Zap,
  GitCommit
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { logger } from '@/shared/utils/logger';
import { gitProvidersApi } from '@/features/devops/git/services/gitProvidersApi';
import { webhooksApi } from '@/features/devops/webhooks/services/webhooksApi';
import { integrationsApi } from '@/features/devops/integrations/services/integrationsApi';
import { apiKeysApi } from '@/features/devops/api-keys/services/apiKeysApi';
import type { RunnerStats } from '@/features/devops/git/types';
import type { WebhookStats } from '@/features/devops/webhooks/services/webhooksApi';
import type { ApiKeyStats } from '@/features/devops/api-keys/services/apiKeysApi';

interface DevOpsStats {
  providers: { total: number; active: number };
  repositories: { total: number; withWebhooks: number };
  runners: RunnerStats | null;
  webhooks: WebhookStats | null;
  integrations: { total: number; active: number; errors: number };
  apiKeys: ApiKeyStats | null;
}

interface QuickLink {
  id: string;
  name: string;
  description: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
  stat?: string | number;
  status?: 'success' | 'warning' | 'error' | 'neutral';
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

const QuickLinkCard: React.FC<QuickLink & { onClick: () => void }> = ({
  name,
  description,
  icon: Icon,
  stat,
  onClick
}) => {
  return (
    <div
      onClick={onClick}
      className="bg-theme-surface border border-theme rounded-lg p-4 cursor-pointer hover:border-theme-primary transition-colors"
    >
      <div className="flex items-center gap-3">
        <div className="p-2 rounded-lg bg-theme-primary/10">
          <Icon className="w-5 h-5 text-theme-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between">
            <h3 className="font-medium text-theme-primary truncate">{name}</h3>
            {stat !== undefined && (
              <span className="text-sm font-semibold text-theme-secondary">{stat}</span>
            )}
          </div>
          <p className="text-xs text-theme-tertiary truncate">{description}</p>
        </div>
        <ArrowRight className="w-4 h-4 text-theme-tertiary" />
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

interface WeeklyActivity {
  weekStart: string;
  weekLabel: string;
  count: number;
}

export function DevOpsOverviewPage() {
  const navigate = useNavigate();
  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'devops',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [stats, setStats] = useState<DevOpsStats>({
    providers: { total: 0, active: 0 },
    repositories: { total: 0, withWebhooks: 0 },
    runners: null,
    webhooks: null,
    integrations: { total: 0, active: 0, errors: 0 },
    apiKeys: null
  });
  const [activityData, setActivityData] = useState<Map<string, number>>(new Map());
  const [loadingActivity, setLoadingActivity] = useState(false);


  const loadStats = async (showRefreshing = false) => {
    if (showRefreshing) setRefreshing(true);
    else setLoading(true);

    try {
      // Fetch all stats in parallel
      const [
        providersData,
        reposData,
        runnersData,
        webhooksData,
        integrationsData,
        apiKeysData
      ] = await Promise.all([
        gitProvidersApi.getProviders().catch(() => []),
        gitProvidersApi.getRepositories({ per_page: 1 }).catch(() => ({ repositories: [], pagination: { total_count: 0 } })),
        gitProvidersApi.getRunners({ per_page: 1 }).catch(() => ({ runners: [], stats: null, pagination: { total_count: 0 } })),
        webhooksApi.getWebhooks(1, 1).catch(() => ({ success: false, data: null })),
        integrationsApi.getInstances(1, 1).catch(() => ({ success: false, data: null })),
        apiKeysApi.getApiKeys(1, 1).catch(() => ({ success: false, data: null }))
      ]);

      // Process providers
      const providers = providersData as { id: string; is_enabled?: boolean }[];
      const activeProviders = providers.filter(p => p.is_enabled !== false).length;

      // Process repositories
      const reposResult = reposData as { repositories: { webhook_configured?: boolean }[]; pagination: { total_count: number } };
      const webhookConfiguredRepos = reposResult.repositories?.filter(r => r.webhook_configured).length || 0;

      // Process integrations
      const integrationsResult = integrationsData as { success: boolean; data?: { instances: { status: string }[]; pagination: { total_count: number } } };
      let integrationStats = { total: 0, active: 0, errors: 0 };
      if (integrationsResult.success && integrationsResult.data) {
        integrationStats = {
          total: integrationsResult.data.pagination.total_count,
          active: integrationsResult.data.instances.filter(i => i.status === 'active').length,
          errors: integrationsResult.data.instances.filter(i => i.status === 'error').length
        };
      }

      setStats({
        providers: { total: providers.length, active: activeProviders },
        repositories: {
          total: reposResult.pagination?.total_count || 0,
          withWebhooks: webhookConfiguredRepos
        },
        runners: (runnersData as { stats: RunnerStats | null }).stats,
        webhooks: (webhooksData as { success: boolean; data?: { stats: WebhookStats } }).success
          ? (webhooksData as { data: { stats: WebhookStats } }).data?.stats || null
          : null,
        integrations: integrationStats,
        apiKeys: (apiKeysData as { success: boolean; data?: { stats: ApiKeyStats } }).success
          ? (apiKeysData as { data: { stats: ApiKeyStats } }).data?.stats || null
          : null
      });
    } catch (error) {
      logger.error('Failed to load DevOps stats', error);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    loadStats();
  }, []);

  // Load commit activity from repositories
  useEffect(() => {
    const loadActivity = async () => {
      if (stats.repositories.total === 0) return;

      setLoadingActivity(true);
      try {
        // Get first few repositories to sample activity
        const reposResult = await gitProvidersApi.getRepositories({ per_page: 5 }) as {
          repositories: { id: string }[]
        };

        const activity = new Map<string, number>();
        const seenShas = new Set<string>();

        // Fetch commits from each repository
        for (const repo of reposResult.repositories || []) {
          try {
            const commits = await gitProvidersApi.getCommits(repo.id, { per_page: 30 }) as Array<{
              sha?: string;
              created_at?: string;
              commit?: { author?: { date?: string } };
            }>;

            (commits || []).forEach((commit) => {
              if (commit.sha && seenShas.has(commit.sha)) return;
              if (commit.sha) seenShas.add(commit.sha);

              const dateStr = commit.created_at || commit.commit?.author?.date;
              if (dateStr) {
                const date = new Date(dateStr).toISOString().split('T')[0];
                activity.set(date, (activity.get(date) || 0) + 1);
              }
            });
          } catch (_error) {
            // Continue with other repos
          }
        }

        setActivityData(activity);
      } catch (_error) {
        // Silently fail
      } finally {
        setLoadingActivity(false);
      }
    };

    if (!loading && stats.repositories.total > 0) {
      loadActivity();
    }
  }, [loading, stats.repositories.total]);

  // Generate weekly activity data (last 12 weeks)
  const generateWeeklyActivity = (): WeeklyActivity[] => {
    const weeks: WeeklyActivity[] = [];
    const today = new Date();

    for (let w = 11; w >= 0; w--) {
      const weekStart = new Date(today);
      weekStart.setDate(today.getDate() - (w * 7 + today.getDay()));

      let weekCount = 0;
      for (let d = 0; d < 7; d++) {
        const date = new Date(weekStart);
        date.setDate(weekStart.getDate() + d);
        const dateStr = date.toISOString().split('T')[0];
        weekCount += activityData.get(dateStr) || 0;
      }

      const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      weeks.push({
        weekStart: weekStart.toISOString().split('T')[0],
        weekLabel: `${monthNames[weekStart.getMonth()]} ${weekStart.getDate()}`,
        count: weekCount
      });
    }
    return weeks;
  };

  const getActivityBarHeight = (count: number, maxCount: number): string => {
    if (count === 0 || maxCount === 0) return 'h-1';
    const percentage = (count / maxCount) * 100;
    if (percentage <= 20) return 'h-4';
    if (percentage <= 40) return 'h-8';
    if (percentage <= 60) return 'h-12';
    if (percentage <= 80) return 'h-16';
    return 'h-20';
  };

  const quickLinks: QuickLink[] = [
    {
      id: 'git-providers',
      name: 'Git Providers',
      description: 'Configure GitHub, GitLab, Gitea connections',
      href: '/app/devops/source-control',
      icon: GitBranch,
      stat: stats.providers.total,
      status: stats.providers.active > 0 ? 'success' : 'neutral'
    },
    {
      id: 'repositories',
      name: 'Repositories',
      description: 'Synced repositories from all providers',
      href: '/app/devops/source-control/repositories',
      icon: FolderGit2,
      stat: stats.repositories.total,
      status: stats.repositories.total > 0 ? 'success' : 'neutral'
    },
    {
      id: 'runners',
      name: 'DevOps Runners',
      description: 'Self-hosted workflow execution agents',
      href: '/app/devops/ci-cd/runners',
      icon: Server,
      stat: stats.runners?.total || 0,
      status: stats.runners?.online ? (stats.runners.online > 0 ? 'success' : 'warning') : 'neutral'
    },
    {
      id: 'webhooks',
      name: 'Webhooks',
      description: 'Webhook endpoints and delivery monitoring',
      href: '/app/devops/connections/webhooks',
      icon: Link2,
      stat: stats.webhooks?.total_endpoints || 0,
      status: stats.webhooks?.failed_deliveries_today ? (stats.webhooks.failed_deliveries_today > 0 ? 'warning' : 'success') : 'neutral'
    },
    {
      id: 'integrations',
      name: 'Integrations',
      description: 'Third-party service integrations',
      href: '/app/devops/connections',
      icon: Puzzle,
      stat: stats.integrations.total,
      status: stats.integrations.errors > 0 ? 'error' : (stats.integrations.active > 0 ? 'success' : 'neutral')
    },
    {
      id: 'api-keys',
      name: 'API Keys',
      description: 'Authentication tokens and access keys',
      href: '/app/devops/connections/api-keys',
      icon: Key,
      stat: stats.apiKeys?.total_keys || 0,
      status: stats.apiKeys?.active_keys ? (stats.apiKeys.active_keys > 0 ? 'success' : 'neutral') : 'neutral'
    }
  ];

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

  if (loading) {
    return (
      <PageContainer
        title="DevOps Overview"
        description="Infrastructure and development operations"
        breadcrumbs={breadcrumbs}
      >
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
          <span className="ml-3 text-theme-secondary">Loading DevOps dashboard...</span>
        </div>
      </PageContainer>
    );
  }

  const totalRunners = stats.runners?.total || 0;

  return (
    <PageContainer
      title="DevOps Overview"
      description="Infrastructure, pipelines, and development operations dashboard"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Key Metrics */}
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
          <StatCard
            title="Git Providers"
            value={stats.providers.active}
            subtitle={`${stats.providers.total} configured`}
            icon={GitBranch}
            status={stats.providers.active > 0 ? 'success' : 'neutral'}
            onClick={() => navigate('/app/devops/source-control')}
          />
          <StatCard
            title="Repositories"
            value={stats.repositories.total}
            subtitle={`${stats.repositories.withWebhooks} with webhooks`}
            icon={FolderGit2}
            status={stats.repositories.total > 0 ? 'success' : 'neutral'}
            onClick={() => navigate('/app/devops/source-control/repositories')}
          />
          <StatCard
            title="Runners Online"
            value={stats.runners?.online || 0}
            subtitle={`${totalRunners} total`}
            icon={Server}
            status={stats.runners?.online ? (stats.runners.online > 0 ? 'success' : 'warning') : 'neutral'}
            onClick={() => navigate('/app/devops/ci-cd/runners')}
          />
          <StatCard
            title="Webhooks Active"
            value={stats.webhooks?.active_endpoints || 0}
            subtitle={`${stats.webhooks?.total_endpoints || 0} total`}
            icon={Link2}
            status={stats.webhooks?.active_endpoints ? 'success' : 'neutral'}
            onClick={() => navigate('/app/devops/connections/webhooks')}
          />
          <StatCard
            title="Integrations"
            value={stats.integrations.active}
            subtitle={stats.integrations.errors > 0 ? `${stats.integrations.errors} errors` : `${stats.integrations.total} total`}
            icon={Puzzle}
            status={stats.integrations.errors > 0 ? 'error' : (stats.integrations.active > 0 ? 'success' : 'neutral')}
            onClick={() => navigate('/app/devops/connections')}
          />
          <StatCard
            title="API Keys"
            value={stats.apiKeys?.active_keys || 0}
            subtitle={`${stats.apiKeys?.requests_today || 0} requests today`}
            icon={Key}
            status={stats.apiKeys?.active_keys ? 'success' : 'neutral'}
            onClick={() => navigate('/app/devops/connections/api-keys')}
          />
        </div>

        {/* Status Overview */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Runner Health */}
          <div className="bg-theme-surface border border-theme rounded-lg p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <Activity className="w-5 h-5" />
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
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <StatusIndicator label="Online" value={stats.runners.online} total={totalRunners} type="success" />
                    <StatusIndicator label="Busy" value={stats.runners.busy} total={totalRunners} type="warning" />
                    <StatusIndicator label="Offline" value={stats.runners.offline} total={totalRunners} type="error" />
                  </div>
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

          {/* Webhook Deliveries */}
          <div className="bg-theme-surface border border-theme rounded-lg p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <Zap className="w-5 h-5" />
                Webhook Deliveries Today
              </h3>
              <button
                onClick={() => navigate('/app/devops/connections/webhooks')}
                className="text-sm text-theme-primary hover:underline"
              >
                View all
              </button>
            </div>
            {stats.webhooks && stats.webhooks.total_deliveries_today > 0 ? (
              <div className="space-y-3">
                <div className="grid grid-cols-3 gap-4 text-center">
                  <div>
                    <p className="text-2xl font-bold text-theme-primary">{stats.webhooks.total_deliveries_today}</p>
                    <p className="text-xs text-theme-tertiary">Total</p>
                  </div>
                  <div>
                    <p className="text-2xl font-bold text-theme-success">{stats.webhooks.successful_deliveries_today}</p>
                    <p className="text-xs text-theme-tertiary">Successful</p>
                  </div>
                  <div>
                    <p className="text-2xl font-bold text-theme-error">{stats.webhooks.failed_deliveries_today}</p>
                    <p className="text-xs text-theme-tertiary">Failed</p>
                  </div>
                </div>
                {stats.webhooks.failed_deliveries_today > 0 && (
                  <div className="flex items-center gap-2 p-2 bg-theme-error/10 rounded text-sm text-theme-error">
                    <AlertTriangle className="w-4 h-4" />
                    <span>{stats.webhooks.failed_deliveries_today} failed deliveries require attention</span>
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

          {/* Commit Activity */}
          <div className="bg-theme-surface border border-theme rounded-lg p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <GitCommit className="w-5 h-5" />
                Commit Activity
              </h3>
              <button
                onClick={() => navigate('/app/devops/source-control/repositories')}
                className="text-sm text-theme-primary hover:underline"
              >
                View repos
              </button>
            </div>
            {loadingActivity ? (
              <div className="flex items-center justify-center py-8">
                <LoadingSpinner size="sm" />
              </div>
            ) : stats.repositories.total > 0 ? (
              (() => {
                const weeklyData = generateWeeklyActivity();
                const maxCount = Math.max(...weeklyData.map(w => w.count), 1);
                const totalCommits = weeklyData.reduce((sum, w) => sum + w.count, 0);

                return (
                  <div className="space-y-3">
                    {/* Bar Chart */}
                    <div className="flex items-end justify-between gap-1 h-24">
                      {weeklyData.map((week, idx) => (
                        <div
                          key={idx}
                          className="flex-1 flex flex-col items-center justify-end h-full group"
                        >
                          <div
                            className={`w-full rounded-t-sm bg-theme-success-solid transition-all group-hover:opacity-80 cursor-default ${getActivityBarHeight(week.count, maxCount)}`}
                            title={`Week of ${week.weekLabel}: ${week.count} commit${week.count !== 1 ? 's' : ''}`}
                          />
                        </div>
                      ))}
                    </div>
                    {/* X-axis labels */}
                    <div className="flex justify-between text-[10px] text-theme-tertiary">
                      {weeklyData.filter((_, i) => i % 3 === 0).map((week, idx) => (
                        <span key={idx}>{week.weekLabel}</span>
                      ))}
                    </div>
                    {/* Summary */}
                    <div className="flex items-center justify-between pt-2 border-t border-theme text-xs text-theme-tertiary">
                      <span>{totalCommits} commits</span>
                      <span>Last 12 weeks</span>
                    </div>
                  </div>
                );
              })()
            ) : (
              <div className="text-center py-4">
                <FolderGit2 className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
                <p className="text-sm text-theme-secondary">No repositories synced</p>
                <button
                  onClick={() => navigate('/app/devops/source-control')}
                  className="text-sm text-theme-primary hover:underline mt-1"
                >
                  Add provider
                </button>
              </div>
            )}
          </div>
        </div>

        {/* Quick Links */}
        <div>
          <h3 className="font-semibold text-theme-primary mb-4">Quick Access</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {quickLinks.map((link) => (
              <QuickLinkCard
                key={link.id}
                {...link}
                onClick={() => navigate(link.href)}
              />
            ))}
          </div>
        </div>

        {/* Recent Activity / Alerts */}
        {(stats.integrations.errors > 0 || (stats.runners && stats.runners.offline > 0)) && (
          <div className="bg-theme-warning/10 border border-theme-warning/30 rounded-lg p-4">
            <h3 className="font-semibold text-theme-warning flex items-center gap-2 mb-3">
              <AlertTriangle className="w-5 h-5" />
              Attention Required
            </h3>
            <div className="space-y-2">
              {stats.integrations.errors > 0 && (
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-secondary">
                    {stats.integrations.errors} integration{stats.integrations.errors > 1 ? 's' : ''} with errors
                  </span>
                  <button
                    onClick={() => navigate('/app/devops/connections')}
                    className="text-theme-primary hover:underline"
                  >
                    Review
                  </button>
                </div>
              )}
              {stats.runners && stats.runners.offline > 0 && (
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
              )}
            </div>
          </div>
        )}
      </div>
    </PageContainer>
  );
}

export default DevOpsOverviewPage;
