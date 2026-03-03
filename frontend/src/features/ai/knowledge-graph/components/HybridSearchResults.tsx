import React, { useState, useCallback } from 'react';
import { Search, FileText, Zap } from 'lucide-react';
import { sanitizeHtml } from '@/shared/utils/sanitizeHtml';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { GraphSearch } from './GraphSearch';
import { NodeDetailPanel } from './NodeDetailPanel';
import { useHybridSearch } from '../api/knowledgeGraphApi';
import type { EntityType, SearchMode, SearchParams } from '../types/knowledgeGraph';

const MATCH_TYPE_BADGE: Record<SearchMode, 'info' | 'success' | 'warning' | 'default'> = {
  hybrid: 'info',
  vector: 'success',
  keyword: 'warning',
  graph: 'default',
};

export const HybridSearchResults: React.FC = () => {
  const [searchParams, setSearchParams] = useState<SearchParams | null>(null);
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);

  const { data: results, isLoading } = useHybridSearch(
    searchParams || { query: '', mode: 'hybrid' },
    !!searchParams && !!searchParams.query,
  );

  const handleSearch = useCallback((query: string, entityType?: EntityType, mode?: SearchMode) => {
    setSearchParams({
      query,
      entity_type: entityType,
      mode: mode || 'hybrid',
      limit: 20,
    });
  }, []);

  const handleClear = useCallback(() => {
    setSearchParams(null);
    setSelectedNodeId(null);
  }, []);

  return (
    <div className="space-y-4">
      <GraphSearch onSearch={handleSearch} onClear={handleClear} />

      {isLoading && <LoadingSpinner size="sm" className="py-8" />}

      {!isLoading && searchParams && (!results || results.length === 0) && (
        <EmptyState
          icon={Search}
          title="No results found"
          description={`No matching nodes for "${searchParams.query}". Try a different search term or mode.`}
        />
      )}

      {!isLoading && results && results.length > 0 && (
        <div className="space-y-3">
          <p className="text-sm text-theme-tertiary">
            {results.length} result{results.length !== 1 ? 's' : ''} for &quot;{searchParams?.query}&quot;
          </p>

          {results.map((result) => (
            <Card
              key={result.id}
              className="p-4 cursor-pointer"
              hoverable
              clickable
              onClick={() => {
                if (result.match_type === 'graph') {
                  setSelectedNodeId(result.node.id);
                }
              }}
            >
              <div className="flex items-start gap-3">
                <div className="h-10 w-10 rounded-lg bg-theme-info bg-opacity-10 flex items-center justify-center flex-shrink-0">
                  <FileText className="h-5 w-5 text-theme-info" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-sm font-semibold text-theme-primary">{result.node.name}</span>
                    <Badge variant="info" size="xs">{result.node.entity_type}</Badge>
                    <Badge variant={MATCH_TYPE_BADGE[result.match_type]} size="xs">
                      {result.match_type}
                    </Badge>
                  </div>
                  {result.node.description && (
                    <p className="text-sm text-theme-secondary line-clamp-2">{result.node.description}</p>
                  )}
                  {result.highlights.length > 0 && (
                    <div className="mt-2 space-y-1">
                      {result.highlights.map((highlight, idx) => (
                        <p
                          key={idx}
                          className="text-xs text-theme-tertiary italic"
                          dangerouslySetInnerHTML={{ __html: sanitizeHtml(highlight) }}
                        />
                      ))}
                    </div>
                  )}
                </div>
                <div className="flex items-center gap-1 text-right flex-shrink-0">
                  <Zap className="h-3 w-3 text-theme-warning" />
                  <span className="text-xs font-medium text-theme-secondary">
                    {(result.score * 100).toFixed(0)}%
                  </span>
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}

      {/* Node Detail Slide-over */}
      <NodeDetailPanel
        nodeId={selectedNodeId}
        onClose={() => setSelectedNodeId(null)}
        onNodeSelect={setSelectedNodeId}
      />
    </div>
  );
};
