import React, { useState, useCallback, useRef, useEffect } from 'react';
import { Search, X, FileText, MessageSquare, ArrowUpDown } from 'lucide-react';

type StatusFilter = 'all' | 'active' | 'archived';
type SearchMode = 'title' | 'messages';
type SortOption = 'last_activity' | 'created_at' | 'message_count';

interface ConversationSearchProps {
  onSearch: (query: string) => void;
  onFilterChange: (status: StatusFilter) => void;
  activeFilter: StatusFilter;
  searchMode?: SearchMode;
  onSearchModeChange?: (mode: SearchMode) => void;
  sortBy?: SortOption;
  onSortChange?: (sort: SortOption) => void;
}

const SORT_OPTIONS: { value: SortOption; label: string }[] = [
  { value: 'last_activity', label: 'Recent' },
  { value: 'message_count', label: 'Most Messages' },
  { value: 'created_at', label: 'Newest' },
];

export const ConversationSearch: React.FC<ConversationSearchProps> = ({
  onSearch,
  onFilterChange,
  activeFilter,
  searchMode = 'title',
  onSearchModeChange,
  sortBy = 'last_activity',
  onSortChange,
}) => {
  const [query, setQuery] = useState('');
  const [showSort, setShowSort] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sortRef = useRef<HTMLDivElement>(null);

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const value = e.target.value;
      setQuery(value);

      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }

      debounceRef.current = setTimeout(() => {
        onSearch(value);
      }, 300);
    },
    [onSearch]
  );

  const clearSearch = useCallback(() => {
    setQuery('');
    onSearch('');
  }, [onSearch]);

  useEffect(() => {
    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }
    };
  }, []);

  // Close sort dropdown on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (sortRef.current && !sortRef.current.contains(e.target as Node)) {
        setShowSort(false);
      }
    };
    if (showSort) {
      document.addEventListener('mousedown', handleClickOutside, true);
      return () => document.removeEventListener('mousedown', handleClickOutside, true);
    }
  }, [showSort]);

  const filterButtons: { label: string; value: StatusFilter }[] = [
    { label: 'All', value: 'all' },
    { label: 'Active', value: 'active' },
    { label: 'Archived', value: 'archived' },
  ];

  return (
    <div className="px-3 py-2 space-y-2">
      {/* Search input */}
      <div className="relative">
        <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-text-tertiary" />
        <input
          type="text"
          placeholder={searchMode === 'messages' ? 'Search messages...' : 'Search conversations...'}
          value={query}
          onChange={handleChange}
          className="w-full pl-8 pr-8 py-1.5 text-sm bg-theme-surface border border-theme rounded-md text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
        />
        {query && (
          <button
            onClick={clearSearch}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-theme-text-tertiary hover:text-theme-primary"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        )}
      </div>

      {/* Filter + search mode + sort row */}
      <div className="flex items-center gap-1">
        {/* Status filters */}
        {filterButtons.map((btn) => (
          <button
            key={btn.value}
            onClick={() => onFilterChange(btn.value)}
            className={`px-2.5 py-1 text-xs rounded-md transition-colors ${
              activeFilter === btn.value
                ? 'bg-theme-interactive-primary text-white'
                : 'text-theme-secondary hover:bg-theme-surface-hover'
            }`}
          >
            {btn.label}
          </button>
        ))}

        <div className="flex-1" />

        {/* Search mode toggle */}
        {onSearchModeChange && (
          <button
            onClick={() => onSearchModeChange(searchMode === 'title' ? 'messages' : 'title')}
            className={`p-1 rounded transition-colors ${
              searchMode === 'messages'
                ? 'bg-theme-interactive-primary/10 text-theme-interactive-primary'
                : 'text-theme-text-tertiary hover:text-theme-primary'
            }`}
            title={searchMode === 'messages' ? 'Search messages (active)' : 'Search titles only'}
          >
            {searchMode === 'messages' ? (
              <MessageSquare className="h-3.5 w-3.5" />
            ) : (
              <FileText className="h-3.5 w-3.5" />
            )}
          </button>
        )}

        {/* Sort dropdown */}
        {onSortChange && (
          <div ref={sortRef} className="relative">
            <button
              onClick={() => setShowSort(!showSort)}
              className="p-1 rounded text-theme-text-tertiary hover:text-theme-primary transition-colors"
              title="Sort conversations"
            >
              <ArrowUpDown className="h-3.5 w-3.5" />
            </button>
            {showSort && (
              <div className="absolute right-0 top-7 z-50 w-36 bg-theme-surface border border-theme rounded-md shadow-lg py-1">
                {SORT_OPTIONS.map((opt) => (
                  <button
                    key={opt.value}
                    onClick={() => {
                      onSortChange(opt.value);
                      setShowSort(false);
                    }}
                    className={`flex items-center w-full px-3 py-1.5 text-xs transition-colors ${
                      sortBy === opt.value
                        ? 'text-theme-interactive-primary bg-theme-interactive-primary/5'
                        : 'text-theme-secondary hover:bg-theme-surface-hover'
                    }`}
                  >
                    {opt.label}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
