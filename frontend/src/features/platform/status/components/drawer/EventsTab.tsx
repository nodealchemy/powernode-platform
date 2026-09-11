import React from 'react';
import { VerdictBadge } from '@/shared/components/ui/VerdictBadge';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';
import type { ComponentStatusEvent, Verdict } from '@/shared/types/platformStatus';

// The component's transition history, newest first (A9 §4.3).
//
// ── BOTH NULLS ARE MEANINGFUL ──────────────────────────────────────────────
//
// A null `from_verdict` is a FIRST SIGHTING: the sweep saw this component for
// the first time and it had no prior state. A null `to_verdict` is a REMOVAL:
// the component was reaped, so there is no verdict to move to. Rendering either
// as a blank cell — or worse, as "unknown" — turns two facts an operator needs
// during an incident into a rendering glitch.

const Endpoint: React.FC<{ verdict: Verdict | null; missingLabel: string; title: string }> = ({
  verdict,
  missingLabel,
  title,
}) =>
  verdict ? (
    <VerdictBadge verdict={verdict} size="xs" labelPrefix={title} />
  ) : (
    <span className="text-xs italic text-theme-tertiary" title={title}>
      {missingLabel}
    </span>
  );

export interface EventsTabProps {
  events: ComponentStatusEvent[];
  loading: boolean;
  /** Server-side total, which may exceed the page loaded. */
  totalCount: number;
  /**
   * The read failed or was malformed. Nothing is known — which is a different
   * fact from "no transitions", and is said as one (C3p2 review R2).
   */
  failed?: boolean;
}

export const EventsTab: React.FC<EventsTabProps> = ({
  events,
  loading,
  totalCount,
  failed = false,
}) => {
  if (loading && events.length === 0) {
    return <p className="text-sm text-theme-secondary">Loading events…</p>;
  }

  if (failed) {
    return (
      <p data-events-failed className="text-sm text-theme-warning-fg">
        Could not load this component&apos;s transition history. Nothing is known about its past
        verdicts from this read.
      </p>
    );
  }

  if (events.length === 0) {
    return (
      <p className="text-sm text-theme-secondary">
        No transitions recorded. This component has held one verdict since it was first swept.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <ul className="flex flex-col gap-2">
        {events.map((event) => (
          <li
            key={event.id}
            data-event-kind={event.kind}
            className="rounded-md border border-theme p-3"
          >
            <div className="flex flex-wrap items-center gap-2">
              <Endpoint
                verdict={event.from_verdict}
                missingLabel="first seen"
                title="No prior verdict — the sweep saw this component for the first time."
              />
              <span aria-hidden="true" className="text-xs text-theme-tertiary">
                to
              </span>
              <Endpoint
                verdict={event.to_verdict}
                missingLabel="removed"
                title="No new verdict — the component was reaped, so its row was deleted."
              />
            </div>
            <div className="mt-1 flex flex-wrap gap-x-3 text-xs text-theme-tertiary">
              <span title={`Occurred at ${event.occurred_at}.`}>
                {formatRelativeTimeCompact(event.occurred_at)}
              </span>
              {/* The kind matters: `platform.component_down` is written IN ADDITION
                  to the transition row, so seeing both for one moment is correct. */}
              <code>{event.kind}</code>
            </div>
          </li>
        ))}
      </ul>

      {totalCount > events.length && (
        <p className="text-xs text-theme-tertiary">
          Showing the {events.length} most recent of {totalCount} recorded transitions.
        </p>
      )}
    </div>
  );
};

export default EventsTab;
