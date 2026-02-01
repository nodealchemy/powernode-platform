import React, { useState, useMemo } from 'react';
import {
  Activity,
  AlertCircle,
  AlertTriangle,
  CheckCircle,
  Clock,
  DollarSign,
  Hash,
  RefreshCw,
  Settings,
  TestTube,
  XCircle,
  Zap
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Progress } from '@/shared/components/ui/Progress';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import type { ProviderMetrics } from '@/shared/types/monitoring';
import { cn } from '@/shared/utils/cn';

interface ProviderHealthDashboardProps {
  providers: ProviderMetrics[];
  isLoading: boolean;
  timeRange: string;
  onRefresh: () => void;
  onTestProvider?: (providerId: string, params: Record<string, unknown>) => void;
  onViewDetails?: (providerId: string) => void;
}

/**
 * ProviderHealthDashboard - Comprehensive AI provider health monitoring
 *
 * Features:
 * - Real-time health scores and status
 * - Circuit breaker states
 * - Performance metrics (latency, success rate, throughput)
 * - Cost tracking
 * - Alert management
 * - Latency percentiles (p50, p95, p99)
 */
export const ProviderHealthDashboard: React.FC<ProviderHealthDashboardProps> = ({
  providers,
  isLoading,
  timeRange,
  onRefresh,
  onTestProvider,
  onViewDetails,
}) => {
  const [selectedProvider, setSelectedProvider] = useState<string | null>(null);

  // Aggregate statistics
  const aggregateStats = useMemo(() => {
    if (providers.length === 0) {
      return {
        totalProviders: 0,
        healthyCount: 0,
        degradedCount: 0,
        unhealthyCount: 0,
        avgHealthScore: 0,
        totalCost: 0,
        totalExecutions: 0,
        avgSuccessRate: 0,
        avgLatency: 0,
        circuitBreakersClosed: 0,
        circuitBreakersOpen: 0,
        circuitBreakersHalfOpen: 0,
        totalAlerts: 0,
      };
    }

    const healthyCount = providers.filter(p => p.status === 'healthy').length;
    const degradedCount = providers.filter(p => p.status === 'degraded').length;
    const unhealthyCount = providers.filter(p => p.status === 'unhealthy').length;

    return {
      totalProviders: providers.length,
      healthyCount,
      degradedCount,
      unhealthyCount,
      avgHealthScore: providers.reduce((sum, p) => sum + p.health_score, 0) / providers.length,
      totalCost: providers.reduce((sum, p) => sum + p.usage.cost, 0),
      totalExecutions: providers.reduce((sum, p) => sum + p.usage.executions_count, 0),
      avgSuccessRate: providers.reduce((sum, p) => sum + p.performance.success_rate, 0) / providers.length,
      avgLatency: providers.reduce((sum, p) => sum + p.performance.avg_response_time, 0) / providers.length,
      circuitBreakersClosed: providers.filter(p => p.circuit_breaker.state === 'closed').length,
      circuitBreakersOpen: providers.filter(p => p.circuit_breaker.state === 'open').length,
      circuitBreakersHalfOpen: providers.filter(p => p.circuit_breaker.state === 'half_open').length,
      totalAlerts: providers.reduce((sum, p) => sum + p.alerts.length, 0),
    };
  }, [providers]);

  // Get status badge variant
  const getStatusBadgeVariant = (status: string): 'success' | 'warning' | 'danger' | 'info' | 'outline' => {
    switch (status) {
      case 'healthy': return 'success';
      case 'degraded': return 'warning';
      case 'unhealthy': return 'danger';
      case 'recovering': return 'info';
      default: return 'outline';
    }
  };

  // Get circuit breaker icon
  const getCircuitBreakerIcon = (state: string) => {
    switch (state) {
      case 'closed': return <CheckCircle className="h-4 w-4 text-theme-success" />;
      case 'half_open': return <Clock className="h-4 w-4 text-theme-warning" />;
      case 'open': return <XCircle className="h-4 w-4 text-theme-danger" />;
      default: return <AlertCircle className="h-4 w-4 text-theme-muted" />;
    }
  };

  // Get health score color
  const getHealthScoreColor = (score: number) => {
    if (score >= 90) return 'text-theme-success';
    if (score >= 70) return 'text-theme-warning';
    return 'text-theme-danger';
  };

  // Format currency
  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2,
      maximumFractionDigits: 4,
    }).format(amount);
  };

  // Format latency
  const formatLatency = (ms: number) => {
    if (ms < 1000) return `${ms.toFixed(0)}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  // Render summary cards
  const renderSummaryCards = () => (
    <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4 mb-6">
      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-theme-muted">Health Score</p>
              <p className={cn('text-2xl font-bold', getHealthScoreColor(aggregateStats.avgHealthScore))}>
                {aggregateStats.avgHealthScore.toFixed(1)}%
              </p>
            </div>
            <Activity className="h-8 w-8 text-theme-muted" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-theme-muted">Success Rate</p>
              <p className={cn('text-2xl font-bold', aggregateStats.avgSuccessRate >= 95 ? 'text-theme-success' : 'text-theme-warning')}>
                {aggregateStats.avgSuccessRate.toFixed(1)}%
              </p>
            </div>
            <CheckCircle className="h-8 w-8 text-theme-muted" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-theme-muted">Avg Latency</p>
              <p className="text-2xl font-bold text-theme-primary">
                {formatLatency(aggregateStats.avgLatency)}
              </p>
            </div>
            <Clock className="h-8 w-8 text-theme-muted" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-theme-muted">Executions</p>
              <p className="text-2xl font-bold text-theme-primary">
                {aggregateStats.totalExecutions.toLocaleString()}
              </p>
            </div>
            <Hash className="h-8 w-8 text-theme-muted" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-theme-muted">Total Cost</p>
              <p className="text-2xl font-bold text-theme-primary">
                {formatCurrency(aggregateStats.totalCost)}
              </p>
            </div>
            <DollarSign className="h-8 w-8 text-theme-muted" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-theme-muted">Active Alerts</p>
              <p className={cn('text-2xl font-bold', aggregateStats.totalAlerts > 0 ? 'text-theme-danger' : 'text-theme-success')}>
                {aggregateStats.totalAlerts}
              </p>
            </div>
            <AlertTriangle className="h-8 w-8 text-theme-muted" />
          </div>
        </CardContent>
      </Card>
    </div>
  );

  // Render status overview
  const renderStatusOverview = () => (
    <Card className="mb-6">
      <CardContent className="p-4">
        <div className="flex items-center justify-between flex-wrap gap-4">
          <div className="flex items-center gap-8">
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-theme-success" />
              <span className="text-sm text-theme-muted">Healthy</span>
              <span className="font-semibold text-theme-primary">{aggregateStats.healthyCount}</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-theme-warning" />
              <span className="text-sm text-theme-muted">Degraded</span>
              <span className="font-semibold text-theme-primary">{aggregateStats.degradedCount}</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-theme-danger" />
              <span className="text-sm text-theme-muted">Unhealthy</span>
              <span className="font-semibold text-theme-primary">{aggregateStats.unhealthyCount}</span>
            </div>
          </div>

          <div className="flex items-center gap-8">
            <div className="flex items-center gap-2">
              <Zap className="h-4 w-4 text-theme-success" />
              <span className="text-sm text-theme-muted">Closed</span>
              <span className="font-semibold text-theme-primary">{aggregateStats.circuitBreakersClosed}</span>
            </div>
            <div className="flex items-center gap-2">
              <Clock className="h-4 w-4 text-theme-warning" />
              <span className="text-sm text-theme-muted">Half Open</span>
              <span className="font-semibold text-theme-primary">{aggregateStats.circuitBreakersHalfOpen}</span>
            </div>
            <div className="flex items-center gap-2">
              <XCircle className="h-4 w-4 text-theme-danger" />
              <span className="text-sm text-theme-muted">Open</span>
              <span className="font-semibold text-theme-primary">{aggregateStats.circuitBreakersOpen}</span>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );

  // Render provider card
  const renderProviderCard = (provider: ProviderMetrics) => (
    <Card
      key={provider.id}
      className={cn(
        'cursor-pointer transition-all hover:shadow-md',
        selectedProvider === provider.id && 'ring-2 ring-theme-primary'
      )}
      onClick={() => setSelectedProvider(selectedProvider === provider.id ? null : provider.id)}
    >
      <CardHeader
        title={provider.name}
        icon={<Settings className="h-5 w-5" />}
        action={<Badge variant={getStatusBadgeVariant(provider.status)}>{provider.status}</Badge>}
        className="pb-3"
      />
      <CardContent className="space-y-4">
        {/* Health Score */}
        <div className="flex items-center justify-between">
          <span className="text-sm text-theme-muted">Health Score</span>
          <span className={cn('font-medium', getHealthScoreColor(provider.health_score))}>
            {provider.health_score.toFixed(1)}%
          </span>
        </div>

        {/* Circuit Breaker */}
        <div className="flex items-center justify-between">
          <span className="text-sm text-theme-muted">Circuit Breaker</span>
          <div className="flex items-center gap-1">
            {getCircuitBreakerIcon(provider.circuit_breaker.state)}
            <span className="text-sm capitalize">{provider.circuit_breaker.state.replace('_', ' ')}</span>
          </div>
        </div>

        {/* Performance Metrics */}
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-muted">Success Rate</span>
            <span className={provider.performance.success_rate >= 95 ? 'text-theme-success' : provider.performance.success_rate >= 90 ? 'text-theme-warning' : 'text-theme-danger'}>
              {provider.performance.success_rate.toFixed(1)}%
            </span>
          </div>
          <Progress value={provider.performance.success_rate} className="h-2" />
        </div>

        <div className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <span className="text-theme-muted block">Avg Response</span>
            <span className="font-medium">
              {formatLatency(provider.performance.avg_response_time)}
            </span>
          </div>
          <div>
            <span className="text-theme-muted block">Executions</span>
            <span className="font-medium">
              {provider.usage.executions_count.toLocaleString()}
            </span>
          </div>
        </div>

        {/* Cost */}
        <div className="flex items-center justify-between text-sm">
          <span className="text-theme-muted">Cost ({timeRange})</span>
          <span className="font-medium">
            {formatCurrency(provider.usage.cost)}
          </span>
        </div>

        {/* Error Rate */}
        {provider.performance.error_rate > 0 && (
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-muted">Error Rate</span>
            <span className="text-theme-danger font-medium">
              {provider.performance.error_rate.toFixed(2)}%
            </span>
          </div>
        )}

        {/* Active Alerts */}
        {provider.alerts.length > 0 && (
          <div className="flex items-center gap-2 p-2 bg-theme-danger/10 rounded border border-theme-danger/20">
            <AlertCircle className="h-4 w-4 text-theme-danger" />
            <span className="text-sm text-theme-danger">
              {provider.alerts.length} active alert{provider.alerts.length > 1 ? 's' : ''}
            </span>
          </div>
        )}

        {/* Actions */}
        <div className="pt-2 border-t border-theme flex gap-2">
          {onTestProvider && (
            <Button
              onClick={(e) => {
                e.stopPropagation();
                onTestProvider(provider.id, {});
              }}
              variant="outline"
              size="sm"
              className="flex-1"
            >
              <TestTube className="h-4 w-4 mr-2" />
              Test
            </Button>
          )}
          {onViewDetails && (
            <Button
              onClick={(e) => {
                e.stopPropagation();
                onViewDetails(provider.id);
              }}
              variant="outline"
              size="sm"
              className="flex-1"
            >
              Details
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );

  // Render provider details panel
  const renderProviderDetails = () => {
    const provider = providers.find(p => p.id === selectedProvider);
    if (!provider) return null;

    return (
      <Card className="mt-6">
        <CardHeader
          title={`${provider.name} - Detailed Metrics`}
          icon={<Settings className="h-5 w-5" />}
          action={
            <Button variant="outline" size="sm" onClick={() => setSelectedProvider(null)}>
              Close
            </Button>
          }
        />
        <CardContent>
          <Tabs defaultValue="performance">
            <TabsList>
              <TabsTrigger value="performance">Performance</TabsTrigger>
              <TabsTrigger value="circuit-breaker">Circuit Breaker</TabsTrigger>
              <TabsTrigger value="credentials">Credentials</TabsTrigger>
              <TabsTrigger value="alerts">Alerts ({provider.alerts.length})</TabsTrigger>
            </TabsList>

            <TabsContent value="performance" className="space-y-4 mt-4">
              <div className="grid grid-cols-4 gap-4">
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Success Rate</p>
                  <p className="text-xl font-bold text-theme-primary">
                    {provider.performance.success_rate.toFixed(2)}%
                  </p>
                </div>
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Avg Response Time</p>
                  <p className="text-xl font-bold text-theme-primary">
                    {formatLatency(provider.performance.avg_response_time)}
                  </p>
                </div>
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Throughput</p>
                  <p className="text-xl font-bold text-theme-primary">
                    {provider.performance.throughput.toFixed(1)}/min
                  </p>
                </div>
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Error Rate</p>
                  <p className={cn('text-xl font-bold', provider.performance.error_rate > 5 ? 'text-theme-danger' : 'text-theme-success')}>
                    {provider.performance.error_rate.toFixed(2)}%
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Total Executions</p>
                  <p className="text-xl font-bold text-theme-primary">
                    {provider.usage.executions_count.toLocaleString()}
                  </p>
                </div>
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Tokens Consumed</p>
                  <p className="text-xl font-bold text-theme-primary">
                    {provider.usage.tokens_consumed.toLocaleString()}
                  </p>
                </div>
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Total Cost</p>
                  <p className="text-xl font-bold text-theme-primary">
                    {formatCurrency(provider.usage.cost)}
                  </p>
                </div>
              </div>
            </TabsContent>

            <TabsContent value="circuit-breaker" className="space-y-4 mt-4">
              <div className="flex items-center gap-4 p-4 bg-theme-surface rounded">
                <div className="flex items-center gap-2">
                  {getCircuitBreakerIcon(provider.circuit_breaker.state)}
                  <span className="text-lg font-medium capitalize">
                    {provider.circuit_breaker.state.replace('_', ' ')}
                  </span>
                </div>
                <Badge variant={provider.circuit_breaker.state === 'closed' ? 'success' : provider.circuit_breaker.state === 'open' ? 'danger' : 'warning'}>
                  {provider.circuit_breaker.state}
                </Badge>
              </div>

              <div className="grid grid-cols-4 gap-4">
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Failure Count</p>
                  <p className="text-xl font-bold text-theme-primary">
                    {provider.circuit_breaker.failure_count}
                  </p>
                </div>
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Success Threshold</p>
                  <p className="text-xl font-bold text-theme-primary">
                    {provider.circuit_breaker.success_threshold}
                  </p>
                </div>
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Timeout</p>
                  <p className="text-xl font-bold text-theme-primary">
                    {provider.circuit_breaker.timeout}s
                  </p>
                </div>
                <div className="p-4 bg-theme-surface rounded">
                  <p className="text-xs text-theme-muted">Last Failure</p>
                  <p className="text-sm font-medium text-theme-primary">
                    {provider.circuit_breaker.last_failure
                      ? new Date(provider.circuit_breaker.last_failure).toLocaleString()
                      : 'Never'}
                  </p>
                </div>
              </div>

              <div className="p-4 bg-theme-surface rounded">
                <h4 className="text-sm font-medium text-theme-muted mb-3">Request Statistics</h4>
                <div className="grid grid-cols-4 gap-4">
                  <div>
                    <p className="text-xs text-theme-muted">Total Requests</p>
                    <p className="font-semibold">{provider.circuit_breaker.stats.total_requests}</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-muted">Successful</p>
                    <p className="font-semibold text-theme-success">{provider.circuit_breaker.stats.successful_requests}</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-muted">Failed</p>
                    <p className="font-semibold text-theme-danger">{provider.circuit_breaker.stats.failed_requests}</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-muted">Avg Response</p>
                    <p className="font-semibold">{formatLatency(provider.circuit_breaker.stats.avg_response_time)}</p>
                  </div>
                </div>
              </div>
            </TabsContent>

            <TabsContent value="credentials" className="space-y-4 mt-4">
              {provider.credentials.length === 0 ? (
                <EmptyState
                  icon={Settings}
                  title="No Credentials"
                  description="No credentials configured for this provider"
                />
              ) : (
                <div className="space-y-2">
                  {provider.credentials.map(cred => (
                    <div key={cred.id} className="flex items-center justify-between p-3 bg-theme-surface rounded">
                      <div className="flex items-center gap-3">
                        {cred.status === 'valid' && <CheckCircle className="h-4 w-4 text-theme-success" />}
                        {cred.status === 'invalid' && <XCircle className="h-4 w-4 text-theme-danger" />}
                        {cred.status === 'expired' && <AlertTriangle className="h-4 w-4 text-theme-warning" />}
                        {cred.status === 'unknown' && <AlertCircle className="h-4 w-4 text-theme-muted" />}
                        <div>
                          <p className="font-medium text-theme-primary">{cred.name}</p>
                          <p className="text-xs text-theme-muted">
                            {cred.last_tested
                              ? `Last tested: ${new Date(cred.last_tested).toLocaleString()}`
                              : 'Never tested'}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <Badge variant={cred.is_active ? 'success' : 'outline'}>
                          {cred.is_active ? 'Active' : 'Inactive'}
                        </Badge>
                        <Badge variant={cred.status === 'valid' ? 'success' : cred.status === 'invalid' ? 'danger' : 'warning'}>
                          {cred.status}
                        </Badge>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </TabsContent>

            <TabsContent value="alerts" className="space-y-4 mt-4">
              {provider.alerts.length === 0 ? (
                <EmptyState
                  icon={CheckCircle}
                  title="No Active Alerts"
                  description="This provider has no active alerts"
                />
              ) : (
                <div className="space-y-2">
                  {provider.alerts.map(alert => (
                    <div
                      key={alert.id}
                      className={cn(
                        'p-3 rounded border',
                        alert.severity === 'critical' && 'bg-theme-danger/10 border-theme-danger/30',
                        alert.severity === 'high' && 'bg-theme-danger/10 border-theme-danger/30',
                        alert.severity === 'medium' && 'bg-theme-warning/10 border-theme-warning/30',
                        alert.severity === 'low' && 'bg-theme-info/10 border-theme-info/30'
                      )}
                    >
                      <div className="flex items-start justify-between">
                        <div className="flex items-start gap-2">
                          <AlertTriangle className={cn(
                            'h-4 w-4 mt-0.5',
                            alert.severity === 'critical' && 'text-theme-danger',
                            alert.severity === 'high' && 'text-theme-danger',
                            alert.severity === 'medium' && 'text-theme-warning',
                            alert.severity === 'low' && 'text-theme-info'
                          )} />
                          <div>
                            <p className="font-medium text-theme-primary">{alert.title}</p>
                            <p className="text-sm text-theme-muted">{alert.message}</p>
                            <p className="text-xs text-theme-muted mt-1">
                              {new Date(alert.created_at).toLocaleString()}
                            </p>
                          </div>
                        </div>
                        <Badge variant={alert.severity === 'critical' || alert.severity === 'high' ? 'danger' : alert.severity === 'medium' ? 'warning' : 'info'}>
                          {alert.severity}
                        </Badge>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    );
  };

  // Loading state
  if (isLoading && providers.length === 0) {
    return (
      <Card>
        <CardHeader
          title="Provider Health Dashboard"
          icon={<Activity className="h-5 w-5" />}
        />
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading provider health data..." />
        </CardContent>
      </Card>
    );
  }

  // Empty state
  if (providers.length === 0) {
    return (
      <Card>
        <CardHeader
          title="Provider Health Dashboard"
          icon={<Activity className="h-5 w-5" />}
        />
        <CardContent>
          <EmptyState
            icon={Settings}
            title="No Providers Found"
            description="Configure AI providers to see health metrics"
          />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold text-theme-primary">Provider Health Dashboard</h2>
        <div className="flex items-center gap-2">
          <Badge variant="outline">{timeRange}</Badge>
          <Button
            onClick={onRefresh}
            variant="outline"
            size="sm"
            disabled={isLoading}
          >
            <RefreshCw className={cn('h-4 w-4 mr-2', isLoading && 'animate-spin')} />
            Refresh
          </Button>
        </div>
      </div>

      {/* Summary Cards */}
      {renderSummaryCards()}

      {/* Status Overview */}
      {renderStatusOverview()}

      {/* Provider Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {providers.map(renderProviderCard)}
      </div>

      {/* Provider Details Panel */}
      {selectedProvider && renderProviderDetails()}
    </div>
  );
};

export default ProviderHealthDashboard;
