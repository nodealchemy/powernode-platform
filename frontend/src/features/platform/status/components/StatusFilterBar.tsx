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
// ── PLANE OPTIONS ARE LABELLED BY NAME, WHERE THE WIRE CARRIES ONE ─────────
//
// C2 had only `environment_id` on the wire and shipped raw (shortened) ids here,
// recorded as a gap rather than papered over with a hardcoded slug list. A4b
// closed it: rows now carry `environment_name` / `environment_slug`, which the
// hook accumulates into `environmentLabels`. An option shows its plane's NAME.
//
// The shortened id survives in exactly one case — an in-plane id the server
// sent no name for, which only an A4b-predating server can produce — because an
// option must render SOMETHING and the id is the only true thing available.
// The full id always stays in the title attribute. The value sent to the server
// is always the id: names are for people, and the door resolves ids.

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
  /** id → plane name, from A4b. Absent entries fall back to the shortened id. */
  environmentLabels?: Record<string, string>;
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
  environmentLabels = {},
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
            {environmentLabels[id] ?? shortenId(id)}
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
