import React from 'react';
import { VerdictBadge } from '@/shared/components/ui/VerdictBadge';
import type { ComponentStatusSummary } from '@/shared/types/platformStatus';

// The right rail: three lists that answer "what must I decide, what is the
// platform doing, and what has it given up on" (design §6).
//
// EVERY LIST IS DERIVED FROM `remediation.state`, which A5 computes server-side
// from SignalState / RemediationOutcome / ApprovalRequest and the lane binding.
// The page never infers a remediation state from a verdict: "down" says nothing
// about whether anyone is acting on it, and a rail that guessed would be
// telling the operator a story the platform never told it.
//
// "In progress" spans TWO facts on purpose: a component whose remediation state
// is `auto_in_progress` (a lane is acting) and one whose VERDICT is
// `progressing` (something is provisioning or converging, whether or not a
// remediation lane owns it). Both mean "work is happening, wait"; separating
// them would give the operator two lists to check for one question. A row that
// is both appears once.

export interface RailBucket {
  id: string;
  title: string;
  /** Why these rows are in this bucket. Rendered, not just commented. */
  basis: string;
  rows: ComponentStatusSummary[];
  emptyLabel: string;
}

export const buildRailBuckets = (rows: ComponentStatusSummary[]): RailBucket[] => [
  {
    id: 'needs-decision',
    title: 'Needs a decision',
    basis: 'Remediation is parked at an approval request. It will not proceed without you.',
    rows: rows.filter((row) => row.remediation_state === 'awaiting_operator'),
    emptyLabel: 'Nothing is waiting on you.',
  },
  {
    id: 'in-progress',
    title: 'In progress',
    basis: 'A lane is acting, or the component is provisioning or converging on its own.',
    rows: rows.filter(
      (row) => row.remediation_state === 'auto_in_progress' || row.verdict === 'progressing'
    ),
    emptyLabel: 'Nothing is in flight.',
  },
  {
    id: 'stuck',
    title: 'Stuck',
    basis: 'Remediation started and did not finish. These need a person to look.',
    rows: rows.filter((row) => row.remediation_state === 'stuck'),
    emptyLabel: 'Nothing is stuck.',
  },
];

export interface RemediationRailProps {
  rows: ComponentStatusSummary[];
  selectedId?: string | null;
  onSelect?: (row: ComponentStatusSummary) => void;
}

export const RemediationRail: React.FC<RemediationRailProps> = ({ rows, selectedId, onSelect }) => (
  <div className="flex flex-col gap-4">
    {buildRailBuckets(rows).map((bucket) => (
      <section
        key={bucket.id}
        data-rail-bucket={bucket.id}
        // Named region (C2 review L3): without `aria-labelledby` a <section> is
        // not exposed as a landmark at all, so a screen-reader user gets three
        // unlabelled lists and no way to tell which is "Needs a decision".
        aria-labelledby={`rail-${bucket.id}-title`}
        className="rounded-lg border border-theme bg-theme-surface p-3"
      >
        <header className="flex items-baseline justify-between gap-2">
          <h3 id={`rail-${bucket.id}-title`} className="text-sm font-medium text-theme-primary">
            {bucket.title}
          </h3>
          <span className="text-xs text-theme-tertiary" title={bucket.basis}>
            {/* The count's basis is repeated as visible text below rather than
                living only in a title attribute, which screen readers surface
                inconsistently. */}
            {bucket.rows.length}
          </span>
        </header>
        <p className="mt-1 text-xs text-theme-tertiary">{bucket.basis}</p>

        {bucket.rows.length === 0 ? (
          <p className="mt-2 text-xs text-theme-secondary">{bucket.emptyLabel}</p>
        ) : (
          <ul aria-label={bucket.title} className="mt-2 flex flex-col gap-1">
            {bucket.rows.map((row) => (
              <li key={row.id}>
                <button
                  type="button"
                  onClick={() => onSelect?.(row)}
                  aria-pressed={selectedId === row.id}
                  className="w-full flex items-center justify-between gap-2 rounded px-2 py-1 text-left hover:bg-theme-surface-hover"
                >
                  <span className="truncate text-xs text-theme-primary">
                    {row.display_name || row.component_ref}
                  </span>
                  <VerdictBadge
                    verdict={row.verdict}
                    size="xs"
                    withLabel={false}
                    labelPrefix={row.display_name || row.component_ref}
                  />
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    ))}
  </div>
);

export default RemediationRail;
