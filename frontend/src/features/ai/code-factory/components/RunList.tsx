import React, { useState, useEffect } from 'react';
import type { ReviewState } from '../types/codeFactory';
import { useCodeFactoryWebSocket } from '../hooks/useCodeFactoryWebSocket';

interface Props {
  reviewStates: ReviewState[];
  compact?: boolean;
  initialExpandedId?: string | null;
  onNavigateToContract?: (contractId: string) => void;
  onSelectRun?: (runId: string) => void;
}

const statusColors: Record<string, string> = {
  pending: 'bg-theme-secondary-bg text-theme-secondary',
  reviewing: 'bg-theme-info-bg text-theme-info',
  clean: 'bg-theme-success-bg text-theme-success',
  dirty: 'bg-theme-error-bg text-theme-error',
  stale: 'bg-theme-warning-bg text-theme-warning',
};

const tierColors: Record<string, string> = {
  low: 'text-theme-secondary',
  standard: 'text-theme-info',
  high: 'text-theme-warning',
  critical: 'text-theme-error',
};

const STEPS = [
  { key: 'preflight', label: 'Preflight' },
  { key: 'reviewing', label: 'Review' },
  { key: 'remediating', label: 'Remediation' },
  { key: 'verifying', label: 'Verify' },
  { key: 'evidence_capture', label: 'Evidence' },
  { key: 'completed', label: 'Complete' },
] as const;

const STATUS_ORDER: Record<string, number> = {
  pending: 0,
  preflight: 1,
  reviewing: 2,
  remediating: 3,
  verifying: 4,
  evidence_capture: 5,
  completed: 6,
  clean: 6,
  failed: -1,
  stale: -2,
  dirty: 2,
};

const RunCardExpanded: React.FC<{
  state: ReviewState;
  onNavigateToContract?: (contractId: string) => void;
}> = ({ state, onNavigateToContract }) => {
  const { events } = useCodeFactoryWebSocket({ reviewStateId: state.id });
  const currentIndex = STATUS_ORDER[state.status] ?? 0;
  const isFailed = state.status === 'stale' || state.status === 'dirty';

  return (
    <div className="border-t border-theme-border px-4 pb-4 space-y-4 pt-3">
      {/* Step Progress */}
      <div>
        <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Pipeline Progress</h5>
        <div className="flex items-center gap-1">
          {STEPS.map((step, idx) => {
            const isComplete = currentIndex > idx;
            const isCurrent = currentIndex === idx;
            return (
              <div key={step.key} className="flex-1">
                <div
                  className={`h-2 rounded-full transition-colors ${
                    isComplete
                      ? 'bg-theme-success'
                      : isCurrent
                      ? isFailed
                        ? 'bg-theme-error'
                        : 'bg-theme-accent animate-pulse'
                      : 'bg-theme-tertiary-bg'
                  }`}
                />
                <span className="text-[10px] text-theme-secondary mt-1 block text-center">
                  {step.label}
                </span>
              </div>
            );
          })}
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div className="bg-theme-secondary-bg rounded-lg p-2 text-center">
          <div className="text-lg font-semibold text-theme-primary">{state.review_findings_count}</div>
          <div className="text-[10px] text-theme-secondary">Findings</div>
        </div>
        <div className="bg-theme-secondary-bg rounded-lg p-2 text-center">
          <div className="text-lg font-semibold text-theme-error">{state.critical_findings_count}</div>
          <div className="text-[10px] text-theme-secondary">Critical</div>
        </div>
        <div className="bg-theme-secondary-bg rounded-lg p-2 text-center">
          <div className="text-lg font-semibold text-theme-primary">{state.remediation_attempts}</div>
          <div className="text-[10px] text-theme-secondary">Remediations</div>
        </div>
        <div className="bg-theme-secondary-bg rounded-lg p-2 text-center">
          <div className="text-lg font-semibold text-theme-primary">{state.bot_threads_resolved}</div>
          <div className="text-[10px] text-theme-secondary">Threads Resolved</div>
        </div>
      </div>

      {/* Required Checks */}
      {state.required_checks.length > 0 && (
        <div>
          <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Required Checks</h5>
          <div className="flex flex-wrap gap-1">
            {state.required_checks.map((check) => {
              const passed = state.completed_checks.includes(check);
              return (
                <span
                  key={check}
                  className={`px-2 py-0.5 rounded text-xs ${
                    passed
                      ? 'bg-theme-success-bg text-theme-success'
                      : 'bg-theme-secondary-bg text-theme-secondary'
                  }`}
                >
                  {passed ? '\u2713' : '\u25CB'} {check}
                </span>
              );
            })}
          </div>
        </div>
      )}

      {/* Evidence */}
      {state.evidence_manifests && state.evidence_manifests.length > 0 && (
        <div>
          <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Evidence Manifests</h5>
          <div className="flex flex-wrap gap-2">
            {state.evidence_manifests.map((m) => (
              <span key={m.id} className="text-xs bg-theme-secondary-bg rounded px-2 py-1">
                <span className="text-theme-primary capitalize">{m.manifest_type.replace(/_/g, ' ')}</span>
                <span className={`ml-2 ${m.status === 'verified' ? 'text-theme-success' : 'text-theme-secondary'}`}>
                  {m.status}
                </span>
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Related Contract Link */}
      {state.risk_contract && (
        <div className="flex items-center gap-2">
          <span className="text-xs text-theme-secondary">Contract:</span>
          {onNavigateToContract ? (
            <button
              onClick={() => onNavigateToContract(state.risk_contract_id)}
              className="text-xs text-theme-accent hover:underline"
            >
              {state.risk_contract.name}
            </button>
          ) : (
            <span className="text-xs text-theme-primary">{state.risk_contract.name}</span>
          )}
        </div>
      )}

      {/* Recent WebSocket Events */}
      {events.length > 0 && (
        <div>
          <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Live Events</h5>
          <div className="space-y-1 max-h-24 overflow-y-auto">
            {events.slice(-5).map((event, idx) => (
              <div key={idx} className="flex items-center gap-2 text-xs text-theme-secondary">
                <span className="font-mono text-theme-tertiary">
                  {new Date(event.timestamp).toLocaleTimeString()}
                </span>
                <span>{event.event}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Metadata footer */}
      <div className="flex items-center justify-between text-[10px] text-theme-secondary font-mono pt-2 border-t border-theme-border">
        <span>ID: {state.id}</span>
        <span>Updated: {new Date(state.updated_at).toLocaleString()}</span>
      </div>
    </div>
  );
};

export const RunList: React.FC<Props> = ({ reviewStates, compact, initialExpandedId, onNavigateToContract, onSelectRun }) => {
  const [expandedId, setExpandedId] = useState<string | null>(initialExpandedId ?? null);

  useEffect(() => {
    if (initialExpandedId) setExpandedId(initialExpandedId);
  }, [initialExpandedId]);

  if (reviewStates.length === 0) {
    return (
      <div className="text-center py-6 text-theme-secondary text-sm">
        No review states found.
      </div>
    );
  }

  const handleRowClick = (state: ReviewState) => {
    if (compact && onSelectRun) {
      onSelectRun(state.id);
    } else {
      setExpandedId(expandedId === state.id ? null : state.id);
    }
  };

  return (
    <div className="space-y-2">
      {reviewStates.map((state) => {
        const isExpanded = expandedId === state.id;

        return (
          <div key={state.id} className="card-theme overflow-hidden">
            <div
              className="p-3 flex items-center justify-between hover:bg-theme-hover transition-colors cursor-pointer"
              onClick={() => handleRowClick(state)}
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  {!compact && (
                    <span className={`transition-transform text-xs text-theme-secondary ${isExpanded ? 'rotate-90' : ''}`}>
                      {'\u25B6'}
                    </span>
                  )}
                  <span className="text-sm font-medium text-theme-primary">PR #{state.pr_number}</span>
                  <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusColors[state.status] || ''}`}>
                    {state.status}
                  </span>
                  {state.risk_tier && (
                    <span className={`text-xs font-medium capitalize ${tierColors[state.risk_tier] || 'text-theme-secondary'}`}>
                      {state.risk_tier}
                    </span>
                  )}
                </div>
                {!compact && (
                  <div className="flex items-center gap-3 mt-1 ml-5 text-xs text-theme-secondary">
                    <span className="font-mono">{state.head_sha?.substring(0, 8)}</span>
                    <span>{state.review_findings_count} findings</span>
                    <span>{state.remediation_attempts} remediations</span>
                    {state.risk_contract && <span className="text-theme-accent">{state.risk_contract.name}</span>}
                  </div>
                )}
              </div>
              <div className="flex items-center gap-2">
                {state.all_checks_passed && (
                  <span className="text-theme-success text-xs">{'\u2713'} Checks</span>
                )}
                {state.evidence_verified && (
                  <span className="text-theme-success text-xs">{'\u2713'} Evidence</span>
                )}
              </div>
            </div>

            {isExpanded && !compact && (
              <RunCardExpanded state={state} onNavigateToContract={onNavigateToContract} />
            )}
          </div>
        );
      })}
    </div>
  );
};
