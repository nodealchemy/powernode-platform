import React from 'react';
import {
  Filter,
  ArrowUpDown,
  SortAsc,
  SortDesc,
  Calendar,
  User,
  Hash,
  FileText,
  CheckCircle,
  Workflow,
  FileStack
} from 'lucide-react';
import { SearchInput } from '@/shared/components/ui/SearchInput';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { WorkflowFilters } from '@/shared/services/ai/types/workflow-api-types';

interface WorkflowFiltersBarProps {
  searchQuery: string;
  onSearch: (query: string) => void;
  sortBy: string;
  onSortByChange: (value: string) => void;
  sortOrder: 'asc' | 'desc';
  onSortOrderToggle: () => void;
  typeFilter: 'all' | 'workflows' | 'templates';
  onTypeFilterChange: (value: 'all' | 'workflows' | 'templates') => void;
  filters: WorkflowFilters;
  onFilterChange: (key: keyof WorkflowFilters, value: WorkflowFilters[keyof WorkflowFilters]) => void;
  onSort: (field: string) => void;
}

const getSortIcon = (field: string) => {
  switch (field) {
    case 'name': return FileText;
    case 'created_at': case 'updated_at': return Calendar;
    case 'status': return CheckCircle;
    case 'creator': return User;
    case 'version': return Hash;
    default: return ArrowUpDown;
  }
};

const getSortLabel = (field: string, order: 'asc' | 'desc') => {
  const labels: Record<string, string> = {
    name: order === 'asc' ? 'Name (A → Z)' : 'Name (Z → A)',
    created_at: order === 'asc' ? 'Oldest First' : 'Newest First',
    updated_at: order === 'asc' ? 'Oldest Updates' : 'Recent Updates',
    status: order === 'asc' ? 'Status (A → Z)' : 'Status (Z → A)',
    creator: order === 'asc' ? 'Creator (A → Z)' : 'Creator (Z → A)',
    version: order === 'asc' ? 'Version (Low → High)' : 'Version (High → Low)'
  };
  return labels[field] || `${field} (${order.toUpperCase()})`;
};

export const WorkflowFiltersBar: React.FC<WorkflowFiltersBarProps> = ({
  searchQuery,
  onSearch,
  sortBy,
  onSortByChange,
  sortOrder,
  onSortOrderToggle,
  typeFilter,
  onTypeFilterChange,
  filters,
  onFilterChange,
}) => {
  return (
    <div className="space-y-4">
      {/* Search Bar */}
      <div className="w-full">
        <SearchInput
          placeholder="Search workflows by name or description..."
          value={searchQuery}
          onChange={onSearch}
          className="w-full"
        />
      </div>

      {/* Filters and Sorting on Same Line */}
      <div className="flex flex-wrap items-center gap-4">
        {/* Sort Controls */}
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1.5 text-sm font-medium text-theme-muted shrink-0">
            <ArrowUpDown className="h-4 w-4" />
            <span>Sort:</span>
          </div>
          <EnhancedSelect
            placeholder="Choose field"
            value={sortBy}
            onChange={(value) => onSortByChange(value || 'created_at')}
            options={[
              { value: 'name', label: 'Name', icon: FileText },
              { value: 'created_at', label: 'Created', icon: Calendar },
              { value: 'updated_at', label: 'Updated', icon: Calendar },
              { value: 'status', label: 'Status', icon: CheckCircle },
              { value: 'creator', label: 'Creator', icon: User },
              { value: 'version', label: 'Version', icon: Hash }
            ]}
            className="w-32"
          />
          <button
            onClick={onSortOrderToggle}
            className="flex items-center gap-2 px-3 py-2 text-sm font-medium border border-theme rounded-md bg-theme-surface hover:bg-theme-surface-elevated transition-colors min-w-fit"
            title={`Currently: ${getSortLabel(sortBy, sortOrder)}`}
          >
            {sortOrder === 'asc' ? (
              <SortAsc className="h-4 w-4 text-theme-interactive-primary" />
            ) : (
              <SortDesc className="h-4 w-4 text-theme-interactive-primary" />
            )}
            <span className="hidden sm:inline text-theme-primary">
              {sortOrder === 'asc' ? 'A→Z' : 'Z→A'}
            </span>
          </button>
        </div>

        {/* Type Filter - Workflows vs Templates */}
        <div className="flex items-center gap-1 bg-theme-surface border border-theme rounded-lg p-1">
          <button
            onClick={() => onTypeFilterChange('all')}
            className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors ${
              typeFilter === 'all'
                ? 'bg-theme-interactive-primary text-theme-on-primary'
                : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-elevated'
            }`}
          >
            All
          </button>
          <button
            onClick={() => onTypeFilterChange('workflows')}
            className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors flex items-center gap-1.5 ${
              typeFilter === 'workflows'
                ? 'bg-theme-interactive-primary text-theme-on-primary'
                : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-elevated'
            }`}
          >
            <Workflow className="h-3.5 w-3.5" />
            Workflows
          </button>
          <button
            onClick={() => onTypeFilterChange('templates')}
            className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors flex items-center gap-1.5 ${
              typeFilter === 'templates'
                ? 'bg-theme-interactive-primary text-theme-on-primary'
                : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-elevated'
            }`}
          >
            <FileStack className="h-3.5 w-3.5" />
            Templates
          </button>
        </div>

        {/* Filter Controls */}
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1.5 text-sm font-medium text-theme-muted shrink-0">
            <Filter className="h-4 w-4" />
            <span>Filter:</span>
          </div>
          <EnhancedSelect
            placeholder="All Statuses"
            value={filters.status || ''}
            onChange={(value) => onFilterChange('status', value || undefined)}
            options={[
              { value: '', label: 'All Statuses' },
              { value: 'draft', label: 'Draft' },
              { value: 'active', label: 'Active' },
              { value: 'inactive', label: 'Inactive' },
              { value: 'paused', label: 'Paused' },
              { value: 'archived', label: 'Archived' }
            ]}
            className="w-32"
          />
          <EnhancedSelect
            placeholder="All Visibility"
            value={filters.visibility || ''}
            onChange={(value) => onFilterChange('visibility', value || undefined)}
            options={[
              { value: '', label: 'All Visibility' },
              { value: 'private', label: 'Private' },
              { value: 'account', label: 'Account' },
              { value: 'public', label: 'Public' }
            ]}
            className="w-32"
          />
        </div>

        {/* Current Sort Display */}
        {(sortBy !== 'created_at' || sortOrder !== 'desc') && (
          <div className="flex items-center gap-2 px-3 py-2 bg-theme-interactive-primary/10 border border-theme-interactive-primary/20 rounded-md text-sm">
            <div className="flex items-center gap-1.5 text-theme-interactive-primary">
              {React.createElement(getSortIcon(sortBy), { className: "h-4 w-4" })}
              <span className="font-medium">
                Sorted by {getSortLabel(sortBy, sortOrder)}
              </span>
            </div>
            <button
              onClick={() => {
                onSortByChange('created_at');
              }}
              className="text-theme-muted hover:text-theme-primary transition-colors"
              title="Reset to default sort"
            >
              ×
            </button>
          </div>
        )}
      </div>
    </div>
  );
};
