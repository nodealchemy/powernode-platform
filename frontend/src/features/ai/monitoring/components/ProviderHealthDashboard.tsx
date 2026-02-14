import React, { useState, useMemo } from 'react';
import { Activity, RefreshCw, Settings } from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import type { ProviderMetrics } from '@/shared/types/monitoring';
import { cn } from '@/shared/utils/cn';
import { ProviderHealthCard } from './ProviderHealthCard';
import { CircuitBreakerStatus } from './CircuitBreakerStatus';
import { LatencyPercentiles } from './LatencyPercentiles';
import { ProviderAlertsList } from './ProviderAlertsList';
import { ProviderCostTracking } from './ProviderCostTracking';

interface ProviderHealthDashboardProps {
  providers: ProviderMetrics[];
  isLoading: boolean;
  timeRange: string;
  onRefresh: () => void;
  onTestProvider?: (providerId: string, params: Record<string, unknown>) => void;
  onViewDetails?: (providerId: string) => void;
}

export const ProviderHealthDashboard: React.FC<ProviderHealthDashboardProps> = ({
  providers,
  isLoading,
  timeRange,
  onRefresh,
  onTestProvider,
  onViewDetails,
}) => {
  const [selectedProvider, setSelectedProvider] = useState<string | null>(null);

  const aggregateStats = useMemo(() => {
    if (providers.length === 0) {
      return {
        totalProviders: 0, healthyCount: 0, degradedCount: 0, unhealthyCount: 0,
        avgHealthScore: 0, totalCost: 0, totalExecutions: 0, avgSuccessRate: 0,
        avgLatency: 0, circuitBreakersClosed: 0, circuitBreakersOpen: 0,
        circuitBreakersHalfOpen: 0, totalAlerts: 0,
      };
    }

    return {
      totalProviders: providers.length,
      healthyCount: providers.filter(p => p.status === 'healthy').length,
      degradedCount: providers.filter(p => p.status === 'degraded').length,
      unhealthyCount: providers.filter(p => p.status === 'unhealthy').length,
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

  const selectedProviderData = selectedProvider ? providers.find(p => p.id === selectedProvider) : null;

  if (isLoading && providers.length === 0) {
    return (
      <Card>
        <CardHeader title="Provider Health Dashboard" icon={<Activity className="h-5 w-5" />} />
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading provider health data..." />
        </CardContent>
      </Card>
    );
  }

  if (providers.length === 0) {
    return (
      <Card>
        <CardHeader title="Provider Health Dashboard" icon={<Activity className="h-5 w-5" />} />
        <CardContent>
          <EmptyState icon={Settings} title="No Providers Found" description="Configure AI providers to see health metrics" />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold text-theme-primary">Provider Health Dashboard</h2>
        <div className="flex items-center gap-2">
          <Badge variant="outline">{timeRange}</Badge>
          <Button onClick={onRefresh} variant="outline" size="sm" disabled={isLoading}>
            <RefreshCw className={cn('h-4 w-4 mr-2', isLoading && 'animate-spin')} />
            Refresh
          </Button>
        </div>
      </div>

      <ProviderCostTracking aggregateStats={aggregateStats} section="summary" />
      <ProviderCostTracking aggregateStats={aggregateStats} section="status" />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {providers.map(provider => (
          <ProviderHealthCard
            key={provider.id}
            provider={provider}
            timeRange={timeRange}
            isSelected={selectedProvider === provider.id}
            onSelect={setSelectedProvider}
            onTestProvider={onTestProvider}
            onViewDetails={onViewDetails}
          />
        ))}
      </div>

      {selectedProviderData && (
        <Card className="mt-6">
          <CardHeader
            title={`${selectedProviderData.name} - Detailed Metrics`}
            icon={<Settings className="h-5 w-5" />}
            action={<Button variant="outline" size="sm" onClick={() => setSelectedProvider(null)}>Close</Button>}
          />
          <CardContent>
            <Tabs defaultValue="performance">
              <TabsList>
                <TabsTrigger value="performance">Performance</TabsTrigger>
                <TabsTrigger value="circuit-breaker">Circuit Breaker</TabsTrigger>
                <TabsTrigger value="credentials">Credentials</TabsTrigger>
                <TabsTrigger value="alerts">Alerts ({selectedProviderData.alerts.length})</TabsTrigger>
              </TabsList>
              <TabsContent value="performance" className="space-y-4 mt-4">
                <LatencyPercentiles provider={selectedProviderData} />
              </TabsContent>
              <TabsContent value="circuit-breaker" className="space-y-4 mt-4">
                <CircuitBreakerStatus provider={selectedProviderData} />
              </TabsContent>
              <TabsContent value="credentials" className="space-y-4 mt-4">
                <ProviderAlertsList provider={selectedProviderData} section="credentials" />
              </TabsContent>
              <TabsContent value="alerts" className="space-y-4 mt-4">
                <ProviderAlertsList provider={selectedProviderData} section="alerts" />
              </TabsContent>
            </Tabs>
          </CardContent>
        </Card>
      )}
    </div>
  );
};

export default ProviderHealthDashboard;
