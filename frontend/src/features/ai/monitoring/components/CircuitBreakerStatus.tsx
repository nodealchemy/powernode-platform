import React from 'react';
import { CheckCircle, Clock, AlertCircle, XCircle } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import type { ProviderMetrics } from '@/shared/types/monitoring';

interface CircuitBreakerStatusProps {
  provider: ProviderMetrics;
}

const getCircuitBreakerIcon = (state: string) => {
  switch (state) {
    case 'closed': return <CheckCircle className="h-4 w-4 text-theme-success" />;
    case 'half_open': return <Clock className="h-4 w-4 text-theme-warning" />;
    case 'open': return <XCircle className="h-4 w-4 text-theme-danger" />;
    default: return <AlertCircle className="h-4 w-4 text-theme-muted" />;
  }
};

const formatLatency = (ms: number) => ms < 1000 ? `${ms.toFixed(0)}ms` : `${(ms / 1000).toFixed(2)}s`;

export const CircuitBreakerStatus: React.FC<CircuitBreakerStatusProps> = ({ provider }) => (
  <div className="space-y-4">
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
        <p className="text-xl font-bold text-theme-primary">{provider.circuit_breaker.failure_count}</p>
      </div>
      <div className="p-4 bg-theme-surface rounded">
        <p className="text-xs text-theme-muted">Success Threshold</p>
        <p className="text-xl font-bold text-theme-primary">{provider.circuit_breaker.success_threshold}</p>
      </div>
      <div className="p-4 bg-theme-surface rounded">
        <p className="text-xs text-theme-muted">Timeout</p>
        <p className="text-xl font-bold text-theme-primary">{provider.circuit_breaker.timeout}s</p>
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
  </div>
);
