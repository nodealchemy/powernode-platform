import React from 'react';
import {
  NO_SEVERITY,
  filtersActive,
  type QueueFacets,
  type QueueFilters,
  type QueueOrder,
} from '../utils/queueFilters';

// The approval queue's controls (IMP-2184bd06b98e): narrow by category and
// severity, show only what needs a person, and choose the order. Controlled —
// the panel owns the state and keeps it in the URL.

interface Props {
  facets: QueueFacets;
  filters: QueueFilters;
  shown: number;
  total: number;
  onChange: (patch: Partial<QueueFilters>) => void;
  onClear: () => void;
}

const SELECT_CLASS =
  'rounded-md border border-theme bg-theme-surface px-2 py-1.5 text-sm text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary';

export const ApprovalQueueFilters: React.FC<Props> = ({ facets, filters, shown, total, onChange, onClear }) => {
  const active = filtersActive(filters);
  return (
    <div role="group" aria-label="Queue filters" className="mb-4 flex flex-wrap items-end gap-3">
      <label className="flex flex-col gap-1 text-xs text-theme-tertiary">
        Category
        <select
          className={SELECT_CLASS}
          value={filters.category}
          onChange={(event) => onChange({ category: event.target.value })}
        >
          <option value="">All categories</option>
          {facets.categories.map((facet) => (
            <option key={facet.value} value={facet.value}>
              {`${facet.value} (${facet.count})`}
            </option>
          ))}
        </select>
      </label>

      <label className="flex flex-col gap-1 text-xs text-theme-tertiary">
        Severity
        <select
          className={SELECT_CLASS}
          value={filters.severity}
          onChange={(event) => onChange({ severity: event.target.value })}
        >
          <option value="">All severities</option>
          {facets.severities.map((facet) => (
            <option key={facet.value} value={facet.value}>
              {`${facet.value === NO_SEVERITY ? 'No severity' : facet.value} (${facet.count})`}
            </option>
          ))}
        </select>
      </label>

      {facets.needsPerson > 0 && (
        <label className="flex items-center gap-2 pb-1.5 text-sm text-theme-primary">
          <input
            type="checkbox"
            checked={filters.needsPerson}
            onChange={(event) => onChange({ needsPerson: event.target.checked })}
          />
          Only what needs a person
          <span className="text-xs text-theme-tertiary">({facets.needsPerson})</span>
        </label>
      )}

      <label className="flex flex-col gap-1 text-xs text-theme-tertiary">
        Order
        <select
          className={SELECT_CLASS}
          value={filters.order}
          onChange={(event) => onChange({ order: event.target.value as QueueOrder })}
        >
          <option value="oldest">Oldest first</option>
          <option value="newest">Newest first</option>
        </select>
      </label>

      {active && (
        <div className="flex items-center gap-3 pb-1.5 text-sm text-theme-secondary">
          <span role="status">{`Showing ${shown} of ${total}`}</span>
          <button type="button" onClick={onClear} className="text-theme-link hover:underline">
            Clear filters
          </button>
        </div>
      )}
    </div>
  );
};
