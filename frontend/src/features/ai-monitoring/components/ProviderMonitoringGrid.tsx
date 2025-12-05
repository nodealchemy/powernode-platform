import React from 'react';
import {
  AlertCircle,
  CheckCircle,
  Clock,
  RefreshCw,
  Settings,
  TestTube,
  XCircle
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Progress } from '@/shared/components/ui/Progress';
import { Loading } from '@/shared/components/ui/Loading';
import { ProviderMetrics } from '@/shared/types/monitoring';

interface ProviderMonitoringGridProps {
  providers: ProviderMetrics[];
  isLoading: boolean;
  timeRange: string;
  onRefresh: () => void;
  onTestProvider?: (providerId: string, params: any) => void;
}

export const ProviderMonitoringGrid: React.FC<ProviderMonitoringGridProps> = ({
  providers,
  isLoading,
  timeRange,
  onRefresh,
  onTestProvider
}) => {
  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'healthy': return 'success';
      case 'degraded': return 'warning';
      case 'unhealthy': return 'danger';
      case 'recovering': return 'info';
      default: return 'outline';
    }
  };

  const getCircuitBreakerIcon = (state: string) => {
    switch (state) {
      case 'closed': return <CheckCircle className="h-4 w-4 text-theme-success" />;
      case 'half_open': return <Clock className="h-4 w-4 text-theme-warning" />;
      case 'open': return <XCircle className="h-4 w-4 text-theme-error" />;
      default: return <AlertCircle className="h-4 w-4 text-theme-muted" />;
    }
  };

  if (isLoading && providers.length === 0) {
    return (
      <Card>
        <CardHeader title="Provider Monitoring" />
        <CardContent className="flex items-center justify-center py-8">
          <Loading size="lg" message="Loading provider data..." />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium text-theme-primary">AI Provider Monitoring</h3>
        <Button
          onClick={onRefresh}
          variant="outline"
          size="sm"
          disabled={isLoading}
        >
          <RefreshCw className={`h-4 w-4 mr-2 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        {providers.map((provider) => (
          <Card key={provider.id} className="relative">
            <CardHeader
              title={provider.name}
              icon={<Settings className="h-5 w-5" />}
              action={<Badge variant={getStatusBadge(provider.status)}>{provider.status}</Badge>}
              className="pb-3"
            />
            <CardContent className="space-y-4">
              {/* Health Score */}
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-muted">Health Score</span>
                <span className={`font-medium ${provider.health_score >= 90 ? 'text-theme-success' : provider.health_score >= 70 ? 'text-theme-warning' : 'text-theme-error'}`}>
                  {provider.health_score.toFixed(1)}%
                </span>
              </div>

              {/* Circuit Breaker */}
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-muted">Circuit Breaker</span>
                <div className="flex items-center gap-1">
                  {getCircuitBreakerIcon(provider.circuit_breaker.state)}
                  <span className="text-sm capitalize">{provider.circuit_breaker.state}</span>
                </div>
              </div>

              {/* Performance Metrics */}
              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-muted">Success Rate</span>
                  <span className={provider.performance.success_rate >= 95 ? 'text-theme-success' : provider.performance.success_rate >= 90 ? 'text-theme-warning' : 'text-theme-error'}>
                    {provider.performance.success_rate.toFixed(1)}%
                  </span>
                </div>
                <Progress value={provider.performance.success_rate} className="h-2" />
              </div>

              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="text-theme-muted block">Avg Response</span>
                  <span className="font-medium">
                    {provider.performance.avg_response_time.toFixed(0)}ms
                  </span>
                </div>
                <div>
                  <span className="text-theme-muted block">Executions</span>
                  <span className="font-medium">
                    {provider.usage.executions_count}
                  </span>
                </div>
              </div>

              {/* Cost */}
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-muted">Cost ({timeRange})</span>
                <span className="font-medium">
                  ${provider.usage.cost.toFixed(4)}
                </span>
              </div>

              {/* Active Alerts */}
              {provider.alerts.length > 0 && (
                <div className="flex items-center gap-2 p-2 bg-theme-error/10 rounded border border-theme-error/20">
                  <AlertCircle className="h-4 w-4 text-theme-error" />
                  <span className="text-sm text-theme-error">
                    {provider.alerts.length} active alert{provider.alerts.length > 1 ? 's' : ''}
                  </span>
                </div>
              )}

              {/* Actions */}
              {onTestProvider && (
                <div className="pt-2 border-t border-theme-border">
                  <Button
                    onClick={() => onTestProvider(provider.id, {})}
                    variant="outline"
                    size="sm"
                    className="w-full"
                  >
                    <TestTube className="h-4 w-4 mr-2" />
                    Test Provider
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {providers.length === 0 && !isLoading && (
        <Card>
          <CardContent className="py-8 text-center">
            <Settings className="h-12 w-12 text-theme-muted mx-auto mb-4" />
            <p className="text-theme-muted">No providers found</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
};