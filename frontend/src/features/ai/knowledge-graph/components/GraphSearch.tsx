import React, { useState, useCallback } from 'react';
import { Search, X } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import type { EntityType, SearchMode } from '../types/knowledgeGraph';

interface GraphSearchProps {
  onSearch: (query: string, entityType?: EntityType, mode?: SearchMode) => void;
  onClear: () => void;
  className?: string;
}

const ENTITY_TYPE_OPTIONS: { id: EntityType | undefined; label: string }[] = [
  { id: undefined, label: 'All Types' },
  { id: 'concept', label: 'Concepts' },
  { id: 'entity', label: 'Entities' },
  { id: 'document', label: 'Documents' },
  { id: 'agent', label: 'Agents' },
  { id: 'skill', label: 'Skills' },
  { id: 'context', label: 'Contexts' },
  { id: 'learning', label: 'Learnings' },
];

const SEARCH_MODE_OPTIONS: { id: SearchMode; label: string }[] = [
  { id: 'hybrid', label: 'Hybrid' },
  { id: 'vector', label: 'Vector' },
  { id: 'keyword', label: 'Keyword' },
  { id: 'graph', label: 'Graph' },
];

export const GraphSearch: React.FC<GraphSearchProps> = ({
  onSearch,
  onClear,
  className = '',
}) => {
  const [query, setQuery] = useState('');
  const [entityType, setEntityType] = useState<EntityType | undefined>(undefined);
  const [searchMode, setSearchMode] = useState<SearchMode>('hybrid');

  const handleSubmit = useCallback((e: React.FormEvent) => {
    e.preventDefault();
    if (query.trim().length >= 2) {
      onSearch(query.trim(), entityType, searchMode);
    }
  }, [query, entityType, searchMode, onSearch]);

  const handleClear = useCallback(() => {
    setQuery('');
    setEntityType(undefined);
    setSearchMode('hybrid');
    onClear();
  }, [onClear]);

  return (
    <div className={`space-y-3 ${className}`}>
      <form onSubmit={handleSubmit} className="flex items-center gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search nodes, entities, concepts..."
            className="w-full pl-10 pr-10 py-2 text-sm border border-theme rounded-lg bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
          />
          {query && (
            <button
              type="button"
              onClick={handleClear}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-theme-tertiary hover:text-theme-primary"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
        <Button type="submit" variant="primary" size="sm" disabled={query.trim().length < 2}>
          Search
        </Button>
      </form>

      {/* Filters row */}
      <div className="flex items-center gap-4 flex-wrap">
        {/* Entity Type filter */}
        <div className="flex items-center gap-1">
          <span className="text-xs text-theme-tertiary mr-1">Type:</span>
          {ENTITY_TYPE_OPTIONS.map((opt) => (
            <button
              key={opt.label}
              onClick={() => setEntityType(opt.id)}
              className={`px-2 py-0.5 text-xs rounded-md transition-colors ${
                entityType === opt.id
                  ? 'bg-theme-interactive-primary text-white'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>

        {/* Search Mode filter */}
        <div className="flex items-center gap-1">
          <span className="text-xs text-theme-tertiary mr-1">Mode:</span>
          {SEARCH_MODE_OPTIONS.map((opt) => (
            <button
              key={opt.id}
              onClick={() => setSearchMode(opt.id)}
              className={`px-2 py-0.5 text-xs rounded-md transition-colors ${
                searchMode === opt.id
                  ? 'bg-theme-interactive-primary text-white'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};
