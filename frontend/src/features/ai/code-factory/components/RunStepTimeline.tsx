import React from 'react';
import type { ReviewState } from '../types/codeFactory';

interface Props {
  reviewState: ReviewState;
}

interface TimelineStep {
  label: string;
  status: 'completed' | 'active' | 'pending' | 'failed';
  detail?: string;
}

function buildTimeline(state: ReviewState): TimelineStep[] {
  const steps: TimelineStep[] = [];
  const statusMap: Record<string, number> = {
    pending: 0, reviewing: 1, clean: 3, dirty: 2, stale: -1,
  };
  const current = statusMap[state.status] ?? 0;

  steps.push({
    label: 'Preflight Gate',
    status: current > 0 ? 'completed' : current === 0 ? 'active' : 'pending',
    detail: state.risk_tier ? `Risk tier: ${state.risk_tier}` : undefined,
  });

  steps.push({
    label: 'Code Review',
    status: current > 1 ? 'completed' : current === 1 ? 'active' : 'pending',
    detail: state.review_findings_count > 0 ? `${state.review_findings_count} findings` : undefined,
  });

  if (state.remediation_attempts > 0 || state.status === 'dirty') {
    steps.push({
      label: 'Remediation',
      status: state.status === 'dirty' ? 'active' : 'completed',
      detail: `${state.remediation_attempts} attempt(s)`,
    });
  }

  steps.push({
    label: 'Verification',
    status: state.all_checks_passed ? 'completed' : current >= 2 ? 'active' : 'pending',
    detail: `${state.completed_checks.length}/${state.required_checks.length} checks`,
  });

  if (state.evidence_verified || state.evidence_manifests?.length) {
    steps.push({
      label: 'Evidence',
      status: state.evidence_verified ? 'completed' : 'active',
      detail: state.evidence_manifests ? `${state.evidence_manifests.length} manifest(s)` : undefined,
    });
  }

  steps.push({
    label: 'Merge Ready',
    status: state.status === 'clean' ? 'completed' : 'pending',
  });

  return steps;
}

const statusIcons: Record<string, { icon: string; color: string }> = {
  completed: { icon: '\u2713', color: 'text-theme-success bg-theme-success-bg' },
  active: { icon: '\u25CF', color: 'text-theme-accent bg-theme-accent/10' },
  pending: { icon: '\u25CB', color: 'text-theme-secondary bg-theme-secondary-bg' },
  failed: { icon: '\u2717', color: 'text-theme-error bg-theme-error-bg' },
};

export const RunStepTimeline: React.FC<Props> = ({ reviewState }) => {
  const steps = buildTimeline(reviewState);

  return (
    <div className="card-theme p-4">
      <h3 className="text-sm font-semibold text-theme-primary mb-4">
        Timeline — PR #{reviewState.pr_number}
      </h3>
      <div className="space-y-3">
        {steps.map((step, idx) => {
          const { icon, color } = statusIcons[step.status];
          return (
            <div key={idx} className="flex items-start gap-3">
              <div className="flex flex-col items-center">
                <span className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-medium ${color}`}>
                  {icon}
                </span>
                {idx < steps.length - 1 && (
                  <div className={`w-px h-6 ${step.status === 'completed' ? 'bg-theme-success' : 'bg-theme-border'}`} />
                )}
              </div>
              <div className="flex-1 min-w-0 pb-1">
                <div className="text-sm font-medium text-theme-primary">{step.label}</div>
                {step.detail && (
                  <div className="text-xs text-theme-secondary">{step.detail}</div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
