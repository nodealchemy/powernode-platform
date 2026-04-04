import React from 'react';
import { X } from 'lucide-react';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import { SOURCE_TYPE_OPTIONS } from './sourceTypeLabels';
import type { DataSourceFilters as DataSourceFiltersType } from '@/shared/types/ai';

interface DataSourceFiltersProps {
  filters: DataSourceFiltersType;
  onFiltersChange: (filters: Partial<DataSourceFiltersType>) => void;
}

export const DataSourceFilters: React.FC<DataSourceFiltersProps> = ({
  filters,
  onFiltersChange
}) => {
  const handleClearFilters = () => {
    onFiltersChange({
      source_type: undefined,
      search: undefined,
      sort: 'priority'
    });
  };

  const hasActiveFilters = filters.source_type || filters.search;

  return (
    <div className="bg-theme-surface p-4 rounded-lg border border-theme space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-theme-primary">Filters</h3>
        {hasActiveFilters && (
          <Button
            variant="ghost"
            size="sm"
            onClick={handleClearFilters}
            className="h-8 px-2 text-theme-tertiary hover:text-theme-primary"
          >
            <X className="h-4 w-4 mr-1" />
            Clear
          </Button>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Source Type
          </label>
          <Select
            value={filters.source_type || ''}
            onChange={(value) => onFiltersChange({ source_type: value || undefined })}
          >
            <option value="">All Types</option>
            {SOURCE_TYPE_OPTIONS.map(({ value, label }) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </Select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Sort By
          </label>
          <Select
            value={filters.sort || 'priority'}
            onChange={(value) => onFiltersChange({ sort: value as 'name' | 'priority' | 'created_at' })}
          >
            <option value="priority">Priority</option>
            <option value="name">Name</option>
            <option value="created_at">Date Created</option>
          </Select>
        </div>
      </div>
    </div>
  );
};
