import type { ProposalHandoff, ProposalStatus } from '../types/autonomy';

/** Every status the Proposals filter offers, in lifecycle order. */
export const PROPOSAL_STATUS_OPTIONS: ReadonlyArray<{ value: ProposalStatus; label: string }> = [
  { value: 'pending_review', label: 'Pending Review' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
  { value: 'implemented', label: 'Implemented' },
  { value: 'withdrawn', label: 'Withdrawn' },
  { value: 'expired', label: 'Expired' },
];

export function proposalStatusLabel(status: ProposalStatus): string {
  return PROPOSAL_STATUS_OPTIONS.find((o) => o.value === status)?.label ?? status.replace(/_/g, ' ');
}

/** The line under an expanded, no-longer-pending proposal. */
export function proposalOutcomeNote(status: ProposalStatus): string {
  switch (status) {
    case 'withdrawn': return 'The filing agent withdrew this proposal.';
    case 'expired': return 'This proposal expired: its review deadline passed with no decision.';
    default: return `This proposal has been ${status}.`;
  }
}

/** What approval did, in words. An acknowledgement-only handoff says nothing was started. */
export function proposalHandoffLabel(handoff: ProposalHandoff | null | undefined): string | null {
  if (!handoff) return null;
  if (handoff.acknowledged_only) return 'Acknowledged only: nothing was started';
  return handoff.label;
}
