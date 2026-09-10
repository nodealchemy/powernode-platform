import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';
import type { StatusCondition, ConditionStatus } from '@/shared/types/platformStatus';

// The conditions a component reports (design §4.2) — the "why" behind its
// verdict, shown in full rather than summarized.
//
// ── A CONDITION'S STATUS IS THREE-VALUED ───────────────────────────────────
//
// true / false / "unknown", and the third is a STRING rather than null because
// in jsonb a null is indistinguishable from an absent key. So "we looked and
// could not tell" gets its own rendering, distinct from both "fine" and
// "broken" — collapsing unknown into either is how a blind spot becomes
// invisible. Note the polarity trap: `status: false` on `Reachable` is bad,
// `status: false` on `Held` is the ordinary case. The badge therefore says what
// the STATUS is, and the reason token beside it says what that means; this
// component never decides which way a given type points.
//
// ── THE REASON TOKEN IS RENDERED VERBATIM ──────────────────────────────────
//
// `type` and `reason` are UpperCamelCase tokens a runbook, an alert and a spec
// all key on. They are shown as-is, in a monospace face, never title-cased or
// space-separated: prettifying them destroys the one property they have. The
// human sentence is `message`, and it is rendered beside them.

const STATUS_PRESENTATION: Record<
  'true' | 'false' | 'unknown',
  { variant: NonNullable<React.ComponentProps<typeof Badge>['variant']>; label: string; title: string }
> = {
  true: { variant: 'success', label: 'true', title: 'This condition holds.' },
  false: {
    variant: 'warning',
    label: 'false',
    title:
      'This condition does not hold. Whether that is a problem depends on the type — a false `Held` is the ordinary case; a false `Reachable` is not.',
  },
  unknown: {
    variant: 'outline',
    label: 'unknown',
    title: 'The contributor could not determine this. Not the same as false.',
  },
};

const statusKey = (status: ConditionStatus): 'true' | 'false' | 'unknown' => {
  if (status === true) return 'true';
  if (status === false) return 'false';
  return 'unknown';
};

const EvidenceTable: React.FC<{ evidence: Record<string, unknown> }> = ({ evidence }) => {
  const entries = Object.entries(evidence ?? {});
  if (entries.length === 0) return null;

  return (
    <dl className="mt-2 grid grid-cols-[minmax(0,auto)_minmax(0,1fr)] gap-x-3 gap-y-1 text-xs">
      {entries.map(([key, value]) => (
        <React.Fragment key={key}>
          <dt className="font-mono text-theme-tertiary">{key}</dt>
          <dd className="font-mono text-theme-secondary break-all">
            {/* The raw numbers the reason came from. Stringified rather than
                interpreted: this panel does not know what any given key means,
                and a formatter that guessed would misreport the evidence an
                operator is here to read. */}
            {typeof value === 'object' && value !== null ? JSON.stringify(value) : String(value)}
          </dd>
        </React.Fragment>
      ))}
    </dl>
  );
};

export interface ConditionsTabProps {
  conditions: StatusCondition[];
}

export const ConditionsTab: React.FC<ConditionsTabProps> = ({ conditions }) => {
  if (conditions.length === 0) {
    // NOT "everything is fine". A component reporting no conditions is a
    // contributor that emitted none, which is itself worth noticing.
    return (
      <p className="text-sm text-theme-secondary">
        This component reported no conditions. That is a contributor emitting nothing, not a clean bill of health.
      </p>
    );
  }

  return (
    <ul className="flex flex-col gap-3">
      {conditions.map((condition, index) => {
        const presentation = STATUS_PRESENTATION[statusKey(condition.status)];
        return (
          <li
            key={`${condition.type}-${index}`}
            data-condition-type={condition.type}
            data-condition-status={presentation.label}
            className="rounded-md border border-theme p-3"
          >
            <div className="flex flex-wrap items-center gap-2">
              <code className="text-sm font-medium text-theme-primary">{condition.type}</code>
              <span title={presentation.title}>
                <Badge variant={presentation.variant} size="xs">
                  {presentation.label}
                </Badge>
              </span>
              {condition.severity && condition.status === false && (
                <Badge variant={condition.severity === 'down' ? 'danger' : 'warning'} size="xs">
                  {condition.severity}
                </Badge>
              )}
            </div>

            <div className="mt-1 flex flex-wrap items-baseline gap-2">
              <code className="text-xs text-theme-secondary">{condition.reason}</code>
              {condition.message && (
                <span className="text-xs text-theme-secondary">{condition.message}</span>
              )}
            </div>

            <div className="mt-1 flex flex-wrap gap-x-3 text-xs text-theme-tertiary">
              {condition.last_transition_at && (
                <span
                  title={`Last CHANGED at ${condition.last_transition_at}. Not when it was last observed — the sweep inherits this while the status holds, which is what makes "for three hours" mean something.`}
                >
                  changed {formatRelativeTimeCompact(condition.last_transition_at)}
                </span>
              )}
              {condition.observed_at && (
                <span title={`Observed at ${condition.observed_at}.`}>
                  observed {formatRelativeTimeCompact(condition.observed_at)}
                </span>
              )}
              {condition.observed_generation && (
                <span title="The generation of the source object this reading was taken from.">
                  gen {condition.observed_generation}
                </span>
              )}
            </div>

            <EvidenceTable evidence={condition.evidence} />
          </li>
        );
      })}
    </ul>
  );
};

export default ConditionsTab;
