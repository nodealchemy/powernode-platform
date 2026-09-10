import React from 'react';
import { icons } from 'lucide-react';
import { VerdictBadge } from '@/shared/components/ui/VerdictBadge';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';
import { RemediationChip } from '@/features/platform/status/components/RemediationChip';
import type { ComponentStatusSummary } from '@/shared/types/platformStatus';

// One component, rendered WITHOUT the page knowing its kind (design §4.4). The
// icon, the label and the grouping all come out of the row's `presentation`
// blob, which a contributor wrote; core learns nothing kind-specific, and a new
// kind is a new contributor file with no frontend edit.
//
// ── THE ICON IS A STRING ───────────────────────────────────────────────────
//
// `presentation.icon` is a Lucide icon NAME, resolved here at render time. That
// is deliberate and is the same convention `NavigationItem` already uses for
// extension-registered nav items: an extension that shipped a React icon
// COMPONENT would have to import from core's node_modules and would pin core's
// lucide version, so the registry passes a name across the seam instead. An
// unknown name falls back to `Puzzle` rather than rendering nothing — a card
// with no icon reads as a rendering bug, which sends the operator looking in
// the wrong place.
//
// ── WHAT THIS CARD CANNOT SHOW ─────────────────────────────────────────────
//
// The list serializer carries the worst failing condition's `reason` TOKEN and
// a `condition_count`, but not the condition's human `message` — that lives in
// the detail payload the drawer fetches (C3). So the card shows the token,
// labelled as a token, and says how many conditions there are. It does not
// paraphrase: a reason is a stable, greppable string that a runbook and an
// alert key on, and prettifying it here would break the one property it has.

const resolveIcon = (name?: string): React.ComponentType<{ className?: string }> => {
  if (!name) return icons.Puzzle;
  return icons[name as keyof typeof icons] ?? icons.Puzzle;
};

export interface ComponentStatusCardProps {
  row: ComponentStatusSummary;
  selected?: boolean;
  /** C3 hangs the drawer off this. C2 wires the plumbing and opens nothing. */
  onSelect?: (row: ComponentStatusSummary) => void;
}

export const ComponentStatusCard: React.FC<ComponentStatusCardProps> = ({
  row,
  selected = false,
  onSelect,
}) => {
  const Icon = resolveIcon(row.presentation?.icon);
  const name = row.display_name || row.component_ref;
  const kindLabel = row.presentation?.label || row.component_kind;

  return (
    <button
      type="button"
      onClick={() => onSelect?.(row)}
      data-component-kind={row.component_kind}
      data-component-ref={row.component_ref}
      data-plane={row.plane}
      aria-pressed={selected}
      className={[
        'w-full text-left rounded-lg border p-4 transition-colors',
        'bg-theme-surface hover:bg-theme-surface-hover',
        selected ? 'border-theme-focus' : 'border-theme',
      ].join(' ')}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3 min-w-0">
          <Icon className="w-5 h-5 mt-0.5 shrink-0 text-theme-secondary" />
          <div className="min-w-0">
            <div className="truncate font-medium text-theme-primary">{name}</div>
            <div className="truncate text-xs text-theme-secondary">{kindLabel}</div>
          </div>
        </div>
        <VerdictBadge verdict={row.verdict} labelPrefix={name} />
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-2">
        {row.reason && (
          <code
            className="text-xs text-theme-secondary"
            title="Reason token of the worst failing condition. Stable and greppable — open the component for the human message."
          >
            {row.reason}
          </code>
        )}
        <RemediationChip state={row.remediation_state} />
      </div>

      <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-theme-tertiary">
        {/* Every number carries its basis: what was measured, and when. */}
        <span title={`Conditions this component reports (${row.condition_count} in total).`}>
          {row.condition_count} condition{row.condition_count === 1 ? '' : 's'}
        </span>
        <span
          title={
            row.observed_at
              ? `Observed at ${row.observed_at} — the SOURCE's measurement time, not the sweep's.`
              : 'No observation time reported by this contributor.'
          }
        >
          {row.observed_at ? `observed ${formatRelativeTimeCompact(row.observed_at)}` : 'never observed'}
        </span>
        {/* A cordoned-and-down node reads verdict `down` and held_by_intent true.
            The two are different questions, so the drain is stated separately
            rather than replacing the verdict. */}
        {row.held_by_intent && row.verdict !== 'held' && (
          <span
            className="text-theme-info-fg"
            title="An operator has cordoned, paused or drained this. Its verdict is what it would be regardless."
          >
            held by intent
          </span>
        )}
        {row.plane === 'none' && (
          <span title="This component belongs to no environment. It rides along in every plane-filtered view rather than being hidden by one.">
            plane-less
          </span>
        )}
        {row.scope === 'shared' && (
          <span title="Process-wide infrastructure with no tenant. Never counted in this account's operational verdict.">
            shared
          </span>
        )}
      </div>
    </button>
  );
};

export default ComponentStatusCard;
