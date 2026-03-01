import React from 'react';
import {
  AlertCircle,
  CheckCircle,
  Clock,
  Settings,
  TestTube,
  XCircle,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Progress } from '@/shared/components/ui/Progress';
import type { ProviderMetrics } from '@/shared/types/monitoring';
import { cn } from '@/shared/utils/cn';

interface ProviderHealthCardProps {
  provider: ProviderMetrics;
  isSelected: boolean;
  timeRange: string;
  onSelect: (id: string | null) => void;
  onTestProvider?: (providerId: string, params: Record<string, unknown>) => void;
  onViewDetails?: (providerId: string) => void;
}

const getStatusBadgeVariant = (status: string): 'success' | 'warning' | 'danger' | 'info' | 'outline' => {
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
    case 'open': return <XCircle className="h-4 w-4 text-theme-danger" />;
    default: return <AlertCircle className="h-4 w-4 text-theme-muted" />;
  }
};

const getHealthScoreColor = (score: number) => {
  if (score >= 90) return 'text-theme-success';
  if (score >= 70) return 'text-theme-warning';
  return 'text-theme-danger';
};

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(amount);

const formatLatency = (ms: number) => ms < 1000 ? `${ms.toFixed(0)}ms` : `${(ms / 1000).toFixed(2)}s`;

export const ProviderHealthCard: React.FC<ProviderHealthCardProps> = ({
  provider,
  isSelected,
  timeRange,
  onSelect,
  onTestProvider,
  onViewDetails,
}) => (
  <Card
    className={cn(
      'cursor-pointer transition-all hover:shadow-md',
      isSelected && 'ring-2 ring-theme-primary'
    )}
    onClick={() => onSelect(isSelected ? null : provider.id)}
  >
    <CardHeader
      title={provider.name}
      icon={<Settings className="h-5 w-5" />}
      action={<Badge variant={getStatusBadgeVariant(provider.status)}>{provider.status}</Badge>}
      className="pb-3"
    />
    <CardContent className="space-y-4">
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-muted">Health Score</span>
        <span className={cn('font-medium', getHealthScoreColor(provider.health_score))}>
          {provider.health_score.toFixed(1)}%
        </span>
      </div>

      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-muted">Circuit Breaker</span>
        <div className="flex items-center gap-1">
          {getCircuitBreakerIcon(provider.circuit_breaker.state)}
          <span className="text-sm capitalize">{provider.circuit_breaker.state.replace('_', ' ')}</span>
        </div>
      </div>

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
          <span className="font-medium">{formatLatency(provider.performance.avg_response_time)}</span>
        </div>
        <div>
          <span className="text-theme-muted block">Executions</span>
          <span className="font-medium">{provider.usage.executions_count.toLocaleString()}</span>
        </div>
      </div>

      <div className="flex items-center justify-between text-sm">
        <span className="text-theme-muted">Cost ({timeRange})</span>
        <span className="font-medium">{formatCurrency(provider.usage.cost)}</span>
      </div>

      {provider.performance.error_rate > 0 && (
        <div className="flex items-center justify-between text-sm">
          <span className="text-theme-muted">Error Rate</span>
          <span className="text-theme-danger font-medium">{provider.performance.error_rate.toFixed(2)}%</span>
        </div>
      )}

      {provider.alerts.length > 0 && (
        <div className="flex items-center gap-2 p-2 bg-theme-danger/10 rounded border border-theme-danger/20">
          <AlertCircle className="h-4 w-4 text-theme-danger" />
          <span className="text-sm text-theme-danger">
            {provider.alerts.length} active alert{provider.alerts.length > 1 ? 's' : ''}
          </span>
        </div>
      )}

      <div className="pt-2 border-t border-theme flex gap-2">
        {onTestProvider && (
          <Button onClick={(e) => { e.stopPropagation(); onTestProvider(provider.id, {}); }} variant="outline" size="sm" className="flex-1">
            <TestTube className="h-4 w-4 mr-2" />
            Test
          </Button>
        )}
        {onViewDetails && (
          <Button onClick={(e) => { e.stopPropagation(); onViewDetails(provider.id); }} variant="outline" size="sm" className="flex-1">
            Details
          </Button>
        )}
      </div>
    </CardContent>
  </Card>
);
