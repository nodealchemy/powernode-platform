import React from 'react';
import { Zap, RefreshCw, AlertTriangle } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { EntityLink } from '@/shared/components/entity';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { getErrorMessage } from '@/shared/utils/errorHandling';
import { useCircuitBreakers, useResetCircuitBreaker } from '../api/autonomyApi';
import type { CircuitBreaker } from '../types/autonomy';

const STATE_CONFIG: Record<string, { variant: 'success' | 'warning' | 'default'; label: string }> = {
  closed: { variant: 'success', label: 'Closed' },
  open: { variant: 'default', label: 'Open' },
  half_open: { variant: 'warning', label: 'Half Open' },
};

const BreakerRow: React.FC<{
  breaker: CircuitBreaker;
  canReset: boolean;
  onRequestReset: (breaker: CircuitBreaker) => void;
}> = ({ breaker, canReset, onRequestReset }) => {
  const stateConfig = STATE_CONFIG[breaker.state] || STATE_CONFIG.closed;

  return (
    <div className="flex items-center justify-between p-3 rounded-lg bg-theme-surface border border-theme">
      <div className="flex items-center gap-3">
        <Zap className={`h-4 w-4 ${breaker.state === 'open' ? 'text-theme-error-fg' : 'text-theme-success-fg'}`} />
        <div>
          <EntityLink type="agent" id={breaker.agent_id} label={breaker.agent_name} className="text-sm font-medium" />
          <span className="text-xs text-theme-tertiary ml-2">({breaker.action_type})</span>
          <div className="text-xs text-theme-tertiary mt-0.5">
            Failures: {breaker.failure_count}/{breaker.failure_threshold}
          </div>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <Badge variant={stateConfig.variant} size="sm">{stateConfig.label}</Badge>
        {canReset && breaker.state !== 'closed' && (
          <button
            onClick={() => onRequestReset(breaker)}
            className="p-1 rounded hover:bg-theme-background-secondary text-theme-tertiary hover:text-theme-primary"
            title="Reset circuit breaker"
          >
            <RefreshCw className="h-3.5 w-3.5" />
          </button>
        )}
      </div>
    </div>
  );
};

/**
 * fc-42 review fix: the reset button used to render whenever the endpoint's
 * OWN read permission (implicitly, whatever gates this panel's mount) let a
 * viewer see the panel, but Ai::AutonomyController's reset_circuit_breaker
 * action requires ai.autonomy.manage — a strictly narrower permission. A
 * viewer who could see tripped breakers but not reset them saw a button that
 * 403'd. Gated on ai.autonomy.manage now, matching the endpoint exactly.
 *
 * A reset re-admits traffic to a target the breaker tripped BECAUSE it was
 * failing — the same class of action as the provider breaker's reset
 * (ProviderCircuitBreakersPanel), which already confirms. This one now does
 * too, via the shared useConfirmation hook.
 *
 * fc-42 re-review: mirrors ProviderCircuitBreakersPanel's error handling — a
 * failed load used to fall through to the same "No circuit breakers
 * registered" copy as a genuinely empty, successful response, and a failed
 * reset closed the confirmation dialog with no feedback at all.
 */
export const CircuitBreakerStatusPanel: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const canReset = hasPermission('ai.autonomy.manage');
  const { data: breakers, isLoading, isError, error, refetch } = useCircuitBreakers();
  const resetMutation = useResetCircuitBreaker();
  const { confirm, ConfirmationDialog } = useConfirmation();

  const requestReset = (breaker: CircuitBreaker) => {
    confirm({
      title: 'Reset Circuit Breaker',
      message: `This re-admits traffic to ${breaker.agent_name} (${breaker.action_type}), which tripped because it was failing. Reset anyway?`,
      confirmLabel: 'Reset',
      variant: 'warning',
      // .mutate + onSettled, not .mutateAsync: the dialog closes once the
      // request settles either way, and a failure never becomes an unhandled
      // rejection from this onClick handler (useConfirmation.handleConfirm
      // has no catch of its own). The toast, fired below on error, is what
      // tells the operator the reset didn't actually happen.
      onConfirm: () =>
        new Promise<void>((resolve) => {
          resetMutation.mutate(breaker.id, {
            onError: (err) => {
              addNotification({
                type: 'error',
                title: 'Failed to reset circuit breaker',
                message: getErrorMessage(err),
              });
            },
            onSettled: () => resolve(),
          });
        }),
    });
  };

  if (isLoading) return null;

  if (isError) {
    return (
      <Card>
        <CardContent>
          <div className="py-6 text-center text-theme-tertiary">
            <AlertTriangle className="w-10 h-10 mx-auto mb-2 text-theme-error-fg opacity-70" />
            <p className="text-sm text-theme-error-fg">{getErrorMessage(error)}</p>
            <Button variant="secondary" size="sm" className="mt-3" onClick={() => refetch()}>
              Try Again
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  const tripped = breakers?.filter(b => b.state !== 'closed') ?? [];
  const closed = breakers?.filter(b => b.state === 'closed') ?? [];

  return (
    <Card>
      <CardHeader title={`Circuit Breakers (${tripped.length} tripped)`} />
      <CardContent>
        {breakers && breakers.length > 0 ? (
          <div className="space-y-2">
            {tripped.map(b => (
              <BreakerRow key={b.id} breaker={b} canReset={canReset} onRequestReset={requestReset} />
            ))}
            {closed.map(b => (
              <BreakerRow key={b.id} breaker={b} canReset={canReset} onRequestReset={requestReset} />
            ))}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-tertiary">
            <Zap className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No circuit breakers registered</p>
          </div>
        )}
      </CardContent>
      {ConfirmationDialog}
    </Card>
  );
};
