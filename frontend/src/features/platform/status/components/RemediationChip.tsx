import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';
import type { RemediationState } from '@/shared/types/platformStatus';

// What the platform is doing about a component, in one chip (design §6: the
// page answers "what is unhealthy, why, what the platform is doing about it,
// and what I must decide").
//
// The table is a `Record<RemediationState, …>` with no default branch, for the
// reason VerdictBadge's is: A5 derives these states server-side from
// SignalState / RemediationOutcome / ApprovalRequest, and a seventh state
// added there must break `tsc` here rather than render as nothing.
//
// `not_actuatable` is an HONEST answer, not an error state: no lane is bound to
// this component's signal kind, so nothing is going to happen without a person.
// It gets the same dashed outline `not_measured` gets, because it is the same
// kind of fact — a gap in coverage rather than a failure — and rendering it as
// a calm grey would read as "handled".

interface ChipPresentation {
  variant: NonNullable<React.ComponentProps<typeof Badge>['variant']>;
  label: string;
  className?: string;
  /** Why this chip is on this card, for the title attribute. Every state states its basis. */
  basis: string;
}

export const REMEDIATION_PRESENTATION: Record<RemediationState, ChipPresentation | null> = {
  // Nothing to say. A chip reading "none" is noise on every healthy card, and
  // noise on every card is how the four that matter stop being seen.
  none: null,
  auto_in_progress: {
    variant: 'primary',
    label: 'Remediating',
    basis: 'A lane is acting on this now, under its own gate.',
  },
  awaiting_operator: {
    variant: 'warning',
    label: 'Needs a decision',
    basis: 'A remediation is parked at an approval request. It will not proceed without you.',
  },
  stuck: {
    variant: 'danger',
    label: 'Stuck',
    basis: 'Remediation started and did not finish. This one needs a person to look.',
  },
  remediated: {
    variant: 'success',
    label: 'Remediated',
    basis: 'A lane acted and the component recovered.',
  },
  not_actuatable: {
    variant: 'outline',
    label: 'Not actuatable',
    className: 'border-dashed',
    basis: 'No remediation lane is bound to this signal kind. Nothing will happen automatically.',
  },
};

export interface RemediationChipProps {
  state: RemediationState;
  size?: NonNullable<React.ComponentProps<typeof Badge>['size']>;
}

export const RemediationChip: React.FC<RemediationChipProps> = ({ state, size = 'xs' }) => {
  const presentation = REMEDIATION_PRESENTATION[state];
  if (!presentation) return null;

  return (
    <span title={presentation.basis} data-remediation={state}>
      <Badge variant={presentation.variant} size={size} className={presentation.className}>
        {presentation.label}
      </Badge>
    </span>
  );
};

export default RemediationChip;
