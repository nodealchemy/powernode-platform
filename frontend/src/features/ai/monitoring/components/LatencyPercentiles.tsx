import React from 'react';
import type { ProviderMetrics } from '@/shared/types/monitoring';
import { cn } from '@/shared/utils/cn';

interface LatencyPercentilesProps {
  provider: ProviderMetrics;
}

const formatLatency = (ms: number) => ms < 1000 ? `${ms.toFixed(0)}ms` : `${(ms / 1000).toFixed(2)}s`;

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(amount);

export const LatencyPercentiles: React.FC<LatencyPercentilesProps> = ({ provider }) => (
  <div className="space-y-4">
    <div className="grid grid-cols-4 gap-4">
      <div className="p-4 bg-theme-surface rounded">
        <p className="text-xs text-theme-tertiary">Success Rate</p>
        <p className="text-xl font-bold text-theme-primary">{provider.performance.success_rate.toFixed(2)}%</p>
      </div>
      <div className="p-4 bg-theme-surface rounded">
        <p className="text-xs text-theme-tertiary">Avg Response Time</p>
        <p className="text-xl font-bold text-theme-primary">{formatLatency(provider.performance.avg_response_time)}</p>
      </div>
      <div className="p-4 bg-theme-surface rounded">
        <p className="text-xs text-theme-tertiary">Throughput</p>
        <p className="text-xl font-bold text-theme-primary">{provider.performance.throughput.toFixed(1)}/min</p>
      </div>
      <div className="p-4 bg-theme-surface rounded">
        <p className="text-xs text-theme-tertiary">Error Rate</p>
        <p className={cn('text-xl font-bold', provider.performance.error_rate > 5 ? 'text-theme-danger-fg' : 'text-theme-success-fg')}>
          {provider.performance.error_rate.toFixed(2)}%
        </p>
      </div>
    </div>

    <div className="grid grid-cols-3 gap-4">
      <div className="p-4 bg-theme-surface rounded">
        <p className="text-xs text-theme-tertiary">Total Executions</p>
        <p className="text-xl font-bold text-theme-primary">{provider.usage.executions_count.toLocaleString()}</p>
      </div>
      <div className="p-4 bg-theme-surface rounded">
        <p className="text-xs text-theme-tertiary">Tokens Consumed</p>
        <p className="text-xl font-bold text-theme-primary">{provider.usage.tokens_consumed.toLocaleString()}</p>
      </div>
      <div className="p-4 bg-theme-surface rounded">
        <p className="text-xs text-theme-tertiary">Total Cost</p>
        <p className="text-xl font-bold text-theme-primary">{formatCurrency(provider.usage.cost)}</p>
      </div>
    </div>
  </div>
);
