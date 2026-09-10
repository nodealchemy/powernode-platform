import React, { useMemo, useState } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { usePlatformStatus, STATUS_POLL_MS } from '@/features/platform/status/hooks/usePlatformStatus';
import { StatusRollupHeader } from '@/features/platform/status/components/StatusRollupHeader';
import {
  StatusFilterBar,
  ALL_PLANES,
  type StatusFilterValue,
} from '@/features/platform/status/components/StatusFilterBar';
import { ComponentStatusCard } from '@/features/platform/status/components/ComponentStatusCard';
import { RemediationRail } from '@/features/platform/status/components/RemediationRail';
import type { ComponentStatusSummary } from '@/shared/types/platformStatus';

// THE OPERATOR SCREEN (design §6). One page answering what is unhealthy, why,
// what the platform is doing about it, and what a person must decide —
// replacing five screens across two codebases (C4 does the deleting).
//
// The page knows NOTHING about component kinds. Cards are drawn from each row's
// `presentation` blob, grouped by its `group_order`, and a kind registered by an
// extension that loads after first render appears without a code change here —
// see the registry subscription in `usePlatformStatus`.
//
// C3 adds the drawer. This file already carries the plumbing for it — a
// `selectedId` and an `onSelect` threaded through both the grid and the rail —
// so C3 opens a drawer without touching the page's layout or its data flow.

/** Rows grouped by `presentation.group_order`, then by label, both stably. */
const groupRows = (rows: ComponentStatusSummary[]) => {
  const groups = new Map<string, { order: number; label: string; rows: ComponentStatusSummary[] }>();

  for (const row of rows) {
    const label = row.presentation?.label || row.component_kind;
    // A contributor that declared no group_order sorts LAST rather than first:
    // an unordered kind is one nobody has placed yet, and placing it above the
    // ones that were deliberately ordered would be an accident presented as a
    // decision.
    const order = row.presentation?.group_order ?? Number.MAX_SAFE_INTEGER;
    const key = `${order}:${label}`;
    const existing = groups.get(key);
    if (existing) existing.rows.push(row);
    else groups.set(key, { order, label, rows: [row] });
  }

  return Array.from(groups.values()).sort(
    (a, b) => a.order - b.order || a.label.localeCompare(b.label)
  );
};

export const StatusPage: React.FC = () => {
  const [filters, setFilters] = useState<StatusFilterValue>({
    kind: '',
    verdict: '',
    environment: ALL_PLANES,
  });
  // C3 reads this. C2 sets it and renders nothing from it beyond the card's
  // pressed state — a drawer that does not exist yet must not be faked.
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const query = useMemo(
    () => ({
      // Empty string means "no filter", and it must not reach the server as
      // `kind=`: the door treats a blank the same as absent today, but relying
      // on that would make this page's behaviour depend on a `presence` call in
      // someone else's file.
      kind: filters.kind || undefined,
      verdict: filters.verdict || undefined,
      environment: filters.environment || undefined,
    }),
    [filters]
  );

  const {
    rows,
    rollup,
    unknownEnvironment,
    totalCount,
    loading,
    error,
    isConnected,
    lastLoadedAt,
    knownEnvironmentIds,
    refresh,
  } = usePlatformStatus(query);

  // Offered kinds come from what the server has actually reported, so a kind
  // nobody contributes never appears as a filter that returns nothing.
  const kinds = useMemo(
    () => Array.from(new Set(rows.map((row) => row.component_kind))).sort(),
    [rows]
  );
  const groups = useMemo(() => groupRows(rows), [rows]);

  const handleSelect = (row: ComponentStatusSummary) => {
    setSelectedId((current) => (current === row.id ? null : row.id));
  };

  return (
    <PageContainer
      title="Status"
      description="Every component of the platform and fleet, its verdict, and what is being done about it."
      actions={[{ id: 'refresh', label: 'Refresh', onClick: refresh, variant: 'secondary' }]}
    >
      <div className="flex flex-col gap-4">
        {error && <ErrorAlert message={error} />}

        <StatusRollupHeader
          rollup={rollup}
          loading={loading}
          isConnected={isConnected}
          lastLoadedAt={lastLoadedAt}
          loadedCount={rows.length}
          totalCount={totalCount}
          pollMs={STATUS_POLL_MS}
        />

        <StatusFilterBar
          value={filters}
          onChange={setFilters}
          kinds={kinds}
          environmentIds={knownEnvironmentIds}
          unknownEnvironment={unknownEnvironment}
        />

        <div className="grid grid-cols-1 lg:grid-cols-4 gap-4">
          <div className="lg:col-span-3 flex flex-col gap-6">
            {loading && rows.length === 0 && (
              <p className="text-sm text-theme-secondary">Loading components…</p>
            )}

            {!loading && rows.length === 0 && (
              // Says which question produced the empty page. "No components"
              // and "no components matching this filter" send an operator to
              // different places.
              <p className="text-sm text-theme-secondary">
                {filters.kind || filters.verdict || filters.environment
                  ? 'No components match these filters.'
                  : 'No components have been swept yet.'}
              </p>
            )}

            {groups.map((group) => (
              <section key={`${group.order}:${group.label}`} data-status-group={group.label}>
                <h2 className="mb-2 text-sm font-medium uppercase tracking-wide text-theme-tertiary">
                  {group.label}
                  <span
                    className="ml-2 normal-case font-normal"
                    title={`Components of this kind matching the current filters (${group.rows.length}).`}
                  >
                    {group.rows.length}
                  </span>
                </h2>
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                  {group.rows.map((row) => (
                    <ComponentStatusCard
                      key={row.id}
                      row={row}
                      selected={selectedId === row.id}
                      onSelect={handleSelect}
                    />
                  ))}
                </div>
              </section>
            ))}
          </div>

          <aside className="lg:col-span-1">
            <RemediationRail rows={rows} selectedId={selectedId} onSelect={handleSelect} />
          </aside>
        </div>
      </div>
    </PageContainer>
  );
};

export default StatusPage;
