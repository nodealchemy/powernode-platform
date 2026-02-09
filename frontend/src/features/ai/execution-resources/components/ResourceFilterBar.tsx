

import { Search, X } from 'lucide-react';
import type { ResourceFilters } from '../types';

interface ResourceFilterBarProps {
  filters: ResourceFilters;
  onFilterChange: (filters: Partial<ResourceFilters>) => void;
  onClear: () => void;
}

export function ResourceFilterBar({ filters, onFilterChange, onClear }: ResourceFilterBarProps) {
  const hasFilters = filters.search || filters.status || filters.start_date || filters.end_date;

  return (
    <div className="flex flex-wrap items-center gap-3 mb-4">
      <div className="relative flex-1 min-w-[200px]">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-text-tertiary" />
        <input
          type="text"
          placeholder="Search resources..."
          value={filters.search || ''}
          onChange={(e) => onFilterChange({ search: e.target.value || undefined })}
          className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-theme-border bg-theme-bg-primary text-theme-text-primary placeholder-theme-text-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
        />
      </div>

      <select
        value={filters.status || ''}
        onChange={(e) => onFilterChange({ status: e.target.value || undefined })}
        className="px-3 py-2 text-sm rounded-lg border border-theme-border bg-theme-bg-primary text-theme-text-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
      >
        <option value="">All Statuses</option>
        <option value="completed">Completed</option>
        <option value="running">Running</option>
        <option value="failed">Failed</option>
        <option value="pending">Pending</option>
        <option value="available">Available</option>
      </select>

      <input
        type="date"
        value={filters.start_date || ''}
        onChange={(e) => onFilterChange({ start_date: e.target.value || undefined })}
        className="px-3 py-2 text-sm rounded-lg border border-theme-border bg-theme-bg-primary text-theme-text-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
      />

      <input
        type="date"
        value={filters.end_date || ''}
        onChange={(e) => onFilterChange({ end_date: e.target.value || undefined })}
        className="px-3 py-2 text-sm rounded-lg border border-theme-border bg-theme-bg-primary text-theme-text-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
      />

      {hasFilters && (
        <button
          onClick={onClear}
          className="inline-flex items-center gap-1 px-3 py-2 text-sm text-theme-text-secondary hover:text-theme-text-primary transition-colors"
        >
          <X className="w-4 h-4" />
          Clear
        </button>
      )}
    </div>
  );
}
