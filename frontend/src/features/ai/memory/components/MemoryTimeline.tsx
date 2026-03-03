import React, { useState, useEffect, useCallback, useMemo } from 'react';
import {
  ChevronDown,
  ChevronUp,
  Clock,
  Database,
  Filter,
  RefreshCw,
  Search,
  Trash2,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { cn } from '@/shared/utils/cn';
import { fetchMemoryEntries } from '../api/memoryApi';
import type { MemoryEntry, MemoryTier, MemoryStats } from '../types/memory';

interface MemoryTimelineProps {
  agentId: string;
  onSelectMemory?: (memory: MemoryEntry) => void;
  stats?: MemoryStats;
  tier?: MemoryTier;
  onTierChange?: (tier: MemoryTier) => void;
  onDeleteEntry?: (entry: MemoryEntry) => void;
  className?: string;
}

const TIER_CONFIG: Record<string, { color: string; label: string }> = {
  working: { color: 'text-theme-warning', label: 'Working' },
  short_term: { color: 'text-theme-info', label: 'Short-Term' },
  long_term: { color: 'text-theme-success', label: 'Long-Term' },
  shared: { color: 'text-theme-primary', label: 'Shared' },
};

const TIER_EMPTY_DESCRIPTIONS: Record<string, string> = {
  working: 'Ephemeral session data stored in Redis — active only during agent execution.',
  short_term: 'Recent observations and context, subject to TTL expiry.',
  long_term: 'Persisted knowledge promoted from short-term memory based on access patterns.',
  shared: 'Cross-agent knowledge accessible to all agents in the account.',
};

function formatValue(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value === null || value === undefined) return '';
  return JSON.stringify(value, null, 2);
}

export const MemoryTimeline: React.FC<MemoryTimelineProps> = ({
  agentId,
  onSelectMemory,
  stats,
  tier,
  onTierChange,
  onDeleteEntry,
  className,
}) => {
  const [memories, setMemories] = useState<MemoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [tierFilter, setTierFilter] = useState<MemoryTier>(tier || 'short_term');
  const [expandedEntries, setExpandedEntries] = useState<Set<string>>(new Set());

  // Sync tier from parent when it changes (e.g. clicking a stats card)
  useEffect(() => {
    if (tier !== undefined && tier !== tierFilter) {
      setTierFilter(tier);
    }
  }, [tier]);

  const handleTierChange = useCallback((value: MemoryTier) => {
    setTierFilter(value);
    setExpandedEntries(new Set());
    onTierChange?.(value);
  }, [onTierChange]);

  const toggleExpanded = useCallback((entryId: string) => {
    setExpandedEntries((prev) => {
      const next = new Set(prev);
      if (next.has(entryId)) {
        next.delete(entryId);
      } else {
        next.add(entryId);
      }
      return next;
    });
  }, []);

  const loadMemories = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await fetchMemoryEntries(agentId, tierFilter);
      setMemories(response);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load memories');
    } finally {
      setLoading(false);
    }
  }, [agentId, tierFilter]);

  useEffect(() => {
    loadMemories();
  }, [loadMemories]);

  // Client-side text filter (no semantic search endpoint available)
  const filteredMemories = useMemo(() => {
    if (!searchQuery.trim()) return memories;
    const query = searchQuery.toLowerCase();
    return memories.filter((entry) => {
      const keyMatch = entry.key?.toLowerCase().includes(query);
      const valueMatch = formatValue(entry.value).toLowerCase().includes(query);
      const contentMatch = entry.content?.toLowerCase().includes(query);
      return keyMatch || valueMatch || contentMatch;
    });
  }, [memories, searchQuery]);

  const formatDateRelative = (dateStr: string) => {
    const date = new Date(dateStr);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
  };

  const getContentPreview = (entry: MemoryEntry): string => {
    if (entry.content) return entry.content;
    return formatValue(entry.value).substring(0, 200);
  };

  // Group by date
  const groupedMemories = filteredMemories.reduce((acc, memory) => {
    const dateStr = memory.created_at
      ? new Date(memory.created_at).toLocaleDateString()
      : 'Unknown';
    if (!acc[dateStr]) acc[dateStr] = [];
    acc[dateStr].push(memory);
    return acc;
  }, {} as Record<string, MemoryEntry[]>);

  if (loading && memories.length === 0) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading memories..." />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Filters */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-wrap items-center gap-4">
            <div className="flex-1 min-w-64">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-muted" />
                <Input
                  placeholder="Filter by key or value..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-10"
                />
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Filter className="h-4 w-4 text-theme-muted" />
              <Select
                value={tierFilter}
                onChange={(value) => handleTierChange(value as MemoryTier)}
                className="w-48"
              >
                <option value="working">
                  Working{stats ? ` (${stats.working.count})` : ''}
                </option>
                <option value="short_term">
                  Short-Term{stats ? ` (${stats.short_term.total})` : ''}
                </option>
                <option value="long_term">
                  Long-Term{stats ? ` (${stats.long_term.total})` : ''}
                </option>
                <option value="shared">
                  Shared{stats ? ` (${stats.shared.total})` : ''}
                </option>
              </Select>
            </div>

            <span className="text-sm text-theme-muted whitespace-nowrap">
              {filteredMemories.length} {filteredMemories.length === 1 ? 'entry' : 'entries'}
            </span>

            <Button variant="outline" size="sm" onClick={loadMemories} disabled={loading}>
              <RefreshCw className={cn('h-4 w-4 mr-2', loading && 'animate-spin')} />
              Refresh
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Error state */}
      {error && (
        <div className="p-4 bg-theme-danger/10 border border-theme-danger/30 rounded-lg text-theme-danger">
          {error}
        </div>
      )}

      {/* Empty state */}
      {!loading && filteredMemories.length === 0 && !error && (
        <EmptyState
          icon={Database}
          title="No memories found"
          description={
            searchQuery
              ? 'No entries match your search. Try a different query.'
              : TIER_EMPTY_DESCRIPTIONS[tierFilter] || `This agent has no ${tierFilter.replace(/_/g, ' ')} memories yet.`
          }
        />
      )}

      {/* Timeline */}
      <div className="space-y-6">
        {Object.entries(groupedMemories).map(([date, dayMemories]) => (
          <div key={date}>
            <div className="flex items-center gap-3 mb-3">
              <div className="h-px flex-1 bg-theme-border" />
              <span className="text-sm font-medium text-theme-muted px-2">{date}</span>
              <div className="h-px flex-1 bg-theme-border" />
            </div>

            <div className="space-y-3 relative">
              {/* Timeline line */}
              <div className="absolute left-4 top-0 bottom-0 w-px bg-theme-border" />

              {dayMemories.map((entry, idx) => {
                const config = TIER_CONFIG[tierFilter] || TIER_CONFIG.short_term;
                const entryId = entry.id || `${entry.key}-${idx}`;
                const isExpanded = expandedEntries.has(entryId);

                return (
                  <Card
                    key={entryId}
                    className="ml-8 cursor-pointer hover:border-theme-primary/50 transition-colors"
                    onClick={() => {
                      toggleExpanded(entryId);
                      onSelectMemory?.(entry);
                    }}
                  >
                    <CardContent className="p-4">
                      {/* Timeline dot */}
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
                            <p className="text-sm text-theme-secondary mt-1 line-clamp-2">
                              {getContentPreview(entry)}
                            </p>
                          )}

                          {/* Expanded: full JSON + metadata */}
                          {isExpanded && (
                            <div className="mt-2 space-y-2">
                              <pre className="text-sm text-theme-secondary bg-theme-surface rounded p-3 overflow-x-auto max-h-64 overflow-y-auto">
                                <code>{formatValue(entry.value)}</code>
                              </pre>
                              <div className="flex flex-wrap items-center gap-3 text-xs text-theme-muted">
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

                          <div className="flex items-center gap-4 mt-2 text-xs text-theme-muted">
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

                        {/* Actions: delete + expand toggle */}
                        <div className="flex items-center gap-1 shrink-0">
                          {onDeleteEntry && (
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={(e) => {
                                e.stopPropagation();
                                onDeleteEntry(entry);
                              }}
                              className="text-theme-danger hover:text-theme-danger"
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          )}
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation();
                              toggleExpanded(entryId);
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
      </div>
    </div>
  );
};

export default MemoryTimeline;
