import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';
import type {
  ApprovalDecisionRecord,
  ApprovalStepStatus,
  ApproverSpec,
} from '@/features/platform/status/components/approvals/approvalChainTypes';

// The approval CHAIN, step by step (C3b, checklist row 33). New capability: the
// absorbed ApprovalQueuePanel never showed it, although every request has
// carried `current_step` and `step_statuses` all along.
//
// ── A STEP NOBODY HAS REACHED IS NOT "PENDING" ──────────────────────────────
//
// `initialize_step_statuses` writes `status: "pending"` on EVERY step at
// creation, and only the current step is actually waiting on anyone. Rendering
// the raw value would show a three-step chain as three things awaiting a
// decision. So the state shown is derived from position as well as status:
// the current step of a pending request reads "awaiting decision", a later one
// reads "not reached", and a pending step on a request that is no longer
// pending (expired, cancelled) reads "not decided" — each a different fact.

type BadgeVariant = NonNullable<React.ComponentProps<typeof Badge>['variant']>;

export type StepState =
  | 'approved'
  | 'rejected'
  | 'delegated'
  | 'current'
  | 'not_reached'
  | 'undecided'
  | 'unknown';

const STEP_PRESENTATION: Record<StepState, { label: string; variant: BadgeVariant }> = {
  approved: { label: 'approved', variant: 'success' },
  rejected: { label: 'rejected', variant: 'danger' },
  delegated: { label: 'delegated', variant: 'info' },
  current: { label: 'awaiting decision', variant: 'warning' },
  not_reached: { label: 'not reached', variant: 'outline' },
  undecided: { label: 'not decided', variant: 'outline' },
  // Rendered with the server's own word, not this label (see below).
  unknown: { label: 'unknown', variant: 'outline' },
};

export const deriveStepState = (
  step: ApprovalStepStatus,
  index: number,
  currentStep: number,
  requestStatus: string
): StepState => {
  switch (step.status) {
    // Explicit literals: the status union is open (string & {}), so returning
    // `step.status` would not narrow to StepState.
    case 'approved':
      return 'approved';
    case 'rejected':
      return 'rejected';
    case 'delegated':
      return 'delegated';
    case 'pending':
      if (requestStatus !== 'pending') return 'undecided';
      if (index === currentStep) return 'current';
      if (index > currentStep) return 'not_reached';
      // A pending step BEHIND the current one should not exist; say so rather
      // than calling it current.
      return 'undecided';
    default:
      return 'unknown';
  }
};

const shortId = (id: string) => (id.length > 12 ? `${id.slice(0, 8)}…` : id);

/** Human form of an approver spec. Display only — never an access decision. */
export const describeApprover = (spec: ApproverSpec): string => {
  if (spec === '*') return 'any active user';
  if (typeof spec === 'string') return `user ${shortId(spec)}`;
  switch (spec.type) {
    case 'permission':
      return `anyone with ${spec.value}`;
    case 'role':
      return `role ${spec.value}`;
    case 'user':
      return `user ${shortId(spec.value)}`;
    default:
      return `${spec.type} ${spec.value}`;
  }
};

export interface ApprovalChainStepsProps {
  stepStatuses: ApprovalStepStatus[];
  currentStep: number;
  requestStatus: string;
  decisions?: ApprovalDecisionRecord[];
}

export const ApprovalChainSteps: React.FC<ApprovalChainStepsProps> = ({
  stepStatuses,
  currentStep,
  requestStatus,
  decisions = [],
}) => {
  if (stepStatuses.length === 0) {
    // Not a fabricated single step: a request whose chain reported no steps is
    // a fact worth seeing, because `can_approve?` refuses everyone on it.
    return (
      <p data-approval-chain="empty" className="text-xs text-theme-warning-fg">
        This request reported no chain steps, so no one can approve it from here.
      </p>
    );
  }

  const total = stepStatuses.length;

  return (
    <div data-approval-chain>
      <p className="text-xs text-theme-tertiary">
        {requestStatus === 'pending'
          ? `Step ${currentStep + 1} of ${total} is awaiting a decision.`
          : `${total}-step chain. The request is ${requestStatus}.`}
      </p>
      <ol aria-label="Approval chain steps" className="mt-2 flex flex-col gap-2">
        {stepStatuses.map((step, index) => {
          const state = deriveStepState(step, index, currentStep, requestStatus);
          const presentation = STEP_PRESENTATION[state];
          const stepDecisions = decisions.filter((decision) => decision.step_number === index);
          const approvers = step.approvers ?? [];

          return (
            <li
              key={index}
              data-step={index}
              data-step-state={state}
              aria-current={state === 'current' ? 'step' : undefined}
              className="rounded-md border border-theme p-3"
            >
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-medium text-theme-primary">
                  Step {index + 1}: {step.step_name || 'Unnamed step'}
                </span>
                <Badge variant={presentation.variant} size="xs">
                  {state === 'unknown' ? String(step.status) : presentation.label}
                </Badge>
              </div>
              <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-theme-secondary">
                <span
                  title="Approvals recorded on this step, against the number it needs."
                >
                  {step.current_approvals ?? 0} of {step.required_approvals ?? 1} approvals
                </span>
                {approvers.length > 0 && (
                  <span>Approvers: {approvers.map(describeApprover).join(', ')}</span>
                )}
              </div>
              {stepDecisions.length > 0 && (
                <ul aria-label={`Decisions on step ${index + 1}`} className="mt-2 flex flex-col gap-1">
                  {stepDecisions.map((decision) => (
                    <li key={decision.id} className="text-xs text-theme-secondary">
                      <span className="font-medium text-theme-primary">{decision.decision}</span>{' '}
                      <span title={decision.created_at}>
                        {formatRelativeTimeCompact(decision.created_at)}
                      </span>
                      {decision.comments && <span>: {decision.comments}</span>}
                    </li>
                  ))}
                </ul>
              )}
            </li>
          );
        })}
      </ol>
    </div>
  );
};

/**
 * The collapsed card's one line of chain position, from the LIST payload
 * (`current_step`, `total_steps`) so it costs no extra read. Nothing for a
 * single-step request — "step 1 of 1" is noise on the common case.
 */
export const ApprovalStepSummary: React.FC<{
  currentStep?: number | null;
  totalSteps?: number | null;
  status: string;
}> = ({ currentStep, totalSteps, status }) => {
  if (!totalSteps || totalSteps < 2 || currentStep == null) return null;
  return (
    <span data-step-summary className="text-xs text-theme-tertiary">
      {status === 'pending' ? `Step ${currentStep + 1} of ${totalSteps}` : `${totalSteps}-step chain`}
    </span>
  );
};

export default ApprovalChainSteps;
