import React, { useState, useEffect } from 'react';
import { Search, SlidersHorizontal, X } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import type { MemoryTier, MemoryFilters } from '../types/memory';

interface MemoryFilterBarProps {
  tier: MemoryTier;
  filters: MemoryFilters;
  activeFilterCount: number;
  totalCount: number;
  loading?: boolean;
  onSearchChange: (q: string) => void;
  onFilterChange: (key: string, value: string | undefined) => void;
  onClearFilters: () => void;
  onRefresh: () => void;
}

const CATEGORY_OPTIONS = [
  { value: '', label: 'All Categories' },
  { value: 'pattern', label: 'Pattern' },
  { value: 'best_practice', label: 'Best Practice' },
  { value: 'discovery', label: 'Discovery' },
  { value: 'failure_mode', label: 'Failure Mode' },
];

const CONTENT_TYPE_OPTIONS = [
  { value: '', label: 'All Types' },
  { value: 'text', label: 'Text' },
  { value: 'markdown', label: 'Markdown' },
  { value: 'code', label: 'Code' },
  { value: 'procedure', label: 'Procedure' },
  { value: 'reference', label: 'Reference' },
  { value: 'guide', label: 'Guide' },
];

const IMPORTANCE_OPTIONS = [
  { value: '', label: 'Any Importance' },
  { value: '0.8', label: 'High (80%+)' },
  { value: '0.6', label: 'Medium (60%+)' },
  { value: '0.3', label: 'Low (30%+)' },
];

export const MemoryFilterBar: React.FC<MemoryFilterBarProps> = ({
  tier,
  filters,
  activeFilterCount,
  totalCount,
  loading,
  onSearchChange,
  onFilterChange,
  onClearFilters,
  onRefresh,
}) => {
  const [localSearch, setLocalSearch] = useState(filters.q || '');
  const [showAdvanced, setShowAdvanced] = useState(false);

  // Sync local search with filter state (e.g., when cleared externally)
  useEffect(() => {
    setLocalSearch(filters.q || '');
  }, [filters.q]);

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => {
      if (localSearch !== (filters.q || '')) {
        onSearchChange(localSearch);
      }
    }, 300);
    return () => clearTimeout(timer);
  }, [localSearch]);

  const showCategoryFilter = tier === 'long_term';
  const showContentTypeFilter = tier === 'shared';
  const showImportanceFilter = tier === 'long_term';
  const hasAdvancedFilters = showCategoryFilter || showContentTypeFilter || showImportanceFilter;

  return (
    <Card>
      <CardContent className="p-4 space-y-3">
        {/* Primary row: search + result count + refresh */}
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex-1 min-w-64">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
              <Input
                placeholder="Search memories..."
                value={localSearch}
                onChange={(e) => setLocalSearch(e.target.value)}
                className="pl-10"
              />
              {localSearch && (
                <button
                  type="button"
                  onClick={() => {
                    setLocalSearch('');
                    onSearchChange('');
                  }}
                  aria-label="Clear search"
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-theme-tertiary hover:text-theme-primary"
                >
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>
          </div>

          {hasAdvancedFilters && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => setShowAdvanced(!showAdvanced)}
              className="relative"
            >
              <SlidersHorizontal className="h-4 w-4 mr-2" />
              Filters
              {activeFilterCount > 0 && (
                <Badge variant="info" size="sm" className="ml-2">
                  {activeFilterCount}
                </Badge>
              )}
            </Button>
          )}

          <span className="text-sm text-theme-tertiary whitespace-nowrap">
            {totalCount} {totalCount === 1 ? 'entry' : 'entries'}
          </span>

          <Button variant="outline" size="sm" onClick={onRefresh} disabled={loading}>
            Refresh
          </Button>
        </div>

        {/* Advanced filters row */}
        {showAdvanced && hasAdvancedFilters && (
          <div className="flex flex-wrap items-center gap-3 pt-2 border-t border-theme">
            {showCategoryFilter && (
              <Select
                value={filters.category || ''}
                onChange={(value) => onFilterChange('category', value || undefined)}
                className="w-44"
              >
                {CATEGORY_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </Select>
            )}

            {showContentTypeFilter && (
              <Select
                value={filters.content_type || ''}
                onChange={(value) => onFilterChange('content_type', value || undefined)}
                className="w-44"
              >
                {CONTENT_TYPE_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </Select>
            )}

            {showImportanceFilter && (
              <Select
                value={filters.min_importance?.toString() || ''}
                onChange={(value) => onFilterChange('min_importance', value || undefined)}
                className="w-44"
              >
                {IMPORTANCE_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </Select>
            )}

            {activeFilterCount > 0 && (
              <Button variant="ghost" size="sm" onClick={onClearFilters} className="text-xs">
                <X className="h-3 w-3 mr-1" />
                Clear all
              </Button>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
};
