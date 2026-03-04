import React from 'react';
import {
  Activity,
  AlertTriangle,
  CheckCircle,
  Clock,
  Database,
  HardDrive,
  RefreshCw,
  Server,
  Users,
  Workflow,
  XCircle
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Loading } from '@/shared/components/ui/Loading';
import { HealthStatus } from '@/shared/services/ai/MonitoringApiService';

interface SystemHealthDashboardProps {
  healthData: HealthStatus | null;
  isLoading: boolean;
  onRefresh: () => void;
}

export const SystemHealthDashboard: React.FC<SystemHealthDashboardProps> = ({
  healthData,
  isLoading,
  onRefresh
}) => {
  const getHealthStatusBadge = (status: string) => {
    switch (status) {
      case 'healthy':
        return 'success';
      case 'degraded':
        return 'warning';
      case 'unhealthy':
      case 'critical':
        return 'danger';
      default:
        return 'outline';
    }
  };

  const getHealthScoreColor = (score: number) => {
    if (score >= 80) return 'text-theme-success';
    if (score >= 50) return 'text-theme-warning';
    return 'text-theme-error';
  };

  const getDatabaseAvailability = (): number => {
    const pool = healthData?.database?.connection_pool;
    if (!pool || pool.size === 0) return 100;
    return (pool.available / pool.size) * 100;
  };

  const getWorkerThroughput = (): number => {
    const workers = healthData?.workers;
    if (!workers || workers.recent_starts === 0) return 100;
    return Math.min(100, (workers.recent_completions / workers.recent_starts) * 100);
  };

  const getComponentStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircle className="h-4 w-4 text-theme-success" />;
      case 'degraded':
        return <AlertTriangle className="h-4 w-4 text-theme-warning" />;
      case 'unhealthy':
      case 'critical':
        return <XCircle className="h-4 w-4 text-theme-error" />;
      default:
        return <Clock className="h-4 w-4 text-theme-muted" />;
    }
  };

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffSec = Math.floor(diffMs / 1000);

    if (diffSec < 60) return `${diffSec}s ago`;
    if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
    return date.toLocaleTimeString();
  };

  if (isLoading && !healthData) {
    return (
      <Card>
        <CardHeader
          title="System Health"
          icon={<Activity className="h-5 w-5" />}
        />
        <CardContent className="flex items-center justify-center py-8">
          <Loading size="lg" message="Loading system health..." />
        </CardContent>
      </Card>
    );
  }

  if (!healthData) {
    return (
      <Card>
        <CardHeader
          title="System Health"
          icon={<Activity className="h-5 w-5" />}
        />
        <CardContent className="py-8 text-center">
          <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
          <p className="text-theme-muted">No health data available</p>
          <Button onClick={onRefresh} variant="outline" size="sm" className="mt-4">
            <RefreshCw className="h-4 w-4 mr-2" />
            Load Health Data
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader
        title="System Health"
        icon={<Activity className="h-5 w-5" />}
        action={
          <Button
            onClick={onRefresh}
            variant="ghost"
            size="sm"
            disabled={isLoading}
          >
            <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
          </Button>
        }
      />
      <CardContent className="space-y-6">
        {/* Overall Health Score - using native health_score */}
        <div className="text-center">
          <div className={`text-3xl font-bold ${getHealthScoreColor(healthData.health_score)}`}>
            {healthData.health_score.toFixed(1)}%
          </div>
          <Badge variant={getHealthStatusBadge(healthData.status)} className="mt-2">
            {healthData.status.charAt(0).toUpperCase() + healthData.status.slice(1)}
          </Badge>
          <p className="text-sm text-theme-muted mt-1">
            Updated {formatTimestamp(healthData.timestamp)}
          </p>
        </div>

        {/* Component Health Status - using native data structure */}
        <div className="space-y-3">
          <h4 className="text-sm font-medium text-theme-primary">Component Status</h4>

          <div className="grid grid-cols-1 gap-3">
            {/* AI Providers - from native providers object */}
            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(
                  healthData.providers.healthy_providers === healthData.providers.total_providers
                    ? 'healthy' : 'degraded'
                )}
                <div>
                  <p className="text-sm font-medium text-theme-primary">AI Providers</p>
                  <p className="text-xs text-theme-muted">
                    {healthData.providers.healthy_providers} / {healthData.providers.total_providers} healthy
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className={`text-sm font-medium ${getHealthScoreColor(
                  healthData.providers.total_providers > 0
                    ? (healthData.providers.healthy_providers / healthData.providers.total_providers) * 100
                    : 100
                )}`}>
                  {healthData.providers.total_providers > 0
                    ? ((healthData.providers.healthy_providers / healthData.providers.total_providers) * 100).toFixed(1)
                    : 100}%
                </p>
              </div>
            </div>

            {/* AI Agents - from native system object */}
            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.system.status)}
                <div className="flex items-center gap-2">
                  <Users className="h-4 w-4 text-theme-muted" />
                  <div>
                    <p className="text-sm font-medium text-theme-primary">AI Agents</p>
                    <p className="text-xs text-theme-muted">
                      {healthData.system.active_agents} active
                    </p>
                  </div>
                </div>
              </div>
              <Badge variant={getHealthStatusBadge(healthData.system.status)} size="sm">
                {healthData.system.status}
              </Badge>
            </div>

            {/* Workflows - from native system object */}
            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.system.status)}
                <div className="flex items-center gap-2">
                  <Workflow className="h-4 w-4 text-theme-muted" />
                  <div>
                    <p className="text-sm font-medium text-theme-primary">Workflows</p>
                    <p className="text-xs text-theme-muted">
                      {healthData.system.active_workflows} active, {healthData.system.running_executions} running
                    </p>
                  </div>
                </div>
              </div>
              <Badge variant={getHealthStatusBadge(healthData.system.status)} size="sm">
                {healthData.system.status}
              </Badge>
            </div>

            {/* Database - from native database object */}
            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.database.status)}
                <div className="flex items-center gap-2">
                  <Database className="h-4 w-4 text-theme-muted" />
                  <div>
                    <p className="text-sm font-medium text-theme-primary">Database</p>
                    <p className="text-xs text-theme-muted">
                      {healthData.database.connection_pool
                        ? `${healthData.database.connection_pool.busy} / ${healthData.database.connection_pool.size} connections`
                        : healthData.database.connection || 'Connected'}
                    </p>
                  </div>
                </div>
              </div>
              {healthData.database.connection_pool ? (
                <div className="text-right">
                  <p className={`text-sm font-medium ${getHealthScoreColor(getDatabaseAvailability())}`}>
                    {getDatabaseAvailability().toFixed(1)}% avail
                  </p>
                </div>
              ) : (
                <Badge variant={getHealthStatusBadge(healthData.database.status)} size="sm">
                  {healthData.database.status}
                </Badge>
              )}
            </div>

            {/* Redis - from native redis object */}
            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.redis.status)}
                <div className="flex items-center gap-2">
                  <Server className="h-4 w-4 text-theme-muted" />
                  <div>
                    <p className="text-sm font-medium text-theme-primary">Redis</p>
                    <p className="text-xs text-theme-muted">
                      {healthData.redis.used_memory || 'Connected'}
                      {healthData.redis.connected_clients !== undefined &&
                        `, ${healthData.redis.connected_clients} clients`}
                    </p>
                  </div>
                </div>
              </div>
              <Badge variant={getHealthStatusBadge(healthData.redis.status)} size="sm">
                {healthData.redis.status}
              </Badge>
            </div>

            {/* Workers - from native workers object */}
            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.workers.status)}
                <div className="flex items-center gap-2">
                  <HardDrive className="h-4 w-4 text-theme-muted" />
                  <div>
                    <p className="text-sm font-medium text-theme-primary">Workers</p>
                    <p className="text-xs text-theme-muted">
                      {healthData.workers.recent_completions} completed, {healthData.workers.estimated_backlog} backlog
                    </p>
                  </div>
                </div>
              </div>
              {healthData.workers.estimated_backlog > 0 ? (
                <div className="text-right">
                  <p className={`text-sm font-medium ${getHealthScoreColor(getWorkerThroughput())}`}>
                    {getWorkerThroughput().toFixed(1)}%
                  </p>
                </div>
              ) : (
                <Badge variant={getHealthStatusBadge(healthData.workers.status)} size="sm">
                  {healthData.workers.status}
                </Badge>
              )}
            </div>
          </div>
        </div>

        {/* Circuit Breakers Summary */}
        {healthData.circuit_breakers && (
          <div className="space-y-3">
            <h4 className="text-sm font-medium text-theme-primary">Circuit Breakers</h4>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex items-center justify-between p-2 bg-theme-surface rounded border border-theme-border">
                <span className="text-sm text-theme-muted">Healthy</span>
                <Badge variant="success" size="sm">
                  {healthData.circuit_breakers.healthy}
                </Badge>
              </div>
              <div className="flex items-center justify-between p-2 bg-theme-surface rounded border border-theme-border">
                <span className="text-sm text-theme-muted">Degraded</span>
                <Badge variant="warning" size="sm">
                  {healthData.circuit_breakers.degraded}
                </Badge>
              </div>
              <div className="flex items-center justify-between p-2 bg-theme-surface rounded border border-theme-border">
                <span className="text-sm text-theme-muted">Unhealthy</span>
                <Badge variant="danger" size="sm">
                  {healthData.circuit_breakers.unhealthy}
                </Badge>
              </div>
              <div className="flex items-center justify-between p-2 bg-theme-surface rounded border border-theme-border">
                <span className="text-sm text-theme-muted">Total</span>
                <Badge variant="info" size="sm">
                  {healthData.circuit_breakers.total_services}
                </Badge>
              </div>
            </div>
          </div>
        )}

        {/* Last Updated */}
        <div className="text-center pt-2 border-t border-theme-border">
          <p className="text-xs text-theme-muted">
            Last updated: {new Date(healthData.timestamp).toLocaleTimeString()}
          </p>
        </div>
      </CardContent>
    </Card>
  );
};
