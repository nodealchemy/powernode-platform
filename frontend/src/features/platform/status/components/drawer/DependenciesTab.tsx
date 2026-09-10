import React from 'react';
import { VerdictBadge } from '@/shared/components/ui/VerdictBadge';
import { Badge } from '@/shared/components/ui/Badge';
import type {
  ComponentDependency,
  ComponentStatusImpactData,
  ComponentStatusSummary,
} from '@/shared/types/platformStatus';

// Upstream and downstream, side by side (design §4.6).
//
// ── THE TWO HALVES COME FROM DIFFERENT PLACES, AND SAY DIFFERENT THINGS ────
//
// UPSTREAM is the component's own `dependencies` array: edges the contributor
// declared, `{kind, ref, relation}`. They are registry keys, NOT row ids, so an
// edge may name a component whose row has not been swept yet. That is by
// design, and it is why upstream entries render as identifiers rather than as
// cards with verdicts — this panel has no row to read a verdict from, and
// inventing "ok" for an unresolvable edge would be the worst possible default.
//
// DOWNSTREAM is the impact endpoint's reverse walk (depth 4, cycle-safe): real
// rows, with real verdicts.
//
// ── THE ROOT-CAUSE RANKING IS LABELLED, EVERY TIME ─────────────────────────
//
// `root_cause_candidates` is correlation over the dependency graph — ordered by
// unhealthy-dependent count, then by earliest transition. The server sends
// `heuristic: true` and a `heuristic_basis` string precisely so this panel
// cannot render the ranking without the caveat. An unlabelled ranking gets read
// as an answer, and an operator who restarts the wrong thing because a list was
// sorted confidently has been misled by the UI, not by the data.

const RELATION_HINT: Record<string, string> = {
  requires: 'This component needs the other to work.',
  serves: 'This component serves the other.',
  hosts: 'This component runs the other.',
  backs: 'This component provides storage or capacity for the other.',
  routes: 'This component carries traffic for the other.',
};

const UpstreamEdge: React.FC<{ edge: ComponentDependency }> = ({ edge }) => (
  <li
    data-dependency-kind={edge.kind}
    data-dependency-relation={edge.relation}
    className="flex flex-wrap items-center gap-2 rounded-md border border-theme px-3 py-2"
  >
    {/* An unrecognized relation renders as its own text rather than being
        dropped. `relation` is validated nowhere server-side, so a contributor
        emitting one this table has never seen is possible today, and an edge
        whose label you do not know is still an edge. */}
    <Badge variant="outline" size="xs" className={RELATION_HINT[edge.relation] ? '' : 'border-dashed'}>
      <span title={RELATION_HINT[edge.relation] ?? 'Relation not documented in design §4.3.'}>
        {edge.relation}
      </span>
    </Badge>
    <code className="text-xs text-theme-secondary">{edge.kind}</code>
    <code className="text-xs text-theme-tertiary break-all">{edge.ref}</code>
  </li>
);

const DownstreamRow: React.FC<{
  row: ComponentStatusSummary;
  onSelect?: (row: ComponentStatusSummary) => void;
}> = ({ row, onSelect }) => {
  const name = row.display_name || row.component_ref;
  return (
    <li>
      <button
        type="button"
        onClick={() => onSelect?.(row)}
        className="w-full flex items-center justify-between gap-2 rounded-md border border-theme px-3 py-2 text-left hover:bg-theme-surface-hover"
      >
        <span className="min-w-0">
          <span className="block truncate text-sm text-theme-primary">{name}</span>
          <code className="block truncate text-xs text-theme-tertiary">{row.component_kind}</code>
        </span>
        <VerdictBadge verdict={row.verdict} size="xs" withLabel={false} labelPrefix={name} />
      </button>
    </li>
  );
};

export interface DependenciesTabProps {
  dependencies: ComponentDependency[];
  impact: ComponentStatusImpactData | null;
  onSelect?: (row: ComponentStatusSummary) => void;
}

export const DependenciesTab: React.FC<DependenciesTabProps> = ({
  dependencies,
  impact,
  onSelect,
}) => (
  <div className="flex flex-col gap-5">
    <section data-dependency-section="upstream">
      <h4 className="mb-2 text-xs uppercase tracking-wide text-theme-tertiary">
        Upstream
        <span
          className="ml-2 normal-case"
          title="Edges this component's contributor declared. They are registry keys, so one may name a component that has not been swept yet."
        >
          {dependencies.length}
        </span>
      </h4>
      {dependencies.length === 0 ? (
        <p className="text-xs text-theme-secondary">
          This component declares no upstream dependencies.
        </p>
      ) : (
        <ul className="flex flex-col gap-2">
          {dependencies.map((edge, index) => (
            <UpstreamEdge key={`${edge.kind}-${edge.ref}-${index}`} edge={edge} />
          ))}
        </ul>
      )}
    </section>

    <section data-dependency-section="downstream">
      <h4 className="mb-2 text-xs uppercase tracking-wide text-theme-tertiary">
        Downstream impact
        {impact && (
          <span
            className="ml-2 normal-case"
            title="Components that depend on this one, reverse-walked to depth 4 from one preloaded edge set."
          >
            {impact.impact.count}
          </span>
        )}
      </h4>
      {!impact ? (
        <p className="text-xs text-theme-secondary">Impact could not be read.</p>
      ) : impact.impact.count === 0 ? (
        <p className="text-xs text-theme-secondary">Nothing this plane models depends on it.</p>
      ) : (
        <>
          <p className="mb-2 text-xs text-theme-tertiary">
            Worst downstream verdict:{' '}
            <VerdictBadge
              verdict={impact.impact.worst_verdict}
              size="xs"
              labelPrefix="Worst downstream"
            />
          </p>
          <ul className="flex flex-col gap-2">
            {impact.impact.components.map((row) => (
              <DownstreamRow key={row.id} row={row} onSelect={onSelect} />
            ))}
          </ul>
        </>
      )}
    </section>

    {impact && impact.root_cause_candidates.length > 0 && (
      <section data-dependency-section="root-cause">
        <h4 className="mb-1 text-xs uppercase tracking-wide text-theme-tertiary">
          Likely root cause
        </h4>
        {/* Rendered, not hidden in a tooltip: the caveat is the point. */}
        <p className="mb-2 text-xs text-theme-tertiary">
          {impact.heuristic ? 'Heuristic, not a diagnosis. ' : ''}
          {impact.heuristic_basis}
        </p>
        <ul className="flex flex-col gap-2">
          {impact.root_cause_candidates.map((row) => (
            <DownstreamRow key={row.id} row={row} onSelect={onSelect} />
          ))}
        </ul>
      </section>
    )}
  </div>
);

export default DependenciesTab;
