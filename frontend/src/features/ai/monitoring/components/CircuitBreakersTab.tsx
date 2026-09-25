import React from 'react';
import { Zap, ShieldCheck, XCircle, CheckCircle2 } from 'lucide-react';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { CircuitBreakerStatusPanel } from '@/features/ai/autonomy/components/CircuitBreakerStatusPanel';
import { useAiOpsRecentErrors } from '@/features/ai/aiops';
import { formatTimestamp } from '@/features/ai/aiops/components/aiopsHelpers';
import { ProviderCircuitBreakersPanel } from './ProviderCircuitBreakersPanel';

/**
 * CircuitBreakersTab — the Observability hub's Circuit Breakers tab (fc-42).
 *
 * Combines the two circuit-breaker surfaces the consolidation plan (Tier 3,
 * "Circuit breakers x3") found scattered across three places under distinct
 * labels: agent breakers (Ai::CircuitBreaker, per-agent, resettable — reused
 * from Autonomy → Security's CircuitBreakerStatusPanel, not duplicated) and
 * provider breakers (Ai::CircuitBreakerRegistry, shared, resettable — the
 * live registry that actually gates Ai::Llm::Client calls). Each half is
 * gated on the permission its OWN backend endpoint enforces — a viewer can
 * hold one without the other:
 *   - Ai::AutonomyController#circuit_breakers -> ai.agents.read
 *   - Api::V1::Ai::MonitoringController#circuit_breakers_category -> ai.monitoring.read
 *
 * The AIOps recent-errors feed (previously bundled into ReliabilitySection
 * alongside a now-superseded breaker table) lives here too, since this is
 * where a viewer investigating a tripped breaker would look next.
 */
export const CircuitBreakersTab: React.FC = () => {
  const { hasPermission } = usePermissions();
  const canViewAgentBreakers = hasPermission('ai.agents.read');
  const canViewProviderBreakers = hasPermission('ai.monitoring.read');
  const recentErrorsQuery = useAiOpsRecentErrors();
  const recentErrors = canViewProviderBreakers ? (recentErrorsQuery.data ?? []) : [];

  if (!canViewAgentBreakers && !canViewProviderBreakers) {
    return (
      <div className="py-6 text-center text-theme-tertiary">
        <CheckCircle2 className="w-10 h-10 mx-auto mb-2 opacity-30" />
        <p className="text-sm">You don&apos;t have permission to view circuit breakers.</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {canViewAgentBreakers && (
        <section>
          <h3 className="text-lg font-semibold text-theme-primary mb-3 flex items-center gap-2">
            <Zap className="h-5 w-5" />
            Agent Circuit Breakers
          </h3>
          <CircuitBreakerStatusPanel />
        </section>
      )}

      {canViewProviderBreakers && (
        <section>
          <h3 className="text-lg font-semibold text-theme-primary mb-3 flex items-center gap-2">
            <ShieldCheck className="h-5 w-5" />
            Provider Circuit Breakers
          </h3>
          <ProviderCircuitBreakersPanel />
        </section>
      )}

      {recentErrors.length > 0 && (
        <section>
          <h3 className="text-lg font-semibold text-theme-primary mb-3 flex items-center gap-2">
            <XCircle className="h-5 w-5 text-theme-error-fg" />
            Recent Errors
          </h3>
          <div className="space-y-2">
            {recentErrors.map((err, idx) => (
              <div key={`${err.execution_id}-${idx}`} className="bg-theme-error-bg border border-theme-error-border rounded-lg p-3">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="text-sm font-medium text-theme-error-fg">{err.agent_name || 'Unknown agent'}</p>
                    <p className="text-sm text-theme-secondary mt-1">{err.error}</p>
                  </div>
                  <span className="text-xs text-theme-tertiary whitespace-nowrap">{formatTimestamp(err.failed_at)}</span>
                </div>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
};

export default CircuitBreakersTab;
