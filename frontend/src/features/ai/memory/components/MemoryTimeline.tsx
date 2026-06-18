import React, { useState, useCallback, useRef, useEffect } from 'react';
import {
  ChevronDown,
  ChevronUp,
  Clock,
  Code,
  Copy,
  Database,
  Eye,
  Trash2,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { MarkdownRenderer } from '@/shared/components/ui/MarkdownRenderer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { cn } from '@/shared/utils/cn';
import { MemoryFilterBar } from './MemoryFilterBar';
import { useInfiniteMemory } from '../hooks/useInfiniteMemory';
import { useMemoryFilters } from '../hooks/useMemoryFilters';
import type { MemoryEntry, MemoryStats } from '../types/memory';

interface MemoryTimelineProps {
  agentId: string;
  onSelectMemory?: (memory: MemoryEntry) => void;
  stats?: MemoryStats;
  onDeleteEntry?: (entry: MemoryEntry) => void;
  className?: string;
}

const TIER_CONFIG: Record<string, { color: string; label: string }> = {
  working: { color: 'text-theme-warning-fg', label: 'Working' },
  short_term: { color: 'text-theme-info-fg', label: 'Short-Term' },
  long_term: { color: 'text-theme-success-fg', label: 'Long-Term' },
  shared: { color: 'text-theme-primary', label: 'Shared' },
};

function formatValue(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value === null || value === undefined) return '';
  return JSON.stringify(value, null, 2);
}

function extractTextContent(entry: MemoryEntry): { text: string; isStructured: boolean } {
  if (entry.content && typeof entry.content === 'string') {
    return { text: entry.content, isStructured: false };
  }
  if (typeof entry.value === 'string') {
    return { text: entry.value, isStructured: false };
  }
  if (entry.value && typeof entry.value === 'object' && 'text' in (entry.value as Record<string, unknown>)) {
    const textVal = (entry.value as Record<string, unknown>).text;
    if (typeof textVal === 'string') return { text: textVal, isStructured: false };
  }
  return { text: formatValue(entry.value), isStructured: true };
}

export const MemoryTimeline: React.FC<MemoryTimelineProps> = ({
  agentId,
  onSelectMemory,
  stats,
  onDeleteEntry,
  className,
}) => {
  const { tier, filters, activeFilterCount, setTier, setSearch, setFilter, clearFilters } = useMemoryFilters();
  const {
    entries,
    loading,
    loadingMore,
    error,
    hasMore,
    totalCount,
    loadMore,
    refresh,
    removeEntry,
  } = useInfiniteMemory({ agentId, tier, filters });

  const [expandedEntries, setExpandedEntries] = useState<Set<string>>(new Set());
  const [rawEntries, setRawEntries] = useState<Set<string>>(new Set());
  const { addNotification } = useNotifications();

  // Infinite scroll sentinel
  const sentinelRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel) return;

    const observer = new IntersectionObserver(
      (intersections) => {
        if (intersections[0]?.isIntersecting && hasMore && !loadingMore) {
          loadMore();
        }
      },
      { rootMargin: '200px' }
    );
    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [hasMore, loadingMore, loadMore]);

  // Reset expand state when tier changes
  useEffect(() => {
    setExpandedEntries(new Set());
    setRawEntries(new Set());
  }, [tier]);

  const toggleExpanded = useCallback((entryId: string) => {
    setExpandedEntries((prev) => {
      const next = new Set(prev);
      if (next.has(entryId)) next.delete(entryId);
      else next.add(entryId);
      return next;
    });
  }, []);

  const toggleRaw = useCallback((entryId: string) => {
    setRawEntries((prev) => {
      const next = new Set(prev);
      if (next.has(entryId)) next.delete(entryId);
      else next.add(entryId);
      return next;
    });
  }, []);

  const copyEntryContent = useCallback((entry: MemoryEntry) => {
    const { text } = extractTextContent(entry);
    navigator.clipboard.writeText(text);
    addNotification({ type: 'success', title: 'Copied', message: 'Content copied to clipboard' });
  }, [addNotification]);

  const handleDelete = useCallback((entry: MemoryEntry) => {
    onDeleteEntry?.(entry);
    removeEntry(entry.id, entry.key);
  }, [onDeleteEntry, removeEntry]);

  const formatDateRelative = (dateStr: string) => {
    const date = new Date(dateStr);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
  };

  // Group by date
  const groupedMemories = entries.reduce((acc, memory) => {
    const dateStr = memory.created_at
      ? new Date(memory.created_at).toLocaleDateString()
      : 'Unknown';
    if (!acc[dateStr]) acc[dateStr] = [];
    acc[dateStr].push(memory);
    return acc;
  }, {} as Record<string, MemoryEntry[]>);

  return (
    <div className={cn('space-y-4', className)}>
      {/* Tier selector pills */}
      <div className="flex gap-2 flex-wrap">
        {(['short_term', 'long_term', 'shared'] as const).map((t) => {
          const config = TIER_CONFIG[t];
          const count = t === 'short_term' ? stats?.short_term.total
            : t === 'long_term' ? stats?.long_term.total
            : stats?.shared.total;
          return (
            <button
              key={t}
              type="button"
              onClick={() => setTier(t)}
              className={cn(
                'flex items-center gap-2 px-3 py-1.5 rounded-full text-sm font-medium transition-colors border',
                tier === t
                  ? 'border-theme-primary bg-theme-primary/10 text-theme-primary'
                  : 'border-theme bg-theme-surface text-theme-secondary hover:border-theme-primary/30'
              )}
            >
              {config.label}
              {count !== undefined && (
                <span className="text-xs opacity-70">{count}</span>
              )}
            </button>
          );
        })}
      </div>

      {/* Filters */}
      <MemoryFilterBar
        tier={tier}
        filters={filters}
        activeFilterCount={activeFilterCount}
        totalCount={totalCount}
        loading={loading}
        onSearchChange={setSearch}
        onFilterChange={setFilter}
        onClearFilters={clearFilters}
        onRefresh={refresh}
      />

      {/* Error state */}
      {error && (
        <div className="p-4 bg-theme-danger-fg/10 border border-theme-danger-border/30 rounded-lg text-theme-danger-fg">
          {error}
        </div>
      )}

      {/* Initial loading */}
      {loading && entries.length === 0 && !error && (
        <Card>
          <CardContent className="flex items-center justify-center py-12">
            <Loading size="lg" message="Loading memories..." />
          </CardContent>
        </Card>
      )}

      {/* Empty state */}
      {!loading && entries.length === 0 && !error && (
        <EmptyState
          icon={Database}
          title="No memories found"
          description={
            filters.q || activeFilterCount > 0
              ? 'No entries match your search and filters. Try adjusting your criteria.'
              : `This agent has no ${tier.replace(/_/g, ' ')} memories yet.`
          }
        />
      )}

      {/* Timeline */}
      {entries.length > 0 && (
        <div className="space-y-6">
          {Object.entries(groupedMemories).map(([date, dayMemories]) => (
            <div key={date}>
              <div className="flex items-center gap-3 mb-3">
                <div className="h-px flex-1 bg-theme-background-secondary" />
                <span className="text-sm font-medium text-theme-tertiary px-2">{date}</span>
                <div className="h-px flex-1 bg-theme-background-secondary" />
              </div>

              <div className="space-y-3 relative">
                <div className="absolute left-4 top-0 bottom-0 w-px bg-theme-background-secondary" />

                {dayMemories.map((entry, idx) => {
                  const config = TIER_CONFIG[tier] || TIER_CONFIG.short_term;
                  const entryId = entry.id || `${entry.key}-${idx}`;
                  const isExpanded = expandedEntries.has(entryId);
                  const { text: entryText, isStructured } = extractTextContent(entry);
                  const isShowingRaw = rawEntries.has(entryId);

                  return (
                    <Card
                      key={entryId}
                      className="ml-8 hover:border-theme-primary/50 transition-colors"
                    >
                      <CardContent className="p-4">
                        <div className="absolute -left-2 w-4 h-4 rounded-full bg-theme-surface border-2 border-theme-primary" />

                        <div className="flex items-start justify-between gap-3">
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className="font-medium text-theme-primary font-mono text-sm">
                                {entry.key}
                              </span>
                              <Badge variant="outline" size="sm" className={config.color}>
                                {config.label}
                              </Badge>
                              {entry.category && (
                                <Badge variant="outline" size="sm">
                                  {entry.category}
                                </Badge>
                              )}
                            </div>

                            {/* Collapsed: content preview */}
                            {!isExpanded && (
                              isStructured ? (
                                <p className="text-sm text-theme-secondary mt-2 line-clamp-2 font-mono">
                                  {entryText}
                                </p>
                              ) : (
                                <div className="mt-2 max-h-[4.5rem] overflow-hidden [mask-image:linear-gradient(to_bottom,black_60%,transparent)]">
                                  <MarkdownRenderer content={entryText} variant="preview" />
                                </div>
                              )
                            )}

                            {/* Expanded: full content */}
                            {isExpanded && (
                              <div className="mt-3 space-y-3">
                                <div className="flex items-center gap-1">
                                  {!isStructured && (
                                    <Button
                                      variant="ghost"
                                      size="sm"
                                      onClick={(e) => { e.stopPropagation(); toggleRaw(entryId); }}
                                      className="text-xs h-7"
                                    >
                                      {isShowingRaw ? (
                                        <><Eye className="h-3.5 w-3.5 mr-1" />Rendered</>
                                      ) : (
                                        <><Code className="h-3.5 w-3.5 mr-1" />Raw</>
                                      )}
                                    </Button>
                                  )}
                                  <Button
                                    variant="ghost"
                                    size="sm"
                                    onClick={(e) => { e.stopPropagation(); copyEntryContent(entry); }}
                                    className="text-xs h-7"
                                  >
                                    <Copy className="h-3.5 w-3.5 mr-1" />
                                    Copy
                                  </Button>
                                </div>

                                {isShowingRaw || isStructured ? (
                                  <pre className="text-sm text-theme-secondary bg-theme-background-tertiary rounded-lg p-3 overflow-x-auto max-h-96 overflow-y-auto">
                                    <code>{entryText}</code>
                                  </pre>
                                ) : (
                                  <div className="rounded-lg border border-theme p-4 bg-theme-surface/30">
                                    <MarkdownRenderer content={entryText} variant="admin" />
                                  </div>
                                )}

                                <div className="flex flex-wrap items-center gap-3 text-xs text-theme-tertiary">
                                  {entry.confidence_score !== undefined && (
                                    <span>Confidence: {Math.round(entry.confidence_score * 100)}%</span>
                                  )}
                                  {entry.session_id && (
                                    <span className="font-mono">Session: {entry.session_id.substring(0, 12)}...</span>
                                  )}
                                  {entry.expires_at && (
                                    <span>Expires: {new Date(entry.expires_at).toLocaleString()}</span>
                                  )}
                                  {entry.memory_type && (
                                    <Badge variant="outline" size="sm">{entry.memory_type}</Badge>
                                  )}
                                </div>
                              </div>
                            )}

                            <div className="flex items-center gap-4 mt-2 text-xs text-theme-tertiary">
                              {entry.created_at && (
                                <span className="flex items-center gap-1">
                                  <Clock className="h-3 w-3" />
                                  {formatDateRelative(entry.created_at)}
                                </span>
                              )}
                              {entry.importance_score !== undefined && (
                                <span>
                                  Importance: {Math.round(entry.importance_score * 100)}%
                                </span>
                              )}
                              {(entry.access_count ?? 0) > 0 && (
                                <span>{entry.access_count} accesses</span>
                              )}
                            </div>
                          </div>

                          <div className="flex items-center gap-1 shrink-0">
                            {onDeleteEntry && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={(e) => { e.stopPropagation(); handleDelete(entry); }}
                                className="text-theme-danger-fg hover:text-theme-danger-fg"
                              >
                                <Trash2 className="h-4 w-4" />
                              </Button>
                            )}
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => {
                                toggleExpanded(entryId);
                                onSelectMemory?.(entry);
                              }}
                            >
                              {isExpanded ? (
                                <ChevronUp className="h-4 w-4" />
                              ) : (
                                <ChevronDown className="h-4 w-4" />
                              )}
                            </Button>
                          </div>
                        </div>
                      </CardContent>
                    </Card>
                  );
                })}
              </div>
            </div>
          ))}

          {/* Infinite scroll sentinel */}
          <div ref={sentinelRef} className="h-1" />
          {loadingMore && (
            <div className="flex justify-center py-4">
              <Loading size="sm" message="Loading more..." />
            </div>
          )}
          {!hasMore && entries.length > 0 && (
            <p className="text-center text-sm text-theme-tertiary py-2">
              All {totalCount} entries loaded
            </p>
          )}
        </div>
      )}
    </div>
  );
};

export default MemoryTimeline;
