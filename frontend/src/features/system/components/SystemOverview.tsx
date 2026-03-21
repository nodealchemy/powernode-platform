import { useState, useEffect, useCallback, useImperativeHandle, forwardRef } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Server, Package, FileText, Settings, Activity, Boxes,
  Play, CheckCircle, XCircle, Clock,
  RefreshCw, ArrowRight, Layers, Globe
} from 'lucide-react';
import { Card, MetricCard } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { systemApi } from '../services/systemApi';
import type { SystemOverviewStats, SystemRecentActivity } from '../types/system.types';

export interface SystemOverviewHandle {
  refresh: () => Promise<void>;
}

interface SystemOverviewProps {
  className?: string;
}

export const SystemOverview = forwardRef<SystemOverviewHandle, SystemOverviewProps>(
  ({ className = '' }, ref) => {
    const navigate = useNavigate();
    const [stats, setStats] = useState<SystemOverviewStats | null>(null);
    const [recentActivity, setRecentActivity] = useState<SystemRecentActivity[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    const loadData = useCallback(async () => {
      try {
        setLoading(true);
        setError(null);
        const [statsData, activityData] = await Promise.all([
          systemApi.getOverviewStats(),
          systemApi.getRecentActivity(5),
        ]);
        setStats(statsData);
        setRecentActivity(activityData);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load system data');
      } finally {
        setLoading(false);
      }
    }, []);

    useEffect(() => {
      loadData();
    }, [loadData]);

    useImperativeHandle(ref, () => ({
      refresh: loadData,
    }));

    const getStatusColor = (status: string) => {
      switch (status) {
        case 'complete':
        case 'running':
          return 'text-theme-success';
        case 'failed':
        case 'aborted':
          return 'text-theme-error';
        case 'pending':
        case 'scheduled':
          return 'text-theme-warning';
        default:
          return 'text-theme-secondary';
      }
    };

    const getStatusIcon = (status: string) => {
      switch (status) {
        case 'complete':
          return <CheckCircle className="w-4 h-4" />;
        case 'running':
          return <Play className="w-4 h-4" />;
        case 'failed':
        case 'aborted':
          return <XCircle className="w-4 h-4" />;
        default:
          return <Clock className="w-4 h-4" />;
      }
    };

    if (loading) {
      return (
        <div className={`space-y-6 ${className}`}>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {[...Array(8)].map((_, i) => (
              <Card key={i} variant="elevated" padding="lg">
                <div className="animate-pulse space-y-3">
                  <div className="h-4 bg-theme-surface rounded w-1/2" />
                  <div className="h-8 bg-theme-surface rounded w-3/4" />
                  <div className="h-3 bg-theme-surface rounded w-2/3" />
                </div>
              </Card>
            ))}
          </div>
        </div>
      );
    }

    if (error) {
      return (
        <div className={`${className}`}>
          <Card variant="outlined" padding="lg">
            <div className="text-center py-8">
              <XCircle className="w-12 h-12 text-theme-error mx-auto mb-4" />
              <h3 className="text-lg font-semibold text-theme-primary mb-2">Failed to Load System Data</h3>
              <p className="text-theme-secondary mb-4">{error}</p>
              <Button onClick={loadData} variant="primary">
                <RefreshCw className="w-4 h-4 mr-2" />
                Retry
              </Button>
            </div>
          </Card>
        </div>
      );
    }

    if (!stats) return null;

    return (
      <div className={`space-y-6 ${className}`}>
        {/* Primary Metrics */}
        <div>
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Infrastructure Overview</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <MetricCard
              title="Nodes"
              value={stats.nodes.total}
              icon={<Server className="w-5 h-5" />}
              description={`${stats.nodes.enabled} enabled, ${stats.nodes.disabled} disabled`}
              onClick={() => navigate('/app/system/nodes')}
            />
            <MetricCard
              title="Templates"
              value={stats.templates.total}
              icon={<FileText className="w-5 h-5" />}
              description={`${stats.templates.public} public, ${stats.templates.private} private`}
              onClick={() => navigate('/app/system/templates')}
            />
            <MetricCard
              title="Providers"
              value={stats.providers.total}
              icon={<Globe className="w-5 h-5" />}
              description={`${stats.providers.enabled} enabled`}
              onClick={() => navigate('/app/system/providers')}
            />
            <MetricCard
              title="Modules"
              value={stats.modules.total}
              icon={<Package className="w-5 h-5" />}
              description={`${stats.modules.enabled} enabled`}
              onClick={() => navigate('/app/system/modules')}
            />
          </div>
        </div>

        {/* Secondary Metrics */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <MetricCard
            title="Platforms"
            value={stats.platforms.total}
            icon={<Layers className="w-5 h-5" />}
            description={`${stats.platforms.enabled} enabled`}
            onClick={() => navigate('/app/system/platforms')}
          />
          <MetricCard
            title="Regions"
            value={stats.regions.total}
            icon={<Globe className="w-5 h-5" />}
            description="Provider regions"
          />
          <MetricCard
            title="Puppet Modules"
            value={stats.puppet.modules}
            icon={<Boxes className="w-5 h-5" />}
            description={`${stats.puppet.resources} resources`}
            onClick={() => navigate('/app/system/puppet')}
          />
          <MetricCard
            title="Operations"
            value={stats.operations.total}
            icon={<Activity className="w-5 h-5" />}
            description={`${stats.operations.running} running`}
            onClick={() => navigate('/app/system/operations')}
          />
        </div>

        {/* Operations Status & Module Distribution */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Operations Status */}
          <Card variant="elevated" padding="lg">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-theme-primary">Operations Status</h3>
              <Button variant="outline" size="sm" onClick={() => navigate('/app/system/operations')}>
                View All <ArrowRight className="w-4 h-4 ml-1" />
              </Button>
            </div>
            <div className="space-y-4">
              <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-warning/10 rounded-lg flex items-center justify-center">
                    <Clock className="w-5 h-5 text-theme-warning" />
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">Pending</p>
                    <p className="text-sm text-theme-secondary">Waiting to start</p>
                  </div>
                </div>
                <span className="text-2xl font-bold text-theme-warning">{stats.operations.pending}</span>
              </div>
              <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-info/10 rounded-lg flex items-center justify-center">
                    <Play className="w-5 h-5 text-theme-info" />
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">Running</p>
                    <p className="text-sm text-theme-secondary">Currently executing</p>
                  </div>
                </div>
                <span className="text-2xl font-bold text-theme-info">{stats.operations.running}</span>
              </div>
              <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-success/10 rounded-lg flex items-center justify-center">
                    <CheckCircle className="w-5 h-5 text-theme-success" />
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">Completed</p>
                    <p className="text-sm text-theme-secondary">Successfully finished</p>
                  </div>
                </div>
                <span className="text-2xl font-bold text-theme-success">{stats.operations.completed}</span>
              </div>
              <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-error/10 rounded-lg flex items-center justify-center">
                    <XCircle className="w-5 h-5 text-theme-error" />
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">Failed</p>
                    <p className="text-sm text-theme-secondary">Errors encountered</p>
                  </div>
                </div>
                <span className="text-2xl font-bold text-theme-error">{stats.operations.failed}</span>
              </div>
            </div>
          </Card>

          {/* Module Distribution */}
          <Card variant="elevated" padding="lg">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-theme-primary">Module Distribution</h3>
              <Button variant="outline" size="sm" onClick={() => navigate('/app/system/modules')}>
                Manage <ArrowRight className="w-4 h-4 ml-1" />
              </Button>
            </div>
            <div className="space-y-4">
              <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-interactive-primary/10 rounded-lg flex items-center justify-center">
                    <Settings className="w-5 h-5 text-theme-interactive-primary" />
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">Config Modules</p>
                    <p className="text-sm text-theme-secondary">Configuration management</p>
                  </div>
                </div>
                <span className="text-2xl font-bold text-theme-interactive-primary">{stats.modules.by_variety.config}</span>
              </div>
              <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-success/10 rounded-lg flex items-center justify-center">
                    <Server className="w-5 h-5 text-theme-success" />
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">Instance Modules</p>
                    <p className="text-sm text-theme-secondary">Instance-specific</p>
                  </div>
                </div>
                <span className="text-2xl font-bold text-theme-success">{stats.modules.by_variety.instance}</span>
              </div>
              <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-warning/10 rounded-lg flex items-center justify-center">
                    <Package className="w-5 h-5 text-theme-warning" />
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">Subscription Modules</p>
                    <p className="text-sm text-theme-secondary">Subscription-based</p>
                  </div>
                </div>
                <span className="text-2xl font-bold text-theme-warning">{stats.modules.by_variety.subscription}</span>
              </div>
              <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-info/10 rounded-lg flex items-center justify-center">
                    <Boxes className="w-5 h-5 text-theme-info" />
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">Puppet Assignments</p>
                    <p className="text-sm text-theme-secondary">Module ↔ Puppet links</p>
                  </div>
                </div>
                <span className="text-2xl font-bold text-theme-info">{stats.puppet.assignments}</span>
              </div>
            </div>
          </Card>
        </div>

        {/* Quick Actions & Recent Activity */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Quick Actions */}
          <Card variant="elevated" padding="lg">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Quick Actions</h3>
            <div className="grid grid-cols-2 gap-3">
              <Button
                variant="outline"
                className="flex flex-col items-center justify-center p-4 h-auto"
                onClick={() => navigate('/app/system/nodes')}
              >
                <Server className="w-6 h-6 mb-2 text-theme-interactive-primary" />
                <span className="text-sm font-medium">Manage Nodes</span>
              </Button>
              <Button
                variant="outline"
                className="flex flex-col items-center justify-center p-4 h-auto"
                onClick={() => navigate('/app/system/templates')}
              >
                <FileText className="w-6 h-6 mb-2 text-theme-interactive-primary" />
                <span className="text-sm font-medium">Templates</span>
              </Button>
              <Button
                variant="outline"
                className="flex flex-col items-center justify-center p-4 h-auto"
                onClick={() => navigate('/app/system/providers')}
              >
                <Globe className="w-6 h-6 mb-2 text-theme-interactive-primary" />
                <span className="text-sm font-medium">Providers</span>
              </Button>
              <Button
                variant="outline"
                className="flex flex-col items-center justify-center p-4 h-auto"
                onClick={() => navigate('/app/system/modules')}
              >
                <Package className="w-6 h-6 mb-2 text-theme-interactive-primary" />
                <span className="text-sm font-medium">Modules</span>
              </Button>
              <Button
                variant="outline"
                className="flex flex-col items-center justify-center p-4 h-auto"
                onClick={() => navigate('/app/system/puppet')}
              >
                <Boxes className="w-6 h-6 mb-2 text-theme-interactive-primary" />
                <span className="text-sm font-medium">Puppet</span>
              </Button>
              <Button
                variant="outline"
                className="flex flex-col items-center justify-center p-4 h-auto"
                onClick={() => navigate('/app/system/operations')}
              >
                <Activity className="w-6 h-6 mb-2 text-theme-interactive-primary" />
                <span className="text-sm font-medium">Operations</span>
              </Button>
            </div>
          </Card>

          {/* Recent Activity */}
          <Card variant="elevated" padding="lg">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-theme-primary">Recent Activity</h3>
              <Button variant="outline" size="sm" onClick={() => navigate('/app/system/operations')}>
                View All <ArrowRight className="w-4 h-4 ml-1" />
              </Button>
            </div>
            {recentActivity.length === 0 ? (
              <div className="text-center py-8">
                <Activity className="w-12 h-12 text-theme-tertiary mx-auto mb-3" />
                <p className="text-theme-secondary">No recent activity</p>
              </div>
            ) : (
              <div className="space-y-3">
                {recentActivity.map((activity) => (
                  <div
                    key={activity.id}
                    className="flex items-start gap-3 p-3 bg-theme-surface rounded-lg hover:bg-theme-surface-hover transition-colors cursor-pointer"
                    onClick={() => navigate('/app/system/operations')}
                  >
                    <div className={`mt-0.5 ${getStatusColor(activity.status || '')}`}>
                      {getStatusIcon(activity.status || '')}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-theme-primary truncate">{activity.action}</p>
                      <p className="text-sm text-theme-secondary truncate">{activity.description}</p>
                      <p className="text-xs text-theme-tertiary mt-1">
                        {new Date(activity.timestamp).toLocaleString()}
                        {activity.initiated_by && ` by ${activity.initiated_by}`}
                      </p>
                    </div>
                    {activity.status && (
                      <span className={`text-xs font-medium px-2 py-1 rounded-full ${
                        activity.status === 'complete' ? 'bg-theme-success/10 text-theme-success' :
                        activity.status === 'running' ? 'bg-theme-info/10 text-theme-info' :
                        activity.status === 'failed' ? 'bg-theme-error/10 text-theme-error' :
                        'bg-theme-warning/10 text-theme-warning'
                      }`}>
                        {activity.status}
                      </span>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>

        {/* Provider Types */}
        {stats.providers.types.length > 0 && (
          <Card variant="elevated" padding="lg">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Configured Provider Types</h3>
            <div className="flex flex-wrap gap-2">
              {stats.providers.types.map((type) => (
                <span
                  key={type}
                  className="px-3 py-1.5 bg-theme-interactive-primary/10 text-theme-interactive-primary rounded-full text-sm font-medium"
                >
                  {type}
                </span>
              ))}
            </div>
          </Card>
        )}
      </div>
    );
  }
);

SystemOverview.displayName = 'SystemOverview';
