import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { Loader2, CheckCircle, XCircle, Repeat, Circle, ChevronDown, ChevronRight } from 'lucide-react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { logger } from '@/shared/utils/logger';

export type ProvisioningStepStatus = 'pending' | 'running' | 'completed' | 'failed' | 'rolled_back';

export interface PlanStep {
  id: string;
  label: string;
  description?: string;
  status?: ProvisioningStepStatus;
  outputs?: Record<string, unknown>;
  error?: string | null;
}

export interface StepProgressStreamProps {
  missionId: string;
  steps: PlanStep[];
  onAllComplete?: () => void;
  onStepFailed?: (stepId: string, error: string) => void;
}

interface StepRuntimeState {
  status: ProvisioningStepStatus;
  outputs?: Record<string, unknown>;
  error?: string | null;
  updatedAt: string;
}

interface StepEventPayload {
  mission_id: string;
  step_id: string;
  status: ProvisioningStepStatus;
  outputs?: Record<string, unknown>;
  error?: string | null;
}

interface MissionPhaseEvent {
  mission_id: string;
  phase: string;
  current_step?: string;
}

const STATUS_ICON_CLS: Record<ProvisioningStepStatus, string> = {
  pending: 'text-theme-secondary',
  running: 'text-theme-info-fg animate-spin',
  completed: 'text-theme-success-fg',
  failed: 'text-theme-danger-fg',
  rolled_back: 'text-theme-warning-fg',
};

function StatusIcon({ status }: { status: ProvisioningStepStatus }) {
  const cls = `h-4 w-4 ${STATUS_ICON_CLS[status]}`;
  switch (status) {
    case 'running':
      return <Loader2 className={cls} aria-label="Running" data-testid="step-icon-running" />;
    case 'completed':
      return <CheckCircle className={cls} aria-label="Completed" data-testid="step-icon-completed" />;
    case 'failed':
      return <XCircle className={cls} aria-label="Failed" data-testid="step-icon-failed" />;
    case 'rolled_back':
      return <Repeat className={cls} aria-label="Rolled back" data-testid="step-icon-rolled_back" />;
    case 'pending':
    default:
      return <Circle className={cls} aria-label="Pending" data-testid="step-icon-pending" />;
  }
}

function formatTimestamp(iso: string): string {
  try {
    const d = new Date(iso);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  } catch {
    return '';
  }
}

/**
 * Live step-by-step status from MissionChannel WebSocket events.
 *
 * Listens for:
 *   - `provisioning_step_changed` { mission_id, step_id, status, outputs?, error? }
 *   - `mission_phase_changed`     { mission_id, phase, current_step? }
 */
export const StepProgressStream: React.FC<StepProgressStreamProps> = ({
  missionId,
  steps,
  onAllComplete,
  onStepFailed,
}) => {
  const { subscribe, isConnected } = useWebSocket();
  const [runtime, setRuntime] = useState<Record<string, StepRuntimeState>>(() =>
    Object.fromEntries(
      steps.map((s) => [
        s.id,
        {
          status: s.status ?? 'pending',
          outputs: s.outputs,
          error: s.error ?? null,
          updatedAt: new Date().toISOString(),
        },
      ])
    )
  );
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const allCompleteFiredRef = useRef(false);
  const failedFiredRef = useRef<Set<string>>(new Set());

  // Reset runtime when initial steps change (new plan)
  useEffect(() => {
    setRuntime(
      Object.fromEntries(
        steps.map((s) => [
          s.id,
          {
            status: s.status ?? 'pending',
            outputs: s.outputs,
            error: s.error ?? null,
            updatedAt: new Date().toISOString(),
          },
        ])
      )
    );
    allCompleteFiredRef.current = false;
    failedFiredRef.current = new Set();
  }, [steps]);

  useEffect(() => {
    if (!isConnected || !missionId) return;

    const unsub = subscribe({
      channel: 'MissionChannel',
      params: { mission_id: missionId },
      onMessage: (raw: unknown) => {
        const evt = raw as { event?: string; payload?: unknown } & Record<string, unknown>;
        const eventName = (evt.event as string | undefined) ?? '';

        if (eventName === 'provisioning_step_changed') {
          const payload = (evt.payload ?? evt) as StepEventPayload;
          if (!payload?.step_id) return;
          if (payload.mission_id && payload.mission_id !== missionId) return;

          setRuntime((prev) => ({
            ...prev,
            [payload.step_id]: {
              status: payload.status,
              outputs: payload.outputs,
              error: payload.error ?? null,
              updatedAt: new Date().toISOString(),
            },
          }));

          if (payload.status === 'failed' && payload.error && onStepFailed) {
            if (!failedFiredRef.current.has(payload.step_id)) {
              failedFiredRef.current.add(payload.step_id);
              onStepFailed(payload.step_id, payload.error);
            }
          }
        } else if (eventName === 'mission_phase_changed') {
          const payload = (evt.payload ?? evt) as MissionPhaseEvent;
          logger.debug('mission_phase_changed', {
            mission_id: payload.mission_id,
            phase: payload.phase,
            current_step: payload.current_step,
          });
        }
      },
      onError: (err) => logger.warn('MissionChannel error', { err }),
    });

    return () => {
      if (unsub) unsub();
    };
  }, [isConnected, missionId, subscribe, onStepFailed]);

  // Fire onAllComplete once when every step is completed
  useEffect(() => {
    if (steps.length === 0) return;
    const allDone = steps.every((s) => runtime[s.id]?.status === 'completed');
    if (allDone && !allCompleteFiredRef.current && onAllComplete) {
      allCompleteFiredRef.current = true;
      onAllComplete();
    }
  }, [runtime, steps, onAllComplete]);

  const completedCount = useMemo(
    () => steps.filter((s) => runtime[s.id]?.status === 'completed').length,
    [steps, runtime]
  );

  const progressPct = steps.length === 0 ? 0 : Math.round((completedCount / steps.length) * 100);

  const toggleExpand = useCallback((stepId: string) => {
    setExpanded((prev) => ({ ...prev, [stepId]: !prev[stepId] }));
  }, []);

  return (
    <div
      className="flex flex-col gap-3 bg-theme-surface border border-theme rounded-lg p-4"
      data-testid="step-progress-stream"
    >
      {/* Aggregate progress bar */}
      <div className="space-y-1.5" data-testid="step-progress-bar">
        <div className="flex items-center justify-between text-xs text-theme-secondary">
          <span className="font-medium text-theme-primary">
            {completedCount} of {steps.length} steps
          </span>
          <span className="tabular-nums">{progressPct}%</span>
        </div>
        <div
          className="h-2 w-full rounded-full bg-theme-background-secondary overflow-hidden"
          role="progressbar"
          aria-valuenow={progressPct}
          aria-valuemin={0}
          aria-valuemax={100}
        >
          <div
            className="h-full bg-theme-interactive-primary transition-all duration-300 ease-out"
            style={{ width: `${progressPct}%` }}
          />
        </div>
      </div>

      {/* Step list */}
      <ol className="flex flex-col gap-2" data-testid="step-list">
        {steps.map((step) => {
          const state = runtime[step.id] ?? {
            status: step.status ?? 'pending',
            error: step.error ?? null,
            outputs: step.outputs,
            updatedAt: new Date().toISOString(),
          };
          const isFailed = state.status === 'failed';
          const isRolled = state.status === 'rolled_back';
          const isExpandable = !!state.error || (state.outputs && Object.keys(state.outputs).length > 0);
          const isExpanded = !!expanded[step.id];

          return (
            <li
              key={step.id}
              data-testid={`step-${step.id}`}
              data-status={state.status}
              className={`flex flex-col gap-1 px-3 py-2 rounded-md border ${
                isFailed
                  ? 'border-theme-danger-border/30 bg-theme-danger-fg/10'
                  : isRolled
                    ? 'border-theme-warning-border/30 bg-theme-warning-fg/10'
                    : 'border-theme bg-theme-background-secondary'
              }`}
            >
              <div className="flex items-center gap-2">
                <StatusIcon status={state.status} />
                <span className="flex-1 text-sm font-medium text-theme-primary truncate">
                  {step.label}
                </span>
                <span className="text-[10px] text-theme-secondary tabular-nums shrink-0">
                  {formatTimestamp(state.updatedAt)}
                </span>
                {isExpandable && (
                  <button
                    type="button"
                    onClick={() => toggleExpand(step.id)}
                    className="p-1 rounded hover:bg-theme-surface text-theme-secondary"
                    aria-label={isExpanded ? 'Collapse details' : 'Expand details'}
                    aria-expanded={isExpanded}
                    data-testid={`step-toggle-${step.id}`}
                  >
                    {isExpanded ? (
                      <ChevronDown className="h-4 w-4" />
                    ) : (
                      <ChevronRight className="h-4 w-4" />
                    )}
                  </button>
                )}
              </div>

              {step.description && (
                <p className="text-xs text-theme-secondary pl-6">{step.description}</p>
              )}

              {isExpandable && isExpanded && (
                <div className="pl-6 pt-1 space-y-2" data-testid={`step-details-${step.id}`}>
                  {state.error && (
                    <pre className="text-xs whitespace-pre-wrap break-words rounded bg-theme-danger-fg/10 text-theme-danger-fg p-2 border border-theme-danger-border/30">
                      {state.error}
                    </pre>
                  )}
                  {state.outputs && Object.keys(state.outputs).length > 0 && (
                    <pre className="text-[11px] whitespace-pre-wrap break-words rounded bg-theme-surface p-2 border border-theme text-theme-primary">
                      {JSON.stringify(state.outputs, null, 2)}
                    </pre>
                  )}
                </div>
              )}
            </li>
          );
        })}
      </ol>
    </div>
  );
};

export default StepProgressStream;
