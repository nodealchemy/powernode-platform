import React from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { RefreshCw, ShieldCheck, AlertTriangle } from 'lucide-react';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { Button } from '@/shared/components/ui/Button';
import { getErrorMessage } from '@/shared/utils/errorHandling';
import { monitoringApi, type ProviderCircuitBreakerState } from '@/shared/services/ai/MonitoringApiService';

const STATE_CONFIG: Record<string, { className: string; label: string }> = {
  closed: { className: 'bg-theme-success-bg text-theme-success-fg', label: 'Closed' },
  open: { className: 'bg-theme-error-bg text-theme-error-fg', label: 'Open' },
  half_open: { className: 'bg-theme-warning-bg text-theme-warning-fg', label: 'Half Open' },
};

const QUERY_KEY = ['monitoring', 'provider-circuit-breakers'] as const;

const BreakerRow: React.FC<{
  breaker: ProviderCircuitBreakerState;
  canReset: boolean;
  onRequestReset: (breaker: ProviderCircuitBreakerState) => void;
}> = ({ breaker, canReset, onRequestReset }) => {
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
            onClick={() => onRequestReset(breaker)}
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
 * ai.monitoring.manage, the same permission the reset endpoint enforces, and
 * confirms first — a reset re-admits traffic to a target that tripped the
 * breaker because it was failing.
 */
export const ProviderCircuitBreakersPanel: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const canReset = hasPermission('ai.monitoring.manage');
  const { data: breakers, isLoading, isError, error, refetch } = useQuery({
    queryKey: QUERY_KEY,
    queryFn: () => monitoringApi.getProviderCircuitBreakers(),
  });
  const queryClient = useQueryClient();
  const resetMutation = useMutation({
    mutationFn: (serviceName: string) => monitoringApi.resetProviderCircuitBreaker(serviceName),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: QUERY_KEY }),
    onError: (err: unknown) => {
      addNotification({
        type: 'error',
        title: 'Failed to reset circuit breaker',
        message: getErrorMessage(err),
      });
    },
  });
  const { confirm, ConfirmationDialog } = useConfirmation();

  const requestReset = (breaker: ProviderCircuitBreakerState) => {
    confirm({
      title: 'Reset Circuit Breaker',
      message: `This re-admits traffic to ${breaker.service_name}, which tripped because it was failing. Reset anyway?`,
      confirmLabel: 'Reset',
      variant: 'warning',
      // .mutate + onSettled, not .mutateAsync: the dialog closes once the
      // request settles either way (the toast, fired from onError above,
      // communicates a failure), and a failure never becomes an unhandled
      // rejection from this onClick handler (useConfirmation.handleConfirm
      // has no catch of its own).
      onConfirm: () =>
        new Promise<void>((resolve) => {
          resetMutation.mutate(breaker.service_name, { onSettled: () => resolve() });
        }),
    });
  };

  if (isLoading) return null;

  if (isError) {
    return (
      <div className="py-6 text-center text-theme-tertiary">
        <AlertTriangle className="w-10 h-10 mx-auto mb-2 text-theme-error-fg opacity-70" />
        <p className="text-sm text-theme-error-fg">{getErrorMessage(error)}</p>
        <Button variant="secondary" size="sm" className="mt-3" onClick={() => refetch()}>
          Try Again
        </Button>
      </div>
    );
  }

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
        <BreakerRow key={b.service_name} breaker={b} canReset={canReset} onRequestReset={requestReset} />
      ))}
      {closed.map((b) => (
        <BreakerRow key={b.service_name} breaker={b} canReset={canReset} onRequestReset={requestReset} />
      ))}
      {ConfirmationDialog}
    </div>
  );
};

export default ProviderCircuitBreakersPanel;
