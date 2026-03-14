import { useState } from 'react';
import { Link } from 'react-router-dom';
import DOMPurify from 'dompurify';
import { contextApi } from '../services/contextApi';
import { Input } from '@/shared/components/ui/Input';
import { Button } from '@/shared/components/ui/Button';
import type { SearchResult, SearchParams, EntryType } from '../types';

interface SearchResultsProps {
  contextId?: string;
  onEntryClick?: (result: SearchResult) => void;
}

export function SearchResults({ contextId, onEntryClick }: SearchResultsProps) {
  const [results, setResults] = useState<SearchResult[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchType, setSearchType] = useState<'keyword' | 'semantic' | 'hybrid'>('hybrid');
  const [selectedTypes, setSelectedTypes] = useState<EntryType[]>([]);
  const [hasSearched, setHasSearched] = useState(false);
  const [totalResults, setTotalResults] = useState(0);

  const handleSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!searchQuery.trim()) return;

    setIsSearching(true);
    setHasSearched(true);

    const params: SearchParams = {
      query: searchQuery,
      search_type: searchType,
      entry_types: selectedTypes.length > 0 ? selectedTypes : undefined,
      limit: 50,
    };

    let response;
    if (contextId) {
      response = await contextApi.searchInContext(contextId, params);
    } else {
      response = await contextApi.search(params);
    }

    if (response.success && response.data) {
      setResults(response.data.results);
      setTotalResults(response.data.total_results);
    } else {
      setResults([]);
      setTotalResults(0);
    }

    setIsSearching(false);
  };

  const toggleEntryType = (type: EntryType) => {
    if (selectedTypes.includes(type)) {
      setSelectedTypes(selectedTypes.filter((t) => t !== type));
    } else {
      setSelectedTypes([...selectedTypes, type]);
    }
  };

  const entryTypes: EntryType[] = [
    'fact',
    'preference',
    'interaction',
    'knowledge',
    'skill',
    'relationship',
    'goal',
    'constraint',
  ];

  return (
    <div className="space-y-6">
      {/* Search Form */}
      <form onSubmit={handleSearch} className="space-y-4">
        <div className="flex gap-3">
          <div className="flex-1">
            <Input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search memories and knowledge..."
            />
          </div>
          <Button
            type="submit"
            variant="primary"
            disabled={isSearching || !searchQuery.trim()}
          >
            {isSearching ? 'Searching...' : 'Search'}
          </Button>
        </div>

        {/* Search Options */}
        <div className="flex flex-wrap items-center gap-4">
          <div className="flex items-center gap-2">
            <span className="text-sm text-theme-secondary">Search Type:</span>
            <div className="flex gap-1">
              {(['keyword', 'semantic', 'hybrid'] as const).map((type) => (
                <button
                  key={type}
                  type="button"
                  onClick={() => setSearchType(type)}
                  className={`px-3 py-1 text-sm rounded border transition-colors ${
                    searchType === type
                      ? 'bg-theme-interactive-primary text-white border-transparent'
                      : 'bg-theme-surface text-theme-primary border-theme hover:border-theme-interactive-primary'
                  }`}
                >
                  {type.charAt(0).toUpperCase() + type.slice(1)}
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <span className="text-sm text-theme-secondary">Filter:</span>
            <div className="flex flex-wrap gap-1">
              {entryTypes.map((type) => (
                <button
                  key={type}
                  type="button"
                  onClick={() => toggleEntryType(type)}
                  className={`px-2 py-1 text-xs rounded border transition-colors ${
                    selectedTypes.includes(type)
                      ? contextApi.getEntryTypeColor(type) + ' border-transparent'
                      : 'bg-theme-surface text-theme-primary border-theme hover:border-theme-interactive-primary'
                  }`}
                >
                  {contextApi.getEntryTypeLabel(type)}
                </button>
              ))}
            </div>
          </div>
        </div>
      </form>

      {/* Results */}
      {hasSearched && (
        <div>
          <div className="flex items-center justify-between mb-4">
            <p className="text-sm text-theme-secondary">
              {isSearching ? (
                'Searching...'
              ) : (
                <>
                  Found <span className="font-medium text-theme-primary">{totalResults}</span>{' '}
                  result{totalResults !== 1 ? 's' : ''}
                </>
              )}
            </p>
          </div>

          {isSearching ? (
            <div className="flex items-center justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
            </div>
          ) : results.length === 0 ? (
            <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
              <div className="text-4xl mb-4">🔍</div>
              <h3 className="text-lg font-medium text-theme-primary">No results found</h3>
              <p className="text-theme-secondary mt-1">
                Try different keywords or search type
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {results.map((result, index) => (
                <SearchResultItem
                  key={`${result.entry.id}-${index}`}
                  result={result}
                  onClick={onEntryClick}
                  showContext={!contextId}
                />
              ))}
            </div>
          )}
        </div>
      )}

      {/* Search Tips */}
      {!hasSearched && (
        <div className="bg-theme-surface border border-theme rounded-lg p-6">
          <h3 className="font-medium text-theme-primary mb-3">Search Tips</h3>
          <ul className="space-y-2 text-sm text-theme-secondary">
            <li className="flex items-start gap-2">
              <span className="text-theme-primary">•</span>
              <span>
                <strong>Keyword</strong> search matches exact terms in content
              </span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-theme-primary">•</span>
              <span>
                <strong>Semantic</strong> search finds conceptually similar content using AI embeddings
              </span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-theme-primary">•</span>
              <span>
                <strong>Hybrid</strong> combines both for best results
              </span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-theme-primary">•</span>
              <span>Use entry type filters to narrow down results</span>
            </li>
          </ul>
        </div>
      )}
    </div>
  );
}

interface SearchResultItemProps {
  result: SearchResult;
  onClick?: (result: SearchResult) => void;
  showContext?: boolean;
}

function SearchResultItem({ result, onClick, showContext }: SearchResultItemProps) {
  const { entry, score, highlights, context } = result;

  const content = (
    <div
      className={`bg-theme-surface border border-theme rounded-lg p-4 transition-colors ${
        onClick ? 'hover:border-theme-primary cursor-pointer' : ''
      }`}
      onClick={() => onClick?.(result)}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span
              className={`px-2 py-0.5 text-xs rounded ${contextApi.getEntryTypeColor(entry.entry_type)}`}
            >
              {contextApi.getEntryTypeLabel(entry.entry_type)}
            </span>
            <span className="font-mono text-sm text-theme-primary truncate">{entry.key}</span>
          </div>

          {entry.content_text && (
            <p className="text-sm text-theme-secondary line-clamp-2">{entry.content_text}</p>
          )}

          {highlights && highlights.length > 0 && (
            <div className="mt-2 text-sm">
              {highlights.map((highlight, i) => (
                <p
                  key={i}
                  className="text-theme-secondary"
                  dangerouslySetInnerHTML={{
                    __html: DOMPurify.sanitize(
                      highlight.replace(
                        /<mark>/g,
                        '<mark class="bg-theme-warning bg-opacity-30 text-theme-primary px-0.5 rounded">'
                      ),
                      { ALLOWED_TAGS: ['mark'], ALLOWED_ATTR: ['class'] }
                    ),
                  }}
                />
              ))}
            </div>
          )}

          <div className="flex items-center gap-4 mt-2 text-xs text-theme-tertiary">
            <span className="text-theme-primary font-medium">
              {(score * 100).toFixed(1)}% match
            </span>
            <span className={contextApi.getImportanceColor(entry.importance_score)}>
              {contextApi.formatImportanceScore(entry.importance_score)} importance
            </span>
            {entry.tags.length > 0 && (
              <span>{entry.tags.slice(0, 3).join(', ')}</span>
            )}
          </div>

          {showContext && context && (
            <div className="mt-2 text-xs text-theme-tertiary">
              Context: {context.name} ({contextApi.getContextTypeLabel(context.context_type)})
            </div>
          )}
        </div>

        <div className="text-right">
          <div
            className={`w-12 h-12 rounded-full flex items-center justify-center text-sm font-medium ${
              score >= 0.8
                ? 'bg-theme-success bg-opacity-10 text-theme-success'
                : score >= 0.5
                  ? 'bg-theme-warning bg-opacity-10 text-theme-warning'
                  : 'bg-theme-surface text-theme-tertiary'
            }`}
          >
            {(score * 100).toFixed(0)}%
          </div>
        </div>
      </div>
    </div>
  );

  if (showContext && context && !onClick) {
    return (
      <Link to={`/app/ai/contexts/${context.id}`} className="block">
        {content}
      </Link>
    );
  }

  return content;
}
