import React from 'react';
import {
  Activity,
  AlertTriangle,
  CheckCircle,
  Clock,
  RefreshCw,
  XCircle
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Loading } from '@/shared/components/ui/Loading';
import { SystemHealthData } from '@/shared/types/monitoring';

interface SystemHealthDashboardProps {
  healthData: SystemHealthData | null;
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
      case 'excellent':
        return 'success';
      case 'good':
        return 'info';
      case 'fair':
        return 'warning';
      case 'degraded':
      case 'critical':
        return 'danger';
      default:
        return 'outline';
    }
  };

  const getHealthScoreColor = (score: number) => {
    if (score >= 90) return 'text-theme-success';
    if (score >= 80) return 'text-theme-info';
    if (score >= 70) return 'text-theme-warning';
    if (score >= 50) return 'text-theme-error';
    return 'text-theme-error';
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
        {/* Overall Health Score */}
        <div className="text-center">
          <div className={`text-3xl font-bold ${getHealthScoreColor(healthData.overall_health)}`}>
            {healthData.overall_health.toFixed(1)}%
          </div>
          <Badge variant={getHealthStatusBadge(healthData.status)} className="mt-2">
            {healthData.status.charAt(0).toUpperCase() + healthData.status.slice(1)}
          </Badge>
          <p className="text-sm text-theme-muted mt-1">Overall System Health</p>
        </div>

        {/* Component Health Status */}
        <div className="space-y-3">
          <h4 className="text-sm font-medium text-theme-primary">Component Status</h4>

          <div className="grid grid-cols-1 gap-3">
            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.components.providers.status)}
                <div>
                  <p className="text-sm font-medium text-theme-primary">AI Providers</p>
                  <p className="text-xs text-theme-muted">
                    {healthData.components.providers.active_count} active
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className={`text-sm font-medium ${getHealthScoreColor(healthData.components.providers.health_score)}`}>
                  {healthData.components.providers.health_score.toFixed(1)}%
                </p>
                {healthData.components.providers.issues.length > 0 && (
                  <p className="text-xs text-theme-error">
                    {healthData.components.providers.issues.length} issue(s)
                  </p>
                )}
              </div>
            </div>

            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.components.agents.status)}
                <div>
                  <p className="text-sm font-medium text-theme-primary">AI Agents</p>
                  <p className="text-xs text-theme-muted">
                    {healthData.components.agents.active_count} active
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className={`text-sm font-medium ${getHealthScoreColor(healthData.components.agents.health_score)}`}>
                  {healthData.components.agents.health_score.toFixed(1)}%
                </p>
                {healthData.components.agents.issues.length > 0 && (
                  <p className="text-xs text-theme-error">
                    {healthData.components.agents.issues.length} issue(s)
                  </p>
                )}
              </div>
            </div>

            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.components.workflows.status)}
                <div>
                  <p className="text-sm font-medium text-theme-primary">Workflows</p>
                  <p className="text-xs text-theme-muted">
                    {healthData.components.workflows.active_count} active
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className={`text-sm font-medium ${getHealthScoreColor(healthData.components.workflows.health_score)}`}>
                  {healthData.components.workflows.health_score.toFixed(1)}%
                </p>
                {healthData.components.workflows.issues.length > 0 && (
                  <p className="text-xs text-theme-error">
                    {healthData.components.workflows.issues.length} issue(s)
                  </p>
                )}
              </div>
            </div>

            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.components.conversations.status)}
                <div>
                  <p className="text-sm font-medium text-theme-primary">Conversations</p>
                  <p className="text-xs text-theme-muted">
                    {healthData.components.conversations.active_count} active
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className={`text-sm font-medium ${getHealthScoreColor(healthData.components.conversations.health_score)}`}>
                  {healthData.components.conversations.health_score.toFixed(1)}%
                </p>
                {healthData.components.conversations.issues.length > 0 && (
                  <p className="text-xs text-theme-error">
                    {healthData.components.conversations.issues.length} issue(s)
                  </p>
                )}
              </div>
            </div>

            <div className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme-border">
              <div className="flex items-center gap-3">
                {getComponentStatusIcon(healthData.components.infrastructure.status)}
                <div>
                  <p className="text-sm font-medium text-theme-primary">Infrastructure</p>
                  <p className="text-xs text-theme-muted">
                    System resources
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className={`text-sm font-medium ${getHealthScoreColor(healthData.components.infrastructure.health_score)}`}>
                  {healthData.components.infrastructure.health_score.toFixed(1)}%
                </p>
                {healthData.components.infrastructure.issues.length > 0 && (
                  <p className="text-xs text-theme-error">
                    {healthData.components.infrastructure.issues.length} issue(s)
                  </p>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Alert Summary */}
        {healthData.alerts && (
          <div className="space-y-3">
            <h4 className="text-sm font-medium text-theme-primary">Active Alerts</h4>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex items-center justify-between p-2 bg-theme-surface rounded border border-theme-border">
                <span className="text-sm text-theme-muted">High Priority</span>
                <Badge variant="danger" size="sm">
                  {healthData.alerts.high_priority}
                </Badge>
              </div>
              <div className="flex items-center justify-between p-2 bg-theme-surface rounded border border-theme-border">
                <span className="text-sm text-theme-muted">Medium Priority</span>
                <Badge variant="warning" size="sm">
                  {healthData.alerts.medium_priority}
                </Badge>
              </div>
              <div className="flex items-center justify-between p-2 bg-theme-surface rounded border border-theme-border">
                <span className="text-sm text-theme-muted">Low Priority</span>
                <Badge variant="info" size="sm">
                  {healthData.alerts.low_priority}
                </Badge>
              </div>
              <div className="flex items-center justify-between p-2 bg-theme-surface rounded border border-theme-border">
                <span className="text-sm text-theme-muted">Recent</span>
                <Badge variant="outline" size="sm">
                  {healthData.alerts.recent_count}
                </Badge>
              </div>
            </div>
          </div>
        )}

        {/* Health Recommendations */}
        {healthData.recommendations && healthData.recommendations.length > 0 && (
          <div className="space-y-3">
            <h4 className="text-sm font-medium text-theme-primary">Recommendations</h4>
            <div className="space-y-2">
              {healthData.recommendations.slice(0, 3).map((recommendation, index) => (
                <div
                  key={index}
                  className="p-3 bg-theme-surface rounded border border-theme-border"
                >
                  <div className="flex items-start gap-2">
                    {recommendation.priority === 'high' && (
                      <AlertTriangle className="h-4 w-4 text-theme-error mt-0.5" />
                    )}
                    {recommendation.priority === 'medium' && (
                      <AlertTriangle className="h-4 w-4 text-theme-warning mt-0.5" />
                    )}
                    {recommendation.priority === 'low' && (
                      <AlertTriangle className="h-4 w-4 text-theme-info mt-0.5" />
                    )}
                    <div className="flex-1">
                      <p className="text-sm font-medium text-theme-primary">
                        {recommendation.message}
                      </p>
                      <p className="text-xs text-theme-muted mt-1">
                        {recommendation.component} • {recommendation.action}
                      </p>
                    </div>
                  </div>
                </div>
              ))}
              {healthData.recommendations.length > 3 && (
                <p className="text-xs text-theme-muted text-center">
                  +{healthData.recommendations.length - 3} more recommendations
                </p>
              )}
            </div>
          </div>
        )}

        {/* Last Updated */}
        <div className="text-center pt-2 border-t border-theme-border">
          <p className="text-xs text-theme-muted">
            Last updated: {new Date(healthData.last_updated).toLocaleTimeString()}
          </p>
        </div>
      </CardContent>
    </Card>
  );
};