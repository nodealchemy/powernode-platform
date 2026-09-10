import React from 'react';
import { VerdictBadge } from '@/shared/components/ui/VerdictBadge';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';
import type { ComponentStatusRollupData, StatusRollup } from '@/shared/types/platformStatus';

// The header answers "is the platform all right", once, with its basis
// attached (design §6: every number carries its basis).
//
// ── THE ROLLUP IS COMPUTED TWICE, AND SO IS THIS HEADER ────────────────────
//
// `rollup.verdict` is the operational verdict over the NON-held components;
// `rollup.held_count` is carried beside it. That is the whole point of the dual
// rollup: a planned drain must never turn this header amber, while the drained
// component's own card still tells the truth. So the held count is rendered as
// a separate, calm statement, never folded into the verdict.
//
// `held_count` and `counts_by_verdict` DISAGREE on purpose — a cordoned-and-down
// node counts once under `down` and once in the held count — so the two are
// never presented as parts of one total.
//
// ── SHARED INFRASTRUCTURE IS ITS OWN VERDICT ───────────────────────────────
//
// A NULL-account row describes process-wide infrastructure belonging to no
// tenant. The server rolls those up separately and this renders them
// separately. Summing them would turn one shared circuit breaker into every
// tenant's outage.

const RollupFigure: React.FC<{
  label: string;
  rollup: StatusRollup;
  basis: string;
}> = ({ label, rollup, basis }) => (
  <div className="flex flex-col gap-1" title={basis}>
    <span className="text-xs uppercase tracking-wide text-theme-tertiary">{label}</span>
    <div className="flex items-center gap-2">
      <VerdictBadge verdict={rollup.verdict} size="md" labelPrefix={label} />
      <span className="text-sm text-theme-secondary">
        {rollup.total} component{rollup.total === 1 ? '' : 's'}
      </span>
    </div>
    <div className="flex flex-wrap gap-x-3 text-xs text-theme-tertiary">
      {rollup.held_count > 0 && (
        <span title="Components an operator has cordoned, paused or drained. Counted here and EXCLUDED from the verdict above, so a planned drain does not read as an outage. A held component that is also down is counted in both places.">
          {rollup.held_count} held by intent
        </span>
      )}
      {(['down', 'degraded', 'not_measured'] as const).map((verdict) =>
        rollup.counts_by_verdict[verdict] > 0 ? (
          <span key={verdict} title={`Components whose derived verdict is ${verdict}.`}>
            {rollup.counts_by_verdict[verdict]} {verdict.replace('_', ' ')}
          </span>
        ) : null
      )}
    </div>
  </div>
);

export interface StatusRollupHeaderProps {
  rollup: ComponentStatusRollupData | null;
  loading: boolean;
  isConnected: boolean;
  lastLoadedAt: Date | null;
  /** Rows currently rendered, and the server's total for the same filters. */
  loadedCount: number;
  totalCount: number;
  pollMs: number;
}

export const StatusRollupHeader: React.FC<StatusRollupHeaderProps> = ({
  rollup,
  loading,
  isConnected,
  lastLoadedAt,
  loadedCount,
  totalCount,
  pollMs,
}) => {
  if (loading && !rollup) {
    return <div className="text-sm text-theme-secondary">Loading platform status…</div>;
  }

  if (!rollup) {
    // Explicitly NOT "everything is fine". A rollup we could not read is a
    // rollup we could not read.
    return <div className="text-sm text-theme-secondary">No rollup available.</div>;
  }

  return (
    <div className="rounded-lg border border-theme bg-theme-surface p-4">
      <div className="flex flex-wrap gap-8">
        <RollupFigure
          label="This account"
          rollup={rollup.rollup}
          basis="The worst verdict over this account's components, EXCLUDING the ones held by operator intent. Shared infrastructure is not counted here."
        />
        {rollup.shared.total > 0 && (
          <RollupFigure
            label="Shared infrastructure"
            rollup={rollup.shared}
            basis="Process-wide components with no tenant. Rolled up separately and never summed into the account verdict — one shared breaker is not every tenant's outage."
          />
        )}
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-theme-tertiary">
        <span
          title={
            isConnected
              ? 'Live: transitions arrive over PlatformStatusChannel. The fallback poll is stopped while this holds.'
              : `Not live: the fallback poll is re-reading every ${Math.round(pollMs / 1000)} seconds.`
          }
        >
          {isConnected ? 'live' : `polling every ${Math.round(pollMs / 1000)}s`}
        </span>
        {lastLoadedAt && (
          <span title={`Last full read at ${lastLoadedAt.toISOString()}.`}>
            read {formatRelativeTimeCompact(lastLoadedAt)}
          </span>
        )}
        {rollup.observed_at && (
          <span title={`The server computed this rollup at ${rollup.observed_at}.`}>
            rolled up {formatRelativeTimeCompact(rollup.observed_at)}
          </span>
        )}
        {totalCount > loadedCount && (
          // Said out loud rather than left to be inferred from a short grid.
          <span title="The server has more matching components than this page loaded. Narrow the filters to see the rest.">
            showing {loadedCount} of {totalCount}
          </span>
        )}
      </div>
    </div>
  );
};

export default StatusRollupHeader;
