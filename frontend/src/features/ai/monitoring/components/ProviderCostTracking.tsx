import React from 'react';
import {
  Activity,
  AlertTriangle,
  CheckCircle,
  Clock,
  DollarSign,
  Hash,
  XCircle,
  Zap,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { cn } from '@/shared/utils/cn';

interface AggregateStats {
  totalProviders: number;
  healthyCount: number;
  degradedCount: number;
  unhealthyCount: number;
  avgHealthScore: number;
  totalCost: number;
  totalExecutions: number;
  avgSuccessRate: number;
  avgLatency: number;
  circuitBreakersClosed: number;
  circuitBreakersOpen: number;
  circuitBreakersHalfOpen: number;
  totalAlerts: number;
}

interface ProviderCostTrackingProps {
  aggregateStats: AggregateStats;
  section: 'summary' | 'status';
}

const getHealthScoreColor = (score: number) => {
  if (score >= 90) return 'text-theme-success';
  if (score >= 70) return 'text-theme-warning';
  return 'text-theme-danger';
};

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(amount);

const formatLatency = (ms: number) => ms < 1000 ? `${ms.toFixed(0)}ms` : `${(ms / 1000).toFixed(2)}s`;

export const ProviderCostTracking: React.FC<ProviderCostTrackingProps> = ({ aggregateStats, section }) => {
  if (section === 'summary') {
    return (
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
                <p className="text-2xl font-bold text-theme-primary">{formatLatency(aggregateStats.avgLatency)}</p>
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
                <p className="text-2xl font-bold text-theme-primary">{aggregateStats.totalExecutions.toLocaleString()}</p>
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
                <p className="text-2xl font-bold text-theme-primary">{formatCurrency(aggregateStats.totalCost)}</p>
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
  }

  // Status overview
  return (
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
};
