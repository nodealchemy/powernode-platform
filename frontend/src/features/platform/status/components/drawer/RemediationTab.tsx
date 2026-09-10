import React from 'react';
import { Link } from 'react-router-dom';
import { RemediationChip } from '@/features/platform/status/components/RemediationChip';
import type { ComponentRemediation, RemediationState } from '@/shared/types/platformStatus';

// What the platform is doing about this component, and what it is waiting on.
//
// Every field here is DERIVED server-side (A5) from SignalState,
// RemediationOutcome, ApprovalRequest and the lane binding. A contributor never
// hand-writes them, and this panel never infers one from a verdict: "down" says
// nothing about whether a lane owns the problem.
//
// `not_actuatable` is the state most likely to be misread, so it says its
// meaning out loud rather than relying on the chip: no lane is bound to this
// signal kind, so nothing will happen without a person. A blank panel would
// read as "handled".

const StateExplanation: React.FC<{ state: RemediationState }> = ({ state }) => {
  const text: Record<RemediationState, string | null> = {
    none: 'No signal is open for this component, so no lane has been asked to act.',
    auto_in_progress: 'A lane is acting on this now, under its own gate and budget.',
    awaiting_operator:
      'A remediation is parked at an approval request. It will not proceed until a person decides.',
    stuck: 'Remediation started and did not finish. This one needs a person to look.',
    remediated: 'A lane acted and the component recovered.',
    not_actuatable:
      'No remediation lane is bound to this signal kind. Nothing will happen automatically — this is an honest gap, not an error.',
  };
  const explanation = text[state];
  if (!explanation) return null;
  return <p className="text-sm text-theme-secondary">{explanation}</p>;
};

const Field: React.FC<{ label: string; title: string; children: React.ReactNode }> = ({
  label,
  title,
  children,
}) => (
  <>
    <dt className="text-xs text-theme-tertiary" title={title}>
      {label}
    </dt>
    <dd className="text-xs text-theme-secondary break-all">{children}</dd>
  </>
);

export interface RemediationTabProps {
  remediation: ComponentRemediation;
  state: RemediationState;
}

export const RemediationTab: React.FC<RemediationTabProps> = ({ remediation, state }) => (
  <div className="flex flex-col gap-4" data-remediation-state={state}>
    <div className="flex items-center gap-2">
      <RemediationChip state={state} size="sm" />
    </div>

    <StateExplanation state={state} />

    <dl className="grid grid-cols-[minmax(0,auto)_minmax(0,1fr)] gap-x-3 gap-y-2">
      {remediation.signal_kind && (
        <Field
          label="Signal kind"
          title="The signal a lane would be routed on. This is the registry key Platform::Remediation::Registry matches."
        >
          <code>{remediation.signal_kind}</code>
        </Field>
      )}
      {remediation.fingerprint && (
        <Field
          label="Fingerprint"
          title="Identifies this occurrence, so a repeat of the same problem is not filed as a new one."
        >
          <code>{remediation.fingerprint}</code>
        </Field>
      )}
      {remediation.last_outcome && (
        <Field label="Last outcome" title="What the lane reported the last time it acted.">
          {remediation.last_outcome}
        </Field>
      )}
      {remediation.stuck === true && (
        <Field
          label="Stuck"
          title="The lane reported it could not finish. The component is not being worked on."
        >
          yes
        </Field>
      )}
    </dl>

    {state === 'awaiting_operator' && remediation.approval_request_id && (
      // The link exists only in the state that has something to decide. An
      // approval link on a component nobody is waiting on would invite a click
      // that leads nowhere.
      <Link
        to="/app/ai/agents/autonomy"
        state={{ approvalRequestId: remediation.approval_request_id }}
        className="text-sm text-theme-info-fg underline"
      >
        Open the approval request
      </Link>
    )}

    {state === 'awaiting_operator' && !remediation.approval_request_id && (
      // Said out loud rather than rendering nothing: "waiting on you" with no
      // way to get there is a dead end an operator would otherwise hunt for.
      <p className="text-xs text-theme-warning-fg">
        This component is waiting on a decision, but no approval request id was reported. Check the
        approvals queue directly.
      </p>
    )}
  </div>
);

export default RemediationTab;
