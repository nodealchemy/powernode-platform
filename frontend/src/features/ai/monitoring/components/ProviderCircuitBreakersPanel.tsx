import React from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { RefreshCw, ShieldCheck } from 'lucide-react';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { monitoringApi, type ProviderCircuitBreakerState } from '@/shared/services/ai/MonitoringApiService';

const STATE_CONFIG: Record<string, { className: string; label: string }> = {
  closed: { className: 'bg-theme-success-bg text-theme-success-fg', label: 'Closed' },
  open: { className: 'bg-theme-error-bg text-theme-error-fg', label: 'Open' },
  half_open: { className: 'bg-theme-warning-bg text-theme-warning-fg', label: 'Half Open' },
};

const QUERY_KEY = ['monitoring', 'provider-circuit-breakers'] as const;

const BreakerRow: React.FC<{ breaker: ProviderCircuitBreakerState; canReset: boolean }> = ({ breaker, canReset }) => {
  const queryClient = useQueryClient();
  const resetMutation = useMutation({
    mutationFn: () => monitoringApi.resetProviderCircuitBreaker(breaker.service_name),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: QUERY_KEY }),
  });
  const stateConfig = STATE_CONFIG[breaker.state] ?? STATE_CONFIG.closed;

  return (
    <div className="flex items-center justify-between p-3 rounded-lg bg-theme-surface border border-theme">
      <div>
        <span className="text-sm font-medium capitalize">{breaker.service_name}</span>
        <div className="text-xs text-theme-tertiary mt-0.5">
          Consecutive failures: {breaker.consecutive_failures}
        </div>
      </div>
      <div className="flex items-center gap-2">
        <span className={`text-xs font-medium px-2 py-0.5 rounded ${stateConfig.className}`}>{stateConfig.label}</span>
        {canReset && breaker.state !== 'closed' && (
          <button
            onClick={() => resetMutation.mutate()}
            disabled={resetMutation.isPending}
            className="p-1 rounded hover:bg-theme-background-secondary text-theme-tertiary hover:text-theme-primary"
            title={`Reset ${breaker.service_name} circuit breaker`}
          >
            <RefreshCw className="h-3.5 w-3.5" />
          </button>
        )}
      </div>
    </div>
  );
};

/**
 * The "provider" half of the Observability Circuit Breakers tab —
 * Ai::CircuitBreakerRegistry's `ai_providers` category, read live via
 * MonitoringApiService.getProviderCircuitBreakers (fc-42: replaces the old
 * ReliabilitySection table, which read a stale Ai::ProviderMetric snapshot
 * instead of the registry actually gating provider calls).
 *
 * These breakers are SHARED across every account on the node (keyed by
 * provider TYPE — "openai", "anthropic" — not by a per-account row), matching
 * how Ai::Llm::Client actually uses the registry. Reset is gated on
 * ai.monitoring.manage, the same permission the reset endpoint enforces.
 */
export const ProviderCircuitBreakersPanel: React.FC = () => {
  const { hasPermission } = usePermissions();
  const canReset = hasPermission('ai.monitoring.manage');
  const { data: breakers, isLoading } = useQuery({
    queryKey: QUERY_KEY,
    queryFn: () => monitoringApi.getProviderCircuitBreakers(),
  });

  if (isLoading) return null;

  const tripped = (breakers ?? []).filter((b) => b.state !== 'closed');
  const closed = (breakers ?? []).filter((b) => b.state === 'closed');

  if (!breakers || breakers.length === 0) {
    return (
      <div className="py-6 text-center text-theme-tertiary">
        <ShieldCheck className="w-10 h-10 mx-auto mb-2 opacity-30" />
        <p className="text-sm">No provider circuit breakers registered</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {tripped.map((b) => (
        <BreakerRow key={b.service_name} breaker={b} canReset={canReset} />
      ))}
      {closed.map((b) => (
        <BreakerRow key={b.service_name} breaker={b} canReset={canReset} />
      ))}
    </div>
  );
};

export default ProviderCircuitBreakersPanel;
