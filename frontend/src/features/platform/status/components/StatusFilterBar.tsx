import React from 'react';
import { VERDICT_LADDER, type Verdict } from '@/shared/types/platformStatus';

// The three filters, and the reason the middle one is not a checkbox.
//
// ── THE ENVIRONMENT FILTER IS THREE-VALUED (design §4.6) ───────────────────
//
// Most core kinds carry NO environment: an AI provider, a circuit breaker and
// the platform's own subsystems are not "in dev" or "in prod". So a plane
// filter has three cases, not two:
//
//   ALL_PLANES     (no param)   every row — in-plane, plane-less, every plane
//   PLANE_LESS     ('none')     the plane-less rows ONLY
//   <environment>  (an id)      that plane PLUS the plane-less ones, never another's
//
// The third case is the one a naive `where(environment_id: x)` gets wrong by
// dropping the plane-less rows, and a `where.not` gets wrong by showing
// another plane's. The server owns that logic; this control's only job is to
// send the right one of the three, and to never send a fourth thing.
//
// ── WHY THE PLANE OPTIONS ARE RAW IDS ──────────────────────────────────────
//
// Core exposes no REST index of `Ai::Environment`, and the component-status
// serializer carries `environment_id` but no slug or name. So the only labels
// available to this control are the ids observed on rows. They are shortened
// for display and carried in full in the title attribute. This is a genuine
// gap, not a style choice: it is fixed by the serializer carrying
// `environment_slug`, or by core exposing an environments read. Recorded in the
// C2 report rather than papered over with a hardcoded slug list, which would
// go stale the moment an account adds a plane.

export const ALL_PLANES = '';
export const PLANE_LESS = 'none';

export interface StatusFilterValue {
  kind: string;
  verdict: string;
  /** '' = all planes, 'none' = plane-less only, otherwise an environment id. */
  environment: string;
}

export interface StatusFilterBarProps {
  value: StatusFilterValue;
  onChange: (next: StatusFilterValue) => void;
  /** Distinct kinds to offer. Derived from what the server has actually reported. */
  kinds: string[];
  /** Every environment id seen this session — a union, never the current response's set. */
  environmentIds: string[];
  /** True when the named plane does not exist for this account. */
  unknownEnvironment: boolean;
}

const selectClass =
  'rounded-md border border-theme bg-theme-surface text-theme-primary px-3 py-2 text-sm ' +
  'focus:outline-none focus:ring-2 focus:ring-theme-info-fg';

const shortenId = (id: string) => (id.length > 12 ? `${id.slice(0, 8)}…` : id);

export const StatusFilterBar: React.FC<StatusFilterBarProps> = ({
  value,
  onChange,
  kinds,
  environmentIds,
  unknownEnvironment,
}) => (
  <div className="flex flex-wrap items-end gap-3">
    <label className="flex flex-col gap-1">
      <span className="text-xs text-theme-tertiary">Kind</span>
      <select
        aria-label="Filter by component kind"
        className={selectClass}
        value={value.kind}
        onChange={(e) => onChange({ ...value, kind: e.target.value })}
      >
        <option value="">All kinds</option>
        {kinds.map((kind) => (
          <option key={kind} value={kind}>
            {kind}
          </option>
        ))}
      </select>
    </label>

    <label className="flex flex-col gap-1">
      <span className="text-xs text-theme-tertiary">Verdict</span>
      <select
        aria-label="Filter by verdict"
        className={selectClass}
        value={value.verdict}
        onChange={(e) => onChange({ ...value, verdict: e.target.value })}
      >
        <option value="">All verdicts</option>
        {VERDICT_LADDER.map((verdict: Verdict) => (
          <option key={verdict} value={verdict}>
            {verdict}
          </option>
        ))}
      </select>
    </label>

    <label className="flex flex-col gap-1">
      <span className="text-xs text-theme-tertiary">Plane</span>
      <select
        aria-label="Filter by environment plane"
        className={selectClass}
        value={value.environment}
        onChange={(e) => onChange({ ...value, environment: e.target.value })}
      >
        <option value={ALL_PLANES}>All planes</option>
        <option value={PLANE_LESS}>Plane-less only</option>
        {environmentIds.map((id) => (
          <option key={id} value={id} title={id}>
            {shortenId(id)}
          </option>
        ))}
      </select>
    </label>

    {unknownEnvironment && (
      // An empty page under a plane nobody has is not the same answer as an
      // empty plane. Both render zero cards; only one is a mistake.
      <p className="text-xs text-theme-warning-fg" role="status">
        That plane does not exist for this account — no components were matched.
      </p>
    )}
  </div>
);

export default StatusFilterBar;
