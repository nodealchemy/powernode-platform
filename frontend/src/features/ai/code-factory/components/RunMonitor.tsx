import React from 'react';
import type { ReviewState } from '../types/codeFactory';
import { useCodeFactoryWebSocket } from '../hooks/useCodeFactoryWebSocket';

interface Props {
  reviewState: ReviewState;
}

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
  failed: -1,
  stale: -2,
};

export const RunMonitor: React.FC<Props> = ({ reviewState }) => {
  const { events } = useCodeFactoryWebSocket({ reviewStateId: reviewState.id });
  const currentIndex = STATUS_ORDER[reviewState.status] ?? 0;
  const isFailed = reviewState.status === 'stale' || reviewState.status === 'dirty';

  return (
    <div className="card-theme p-4 space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold text-theme-primary">
          Run Monitor — PR #{reviewState.pr_number}
        </h3>
        <span className="text-xs font-mono text-theme-secondary">
          {reviewState.head_sha?.substring(0, 8)}
        </span>
      </div>

      {/* Step Progress */}
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

      {/* Summary Stats */}
      <div className="grid grid-cols-4 gap-3 text-center">
        <div>
          <div className="text-lg font-semibold text-theme-primary">{reviewState.review_findings_count}</div>
          <div className="text-xs text-theme-secondary">Findings</div>
        </div>
        <div>
          <div className="text-lg font-semibold text-theme-primary">{reviewState.critical_findings_count}</div>
          <div className="text-xs text-theme-secondary">Critical</div>
        </div>
        <div>
          <div className="text-lg font-semibold text-theme-primary">{reviewState.remediation_attempts}</div>
          <div className="text-xs text-theme-secondary">Remediations</div>
        </div>
        <div>
          <div className="text-lg font-semibold text-theme-primary">{reviewState.bot_threads_resolved}</div>
          <div className="text-xs text-theme-secondary">Resolved</div>
        </div>
      </div>

      {/* Checks Progress */}
      {reviewState.required_checks.length > 0 && (
        <div className="space-y-1">
          <h4 className="text-xs font-medium text-theme-secondary">Required Checks</h4>
          <div className="flex flex-wrap gap-1">
            {reviewState.required_checks.map((check) => {
              const passed = reviewState.completed_checks.includes(check);
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

      {/* Recent Events */}
      {events.length > 0 && (
        <div className="space-y-1">
          <h4 className="text-xs font-medium text-theme-secondary">Recent Events</h4>
          <div className="space-y-1 max-h-32 overflow-y-auto">
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
    </div>
  );
};
