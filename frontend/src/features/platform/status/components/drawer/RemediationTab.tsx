import React from 'react';
import { Link } from 'react-router-dom';
import { RemediationChip } from '@/features/platform/status/components/RemediationChip';
import type {
  ComponentRemediation,
  RemediationRouteData,
  RemediationState,
} from '@/shared/types/platformStatus';

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

// The core tokens a route's `reason` can carry. Anything else is a lane's own
// sentence and is rendered as prose — a switch over lane sentences would be a
// switch over strings nobody promised to keep stable.
const CORE_REASON_TEXT: Record<string, string> = {
  NoLaneForSignal: 'No lane is registered for this signal kind.',
  LaneError: "The lane raised while describing itself, so its report can't be trusted.",
  LaneReportedUnknownState:
    'The lane reported a state the platform does not recognise, so it was rejected.',
};

/**
 * What the owning lane reported (A9 §4.2).
 *
 * BRANCHES ON `routed`, never on `route.state`: the response omits `route`
 * entirely when nothing routed the component.
 *
 * `lane_reason` is the one field here that most needs rendering and had no
 * consumer until now (E2 review L3). Verified against the producer rather than
 * either brief: `Platform::RemediationRouter` (remediation_router.rb:98-113) sets
 * it ONLY on the refusal path, when a lane reported a state core rejected, and
 * it carries that lane's own `reason` sentence. The route's `reason` then holds
 * core's token for the refusal; `lane_reason` holds what the lane itself said —
 * which may well be "consent budget exhausted", but that is the lane's content,
 * not the field's meaning. When present it is still the ONLY explanation of the
 * component's situation, so it is shown beside the lane, verbatim, and ONLY when
 * present: no placeholder, no "none", nothing fabricated when the lane said
 * nothing.
 */
const RoutePanel: React.FC<{ route: RemediationRouteData }> = ({ route }) => {
  if (!route.routed || !route.route) {
    return (
      <section data-route-section="unrouted" className="rounded-md border border-theme p-3">
        <h4 className="text-xs uppercase tracking-wide text-theme-tertiary">Route</h4>
        <p className="mt-1 text-sm text-theme-secondary">
          Nothing routes this component to a lane
          {route.reason === 'NoRoutedSignal' ? ' — no signal is open for it.' : '.'}
        </p>
      </section>
    );
  }

  const lane = route.route;
  const reasonText = lane.reason ? (CORE_REASON_TEXT[lane.reason] ?? lane.reason) : null;

  return (
    <section data-route-section="routed" className="rounded-md border border-theme p-3">
      <h4 className="text-xs uppercase tracking-wide text-theme-tertiary">Route</h4>
      <div data-route-lane className="mt-1 flex flex-wrap items-center gap-2">
        <span className="text-xs text-theme-tertiary">Lane</span>
        <code className="text-sm text-theme-primary">{lane.lane_key}</code>
        {lane.lane_reason && (
          // Beside the lane, so the reason is read as the lane's own account of
          // itself — typically "consent budget exhausted" — not as a caption.
          <span data-lane-reason className="text-xs text-theme-warning-fg">
            {lane.lane_reason}
          </span>
        )}
      </div>

      {reasonText && <p className="mt-1 text-sm text-theme-secondary">{reasonText}</p>}

      <dl className="mt-2 grid grid-cols-[minmax(0,auto)_minmax(0,1fr)] gap-x-3 gap-y-1 text-xs">
        {lane.policy && (
          <>
            <dt className="text-theme-tertiary">Policy</dt>
            <dd className="text-theme-secondary">{lane.policy}</dd>
          </>
        )}
        {lane.consent && (
          <>
            <dt className="text-theme-tertiary">Consent</dt>
            <dd className="text-theme-secondary">{lane.consent}</dd>
          </>
        )}
        {lane.disruption && (
          <>
            <dt className="text-theme-tertiary">Disruption</dt>
            <dd className="text-theme-secondary">{lane.disruption}</dd>
          </>
        )}
        {lane.environment_ceiling && (
          <>
            <dt className="text-theme-tertiary">Environment ceiling</dt>
            <dd className="text-theme-secondary">{lane.environment_ceiling}</dd>
          </>
        )}
        {lane.blast_radius !== null && lane.blast_radius !== undefined && (
          <>
            <dt className="text-theme-tertiary" title="How many instances one action from this lane may touch.">
              Blast radius
            </dt>
            <dd className="text-theme-secondary">{lane.blast_radius}</dd>
          </>
        )}
        <dt className="text-theme-tertiary">Can proceed</dt>
        <dd className="text-theme-secondary">
          {lane.can_proceed ? 'yes' : 'no'}
          {/* `false` while awaiting an operator is the normal combination, and is
              said so rather than left reading like an error. */}
          {!lane.can_proceed && lane.state === 'awaiting_operator' && ' — waiting on a decision, as expected'}
        </dd>
      </dl>
    </section>
  );
};

export interface RemediationTabProps {
  remediation: ComponentRemediation;
  state: RemediationState;
  /** The owning lane's report. Null while loading, and when the read failed (see `routeFailed`). */
  route?: RemediationRouteData | null;
  /** The route read failed, which is a different fact from "nothing routes this component". */
  routeFailed?: boolean;
}

export const RemediationTab: React.FC<RemediationTabProps> = ({
  remediation,
  state,
  route,
  routeFailed = false,
}) => (
  <div className="flex flex-col gap-4" data-remediation-state={state}>
    <div className="flex items-center gap-2">
      <RemediationChip state={state} size="sm" />
    </div>

    <StateExplanation state={state} />

    {route && <RoutePanel route={route} />}

    {/* Said, not left blank (C3p2 review R4): an absent route panel reads as
        "no lane report", and a failed read has not established that. */}
    {routeFailed && (
      <p className="text-sm text-theme-warning-fg" data-route-failed>
        Could not load this component&apos;s remediation route. What its lane is doing is unknown
        here; this is a failed read, not a finding that nothing routes it.
      </p>
    )}

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
