import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  Link2, Brain, GitBranch, Puzzle, Key,
  CheckCircle, AlertTriangle, XCircle, ArrowRight,
  Plus, Settings, Loader2
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { providersApi } from '@/shared/services/ai/ProvidersApiService';
import { gitProvidersApi } from '@/features/devops/git/services/gitProvidersApi';
import { integrationsApi } from '@/features/devops/integrations/services/integrationsApi';

interface ConnectionCategory {
  id: string;
  name: string;
  description: string;
  icon: React.ReactNode;
  href: string;
  count: number;
  activeCount: number;
  errorCount: number;
}

interface RecentConnection {
  id: string;
  name: string;
  type: 'ai' | 'git' | 'integration';
  status: 'connected' | 'error' | 'warning';
  lastUsed: string;
}

export function ConnectionsOverview() {
  const navigate = useNavigate();
  const [categories, setCategories] = useState<ConnectionCategory[]>([
    {
      id: 'ai',
      name: 'AI Services',
      description: 'OpenAI, Anthropic, and other AI providers',
      icon: <Brain className="w-6 h-6" />,
      href: '/app/connections/ai',
      count: 0,
      activeCount: 0,
      errorCount: 0
    },
    {
      id: 'git',
      name: 'Git Providers',
      description: 'GitHub, GitLab, Gitea, and other git providers',
      icon: <GitBranch className="w-6 h-6" />,
      href: '/app/connections/git',
      count: 0,
      activeCount: 0,
      errorCount: 0
    },
    {
      id: 'integrations',
      name: 'Integrations',
      description: 'Third-party service integrations',
      icon: <Puzzle className="w-6 h-6" />,
      href: '/app/connections/integrations',
      count: 0,
      activeCount: 0,
      errorCount: 0
    },
    {
      id: 'credentials',
      name: 'Credentials',
      description: 'API keys and authentication tokens',
      icon: <Key className="w-6 h-6" />,
      href: '/app/connections/credentials',
      count: 0,
      activeCount: 0,
      errorCount: 0
    }
  ]);
  const [recentConnections, setRecentConnections] = useState<RecentConnection[]>([]);
  const [loading, setLoading] = useState(true);

  const pageActions: PageAction[] = [
    {
      id: 'add-connection',
      label: 'Add Connection',
      onClick: () => navigate('/app/connections/integrations/marketplace'),
      variant: 'primary',
      icon: Plus
    }
  ];

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);

        // Fetch stats from all services in parallel
        const [aiStats, gitProviders, integrationsResponse] = await Promise.all([
          providersApi.getStatistics().catch(() => ({ total_providers: 0, active_providers: 0, inactive_providers: 0, total_credentials: 0 })),
          gitProvidersApi.getProviders().catch(() => []),
          integrationsApi.getInstances().catch(() => ({ success: false, data: { instances: [] } }))
        ]);

        // Calculate git provider stats - GitProvider type uses is_active boolean
        const gitActive = gitProviders.filter((p) => p.is_active).length;
        const gitError = gitProviders.filter((p) => !p.is_active).length;

        // Calculate integration stats
        const instances = integrationsResponse.success && integrationsResponse.data?.instances ? integrationsResponse.data.instances : [];
        const intActive = instances.filter((i: { status?: string }) => i.status === 'active').length;
        const intError = instances.filter((i: { status?: string }) => i.status === 'error').length;

        // Update categories with real data
        setCategories(prev => prev.map(cat => {
          switch (cat.id) {
            case 'ai':
              return {
                ...cat,
                count: aiStats.total_providers || 0,
                activeCount: aiStats.active_providers || 0,
                errorCount: aiStats.inactive_providers || 0
              };
            case 'git':
              return {
                ...cat,
                count: gitProviders.length,
                activeCount: gitActive,
                errorCount: gitError
              };
            case 'integrations':
              return {
                ...cat,
                count: instances.length,
                activeCount: intActive,
                errorCount: intError
              };
            case 'credentials':
              return {
                ...cat,
                count: aiStats.total_credentials || 0,
                activeCount: aiStats.total_credentials || 0,
                errorCount: 0
              };
            default:
              return cat;
          }
        }));

        // Build recent connections from all sources
        const recent: RecentConnection[] = [];

        // Add git providers - GitProvider type uses is_active and created_at
        gitProviders.slice(0, 3).forEach((p) => {
          recent.push({
            id: p.id,
            name: p.name,
            type: 'git',
            status: p.is_active ? 'connected' : 'warning',
            lastUsed: formatTimeAgo(p.created_at)
          });
        });

        // Add integrations
        instances.slice(0, 3).forEach((i: { id: string; name: string; status?: string; last_executed_at?: string }) => {
          recent.push({
            id: i.id,
            name: i.name,
            type: 'integration',
            status: i.status === 'active' ? 'connected' : i.status === 'error' ? 'error' : 'warning',
            lastUsed: formatTimeAgo(i.last_executed_at)
          });
        });

        setRecentConnections(recent.slice(0, 5));
      } catch (error) {
        // Keep default empty state on error
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, []);

  const formatTimeAgo = (dateStr?: string): string => {
    if (!dateStr) return 'Never';
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

  const totalConnections = categories.reduce((sum, cat) => sum + cat.count, 0);
  const totalActive = categories.reduce((sum, cat) => sum + cat.activeCount, 0);
  const totalErrors = categories.reduce((sum, cat) => sum + cat.errorCount, 0);

  if (loading) {
    return (
      <PageContainer
        title="Connections"
        description="Manage all your connected services and providers"
        actions={pageActions}
      >
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  const getStatusIcon = (status: RecentConnection['status']) => {
    switch (status) {
      case 'connected':
        return <CheckCircle className="w-4 h-4 text-theme-success" />;
      case 'error':
        return <XCircle className="w-4 h-4 text-theme-danger" />;
      case 'warning':
        return <AlertTriangle className="w-4 h-4 text-theme-warning" />;
    }
  };

  const getTypeIcon = (type: RecentConnection['type']) => {
    switch (type) {
      case 'ai':
        return <Brain className="w-4 h-4 text-theme-interactive-primary" />;
      case 'git':
        return <GitBranch className="w-4 h-4 text-theme-info" />;
      case 'integration':
        return <Puzzle className="w-4 h-4 text-theme-success" />;
    }
  };

  const getTypeHref = (type: RecentConnection['type']) => {
    switch (type) {
      case 'ai':
        return '/app/connections/ai';
      case 'git':
        return '/app/connections/git';
      case 'integration':
        return '/app/connections/integrations';
    }
  };

  return (
    <PageContainer
      title="Connections"
      description="Manage all your connected services and providers"
      actions={pageActions}
    >
      {/* Summary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-bg-subtle rounded-lg">
              <Link2 className="w-5 h-5 text-theme-primary" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Total Connections</p>
              <p className="text-2xl font-semibold text-theme-primary">{totalConnections}</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-success/10 rounded-lg">
              <CheckCircle className="w-5 h-5 text-theme-success" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Active</p>
              <p className="text-2xl font-semibold text-theme-primary">{totalActive}</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${totalErrors > 0 ? 'bg-theme-danger/10' : 'bg-theme-bg-subtle'}`}>
              <AlertTriangle className={`w-5 h-5 ${totalErrors > 0 ? 'text-theme-danger' : 'text-theme-secondary'}`} />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Errors</p>
              <p className="text-2xl font-semibold text-theme-primary">{totalErrors}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Categories Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
        {categories.map((category) => (
          <Link
            key={category.id}
            to={category.href}
            className="bg-theme-surface border border-theme rounded-lg p-5 hover:border-theme-primary transition-colors group"
          >
            <div className="flex items-start justify-between">
              <div className="flex items-center gap-4">
                <div className="p-3 bg-theme-bg-subtle rounded-lg text-theme-primary group-hover:bg-theme-primary group-hover:text-white transition-colors">
                  {category.icon}
                </div>
                <div>
                  <h3 className="font-semibold text-theme-primary">{category.name}</h3>
                  <p className="text-sm text-theme-secondary mt-1">{category.description}</p>
                </div>
              </div>
              <ArrowRight className="w-5 h-5 text-theme-secondary group-hover:text-theme-primary transition-colors" />
            </div>

            <div className="flex items-center gap-4 mt-4 pt-4 border-t border-theme">
              <div className="flex items-center gap-1">
                <span className="text-lg font-semibold text-theme-primary">{category.count}</span>
                <span className="text-sm text-theme-secondary">total</span>
              </div>
              <div className="flex items-center gap-1">
                <CheckCircle className="w-4 h-4 text-theme-success" />
                <span className="text-sm text-theme-secondary">{category.activeCount} active</span>
              </div>
              {category.errorCount > 0 && (
                <div className="flex items-center gap-1">
                  <AlertTriangle className="w-4 h-4 text-theme-danger" />
                  <span className="text-sm text-theme-danger">{category.errorCount} error</span>
                </div>
              )}
            </div>
          </Link>
        ))}
      </div>

      {/* Recent Activity */}
      <div className="bg-theme-surface border border-theme rounded-lg">
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <h2 className="font-semibold text-theme-primary">Recent Activity</h2>
          <Link
            to="/app/system/audit-logs?filter=connections"
            className="text-sm text-theme-primary hover:underline"
          >
            View all activity
          </Link>
        </div>

        <div className="divide-y divide-theme">
          {recentConnections.length === 0 ? (
            <div className="p-8 text-center">
              <Link2 className="w-12 h-12 mx-auto mb-3 text-theme-secondary opacity-50" />
              <p className="text-theme-secondary">No recent activity</p>
              <p className="text-sm text-theme-tertiary mt-1">
                Connect your first service to see activity here
              </p>
            </div>
          ) : (
            recentConnections.map((connection) => (
            <Link
              key={connection.id}
              to={`${getTypeHref(connection.type)}/${connection.id}`}
              className="flex items-center justify-between p-4 hover:bg-theme-bg-subtle transition-colors"
            >
              <div className="flex items-center gap-3">
                {getStatusIcon(connection.status)}
                <div>
                  <div className="flex items-center gap-2">
                    {getTypeIcon(connection.type)}
                    <span className="font-medium text-theme-primary">{connection.name}</span>
                  </div>
                  <p className="text-sm text-theme-secondary">
                    Last used {connection.lastUsed}
                  </p>
                </div>
              </div>
              <button
                onClick={(e) => {
                  e.preventDefault();
                  // Open settings
                }}
                className="p-2 hover:bg-theme-bg-subtle rounded-lg"
              >
                <Settings className="w-4 h-4 text-theme-secondary" />
              </button>
            </Link>
            ))
          )}
        </div>
      </div>
    </PageContainer>
  );
}

export default ConnectionsOverview;
