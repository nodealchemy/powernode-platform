import React from 'react';
import { Zap, RefreshCw } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { useCircuitBreakers, useResetCircuitBreaker } from '../api/autonomyApi';
import type { CircuitBreaker } from '../types/autonomy';

const STATE_CONFIG: Record<string, { variant: 'success' | 'warning' | 'default'; label: string }> = {
  closed: { variant: 'success', label: 'Closed' },
  open: { variant: 'default', label: 'Open' },
  half_open: { variant: 'warning', label: 'Half Open' },
};

const BreakerRow: React.FC<{ breaker: CircuitBreaker }> = ({ breaker }) => {
  const resetMutation = useResetCircuitBreaker();
  const stateConfig = STATE_CONFIG[breaker.state] || STATE_CONFIG.closed;

  return (
    <div className="flex items-center justify-between p-3 rounded-lg bg-theme-surface border border-theme-border">
      <div className="flex items-center gap-3">
        <Zap className={`h-4 w-4 ${breaker.state === 'open' ? 'text-theme-error' : 'text-theme-success'}`} />
        <div>
          <span className="text-sm font-medium text-theme-primary">{breaker.agent_name}</span>
          <span className="text-xs text-theme-muted ml-2">({breaker.action_type})</span>
          <div className="text-xs text-theme-muted mt-0.5">
            Failures: {breaker.failure_count}/{breaker.failure_threshold}
          </div>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <Badge variant={stateConfig.variant} size="sm">{stateConfig.label}</Badge>
        {breaker.state !== 'closed' && (
          <button
            onClick={() => resetMutation.mutate(breaker.id)}
            disabled={resetMutation.isPending}
            className="p-1 rounded hover:bg-theme-bg-secondary text-theme-muted hover:text-theme-primary"
            title="Reset circuit breaker"
          >
            <RefreshCw className="h-3.5 w-3.5" />
          </button>
        )}
      </div>
    </div>
  );
};

export const CircuitBreakerStatusPanel: React.FC = () => {
  const { data: breakers, isLoading } = useCircuitBreakers();

  if (isLoading) return null;

  const tripped = breakers?.filter(b => b.state !== 'closed') ?? [];
  const closed = breakers?.filter(b => b.state === 'closed') ?? [];

  return (
    <Card>
      <CardHeader title={`Circuit Breakers (${tripped.length} tripped)`} />
      <CardContent>
        {breakers && breakers.length > 0 ? (
          <div className="space-y-2">
            {tripped.map(b => <BreakerRow key={b.id} breaker={b} />)}
            {closed.map(b => <BreakerRow key={b.id} breaker={b} />)}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-muted">
            <Zap className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No circuit breakers registered</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
