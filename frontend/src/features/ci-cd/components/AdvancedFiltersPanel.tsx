import React, { useState, useEffect, useCallback } from 'react';
import {
  Filter,
  ChevronDown,
  ChevronUp,
  Calendar,
  User,
  Zap,
  Clock,
  RotateCcw,
  Check,
  Search,
} from 'lucide-react';

// ================================
// TYPES
// ================================

export interface PipelineFilters {
  // Status
  status?: string[];

  // Trigger type
  triggerType?: string[];

  // Time filters
  since?: string;
  until?: string;

  // Duration filters (in seconds)
  minDuration?: number;
  maxDuration?: number;

  // Actor filter
  actor?: string;

  // Branch filter
  branch?: string;

  // Repository filter
  repositoryId?: string;

  // Event type
  event?: string;

  // Sort
  sortBy?: string;
  sortDirection?: 'asc' | 'desc';
}

interface AdvancedFiltersPanelProps {
  filters: PipelineFilters;
  onChange: (filters: PipelineFilters) => void;
  onClear: () => void;
  isOpen: boolean;
  onToggle: () => void;
  repositories?: Array<{ id: string; name: string; full_name: string }>;
  branches?: string[];
  actors?: string[];
}

// ================================
// CONSTANTS
// ================================

const STATUS_OPTIONS = [
  { value: 'pending', label: 'Pending', color: 'bg-theme-warning' },
  { value: 'running', label: 'Running', color: 'bg-theme-info' },
  { value: 'success', label: 'Success', color: 'bg-theme-success' },
  { value: 'failure', label: 'Failure', color: 'bg-theme-danger' },
  { value: 'cancelled', label: 'Cancelled', color: 'bg-theme-secondary' },
  { value: 'skipped', label: 'Skipped', color: 'bg-theme-secondary' },
];

const TRIGGER_OPTIONS = [
  { value: 'push', label: 'Push', icon: '⬆️' },
  { value: 'pull_request', label: 'Pull Request', icon: '🔀' },
  { value: 'schedule', label: 'Schedule', icon: '🕐' },
  { value: 'workflow_dispatch', label: 'Manual', icon: '▶️' },
  { value: 'repository_dispatch', label: 'API', icon: '🔗' },
  { value: 'merge_group', label: 'Merge Queue', icon: '📋' },
];

const DURATION_PRESETS = [
  { label: 'Any', min: undefined, max: undefined },
  { label: '< 1 min', min: undefined, max: 60 },
  { label: '1-5 min', min: 60, max: 300 },
  { label: '5-15 min', min: 300, max: 900 },
  { label: '15-30 min', min: 900, max: 1800 },
  { label: '30-60 min', min: 1800, max: 3600 },
  { label: '> 1 hour', min: 3600, max: undefined },
];

const TIME_PRESETS = [
  { label: 'Last hour', hours: 1 },
  { label: 'Last 24 hours', hours: 24 },
  { label: 'Last 7 days', hours: 168 },
  { label: 'Last 30 days', hours: 720 },
  { label: 'Last 90 days', hours: 2160 },
];

// ================================
// SUB-COMPONENTS
// ================================

interface MultiSelectChipsProps {
  options: Array<{ value: string; label: string; color?: string; icon?: string }>;
  selected: string[];
  onChange: (selected: string[]) => void;
  label: string;
}

const MultiSelectChips: React.FC<MultiSelectChipsProps> = ({
  options,
  selected,
  onChange,
  label,
}) => {
  const toggleOption = (value: string) => {
    if (selected.includes(value)) {
      onChange(selected.filter((v) => v !== value));
    } else {
      onChange([...selected, value]);
    }
  };

  return (
    <div>
      <label className="block text-sm font-medium text-theme-primary mb-2">{label}</label>
      <div className="flex flex-wrap gap-2">
        {options.map((option) => {
          const isSelected = selected.includes(option.value);
          return (
            <button
              key={option.value}
              type="button"
              onClick={() => toggleOption(option.value)}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
                isSelected
                  ? 'bg-theme-primary text-white'
                  : 'bg-theme-bg border border-theme text-theme-secondary hover:border-theme-primary hover:text-theme-primary'
              }`}
            >
              {option.color && (
                <span className={`w-2 h-2 rounded-full ${option.color}`} />
              )}
              {option.icon && <span>{option.icon}</span>}
              {option.label}
              {isSelected && <Check className="w-3 h-3 ml-1" />}
            </button>
          );
        })}
      </div>
    </div>
  );
};

interface DurationSliderProps {
  minDuration?: number;
  maxDuration?: number;
  onChange: (min?: number, max?: number) => void;
}

const DurationSlider: React.FC<DurationSliderProps> = ({
  minDuration,
  maxDuration,
  onChange,
}) => {
  return (
    <div>
      <label className="block text-sm font-medium text-theme-primary mb-2">
        <Clock className="w-4 h-4 inline mr-1" />
        Duration
      </label>
      <div className="flex flex-wrap gap-2">
        {DURATION_PRESETS.map((preset) => {
          const isActive = preset.min === minDuration && preset.max === maxDuration;
          return (
            <button
              key={preset.label}
              type="button"
              onClick={() => onChange(preset.min, preset.max)}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                isActive
                  ? 'bg-theme-primary text-white'
                  : 'bg-theme-bg border border-theme text-theme-secondary hover:border-theme-primary'
              }`}
            >
              {preset.label}
            </button>
          );
        })}
      </div>

      {/* Custom range inputs */}
      <div className="mt-3 flex items-center gap-2">
        <input
          type="number"
          value={minDuration || ''}
          onChange={(e) => onChange(e.target.value ? parseInt(e.target.value, 10) : undefined, maxDuration)}
          placeholder="Min (sec)"
          className="w-24 bg-theme-bg border border-theme rounded px-2 py-1 text-sm text-theme-primary"
        />
        <span className="text-theme-secondary">to</span>
        <input
          type="number"
          value={maxDuration || ''}
          onChange={(e) => onChange(minDuration, e.target.value ? parseInt(e.target.value, 10) : undefined)}
          placeholder="Max (sec)"
          className="w-24 bg-theme-bg border border-theme rounded px-2 py-1 text-sm text-theme-primary"
        />
      </div>
    </div>
  );
};

interface DateRangePickerProps {
  since?: string;
  until?: string;
  onChange: (since?: string, until?: string) => void;
}

const DateRangePicker: React.FC<DateRangePickerProps> = ({ since, until, onChange }) => {
  const applyPreset = (hours: number) => {
    const now = new Date();
    const start = new Date(now.getTime() - hours * 60 * 60 * 1000);
    onChange(start.toISOString().slice(0, 16), undefined);
  };

  return (
    <div>
      <label className="block text-sm font-medium text-theme-primary mb-2">
        <Calendar className="w-4 h-4 inline mr-1" />
        Time Range
      </label>

      {/* Presets */}
      <div className="flex flex-wrap gap-2 mb-3">
        {TIME_PRESETS.map((preset) => (
          <button
            key={preset.label}
            type="button"
            onClick={() => applyPreset(preset.hours)}
            className="px-3 py-1.5 rounded-lg text-sm font-medium bg-theme-bg border border-theme text-theme-secondary hover:border-theme-primary hover:text-theme-primary transition-colors"
          >
            {preset.label}
          </button>
        ))}
      </div>

      {/* Custom range */}
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-xs text-theme-secondary mb-1">From</label>
          <input
            type="datetime-local"
            value={since?.slice(0, 16) || ''}
            onChange={(e) => onChange(e.target.value ? new Date(e.target.value).toISOString() : undefined, until)}
            className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-sm text-theme-primary"
          />
        </div>
        <div>
          <label className="block text-xs text-theme-secondary mb-1">To</label>
          <input
            type="datetime-local"
            value={until?.slice(0, 16) || ''}
            onChange={(e) => onChange(since, e.target.value ? new Date(e.target.value).toISOString() : undefined)}
            className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-sm text-theme-primary"
          />
        </div>
      </div>
    </div>
  );
};

interface AutocompleteInputProps {
  value: string;
  onChange: (value: string) => void;
  suggestions: string[];
  placeholder: string;
  label: string;
  icon: React.ReactNode;
}

const AutocompleteInput: React.FC<AutocompleteInputProps> = ({
  value,
  onChange,
  suggestions,
  placeholder,
  label,
  icon,
}) => {
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [filteredSuggestions, setFilteredSuggestions] = useState<string[]>([]);

  useEffect(() => {
    if (value) {
      const filtered = suggestions.filter((s) =>
        s.toLowerCase().includes(value.toLowerCase())
      );
      setFilteredSuggestions(filtered);
    } else {
      setFilteredSuggestions(suggestions.slice(0, 10));
    }
  }, [value, suggestions]);

  return (
    <div className="relative">
      <label className="block text-sm font-medium text-theme-primary mb-2">
        {icon}
        <span className="ml-1">{label}</span>
      </label>
      <div className="relative">
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onFocus={() => setShowSuggestions(true)}
          onBlur={() => setTimeout(() => setShowSuggestions(false), 200)}
          placeholder={placeholder}
          className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary"
        />
        <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-secondary" />
      </div>

      {showSuggestions && filteredSuggestions.length > 0 && (
        <div className="absolute z-10 w-full mt-1 bg-theme-surface border border-theme rounded-lg shadow-lg max-h-48 overflow-y-auto">
          {filteredSuggestions.map((suggestion) => (
            <button
              key={suggestion}
              type="button"
              onClick={() => {
                onChange(suggestion);
                setShowSuggestions(false);
              }}
              className="w-full px-3 py-2 text-left text-sm text-theme-primary hover:bg-theme-bg"
            >
              {suggestion}
            </button>
          ))}
        </div>
      )}
    </div>
  );
};

// ================================
// MAIN COMPONENT
// ================================

export const AdvancedFiltersPanel: React.FC<AdvancedFiltersPanelProps> = ({
  filters,
  onChange,
  onClear,
  isOpen,
  onToggle,
  repositories = [],
  branches = [],
  actors = [],
}) => {
  const activeFilterCount = Object.values(filters).filter(
    (v) => v !== undefined && v !== '' && (Array.isArray(v) ? v.length > 0 : true)
  ).length;

  const handleStatusChange = useCallback(
    (status: string[]) => {
      onChange({ ...filters, status: status.length > 0 ? status : undefined });
    },
    [filters, onChange]
  );

  const handleTriggerChange = useCallback(
    (triggerType: string[]) => {
      onChange({ ...filters, triggerType: triggerType.length > 0 ? triggerType : undefined });
    },
    [filters, onChange]
  );

  const handleDurationChange = useCallback(
    (min?: number, max?: number) => {
      onChange({ ...filters, minDuration: min, maxDuration: max });
    },
    [filters, onChange]
  );

  const handleDateChange = useCallback(
    (since?: string, until?: string) => {
      onChange({ ...filters, since, until });
    },
    [filters, onChange]
  );

  return (
    <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
      {/* Header */}
      <button
        onClick={onToggle}
        className="w-full flex items-center justify-between p-4 hover:bg-theme-bg/50 transition-colors"
      >
        <div className="flex items-center gap-2">
          <Filter className="w-5 h-5 text-theme-secondary" />
          <span className="font-medium text-theme-primary">Advanced Filters</span>
          {activeFilterCount > 0 && (
            <span className="px-2 py-0.5 bg-theme-primary text-white rounded-full text-xs">
              {activeFilterCount}
            </span>
          )}
        </div>
        {isOpen ? (
          <ChevronUp className="w-5 h-5 text-theme-secondary" />
        ) : (
          <ChevronDown className="w-5 h-5 text-theme-secondary" />
        )}
      </button>

      {/* Content */}
      {isOpen && (
        <div className="p-4 pt-0 space-y-6 border-t border-theme">
          {/* Status Filter */}
          <MultiSelectChips
            options={STATUS_OPTIONS}
            selected={filters.status || []}
            onChange={handleStatusChange}
            label="Status"
          />

          {/* Trigger Type Filter */}
          <MultiSelectChips
            options={TRIGGER_OPTIONS}
            selected={filters.triggerType || []}
            onChange={handleTriggerChange}
            label="Trigger Type"
          />

          {/* Duration Filter */}
          <DurationSlider
            minDuration={filters.minDuration}
            maxDuration={filters.maxDuration}
            onChange={handleDurationChange}
          />

          {/* Date Range Filter */}
          <DateRangePicker
            since={filters.since}
            until={filters.until}
            onChange={handleDateChange}
          />

          {/* Actor Filter */}
          <AutocompleteInput
            value={filters.actor || ''}
            onChange={(actor) => onChange({ ...filters, actor: actor || undefined })}
            suggestions={actors}
            placeholder="Search by username..."
            label="Actor"
            icon={<User className="w-4 h-4 inline" />}
          />

          {/* Branch Filter */}
          <AutocompleteInput
            value={filters.branch || ''}
            onChange={(branch) => onChange({ ...filters, branch: branch || undefined })}
            suggestions={branches}
            placeholder="Search by branch..."
            label="Branch"
            icon={<Zap className="w-4 h-4 inline" />}
          />

          {/* Repository Filter */}
          {repositories.length > 0 && (
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Repository
              </label>
              <select
                value={filters.repositoryId || ''}
                onChange={(e) =>
                  onChange({ ...filters, repositoryId: e.target.value || undefined })
                }
                className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary"
              >
                <option value="">All Repositories</option>
                {repositories.map((repo) => (
                  <option key={repo.id} value={repo.id}>
                    {repo.full_name}
                  </option>
                ))}
              </select>
            </div>
          )}

          {/* Sort Options */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Sort By
              </label>
              <select
                value={filters.sortBy || 'created_at'}
                onChange={(e) => onChange({ ...filters, sortBy: e.target.value })}
                className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary"
              >
                <option value="created_at">Created Date</option>
                <option value="updated_at">Updated Date</option>
                <option value="duration">Duration</option>
                <option value="status">Status</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Direction
              </label>
              <select
                value={filters.sortDirection || 'desc'}
                onChange={(e) =>
                  onChange({ ...filters, sortDirection: e.target.value as 'asc' | 'desc' })
                }
                className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary"
              >
                <option value="desc">Newest First</option>
                <option value="asc">Oldest First</option>
              </select>
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center justify-between pt-4 border-t border-theme">
            <button
              onClick={onClear}
              className="flex items-center gap-2 px-4 py-2 text-theme-secondary hover:text-theme-primary"
            >
              <RotateCcw className="w-4 h-4" />
              Clear All
            </button>
            <button
              onClick={onToggle}
              className="flex items-center gap-2 px-4 py-2 bg-theme-primary text-white rounded-lg font-medium hover:bg-theme-primary/90"
            >
              <Check className="w-4 h-4" />
              Apply Filters
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default AdvancedFiltersPanel;
