import React, { useState, useEffect, useCallback } from 'react';
import {
  Clock,
  Brain,
  Lightbulb,
  Activity,
  CheckCircle,
  XCircle,
  Filter,
  RefreshCw,
  Search,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { memoryApiService } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { MemoryEntry, MemoryType, MemoryFilters } from '@/shared/services/ai/types/memory-types';

interface MemoryTimelineProps {
  agentId: string;
  onSelectMemory?: (memory: MemoryEntry) => void;
  className?: string;
}

const memoryTypeConfig: Record<MemoryType, { icon: React.FC<{ className?: string }>; color: string; label: string }> = {
  factual: { icon: Brain, color: 'text-theme-info', label: 'Factual' },
  experiential: { icon: Lightbulb, color: 'text-theme-warning', label: 'Experiential' },
  working: { icon: Activity, color: 'text-theme-success', label: 'Working' },
};

export const MemoryTimeline: React.FC<MemoryTimelineProps> = ({
  agentId,
  onSelectMemory,
  className,
}) => {
  const [memories, setMemories] = useState<MemoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [memoryTypeFilter, setMemoryTypeFilter] = useState<MemoryType | ''>('');
  const [outcomeFilter, setOutcomeFilter] = useState<string>('');

  const loadMemories = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: MemoryFilters = { limit: 50 };
      if (memoryTypeFilter) filters.memory_type = memoryTypeFilter;
      if (outcomeFilter === 'success') filters.outcome_success = true;
      if (outcomeFilter === 'failure') filters.outcome_success = false;

      const response = await memoryApiService.getMemories(agentId, filters);
      setMemories(response.items || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load memories');
    } finally {
      setLoading(false);
    }
  }, [agentId, memoryTypeFilter, outcomeFilter]);

  useEffect(() => {
    loadMemories();
  }, [loadMemories]);

  const handleSearch = async () => {
    if (!searchQuery.trim()) {
      loadMemories();
      return;
    }

    try {
      setLoading(true);
      const response = await memoryApiService.searchMemories(agentId, {
        query: searchQuery,
        memory_type: memoryTypeFilter || undefined,
        limit: 50,
      });
      setMemories(response.results || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Search failed');
    } finally {
      setLoading(false);
    }
  };

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
  };

  const getContentPreview = (memory: MemoryEntry): string => {
    if (memory.content_text) return memory.content_text;
    if (typeof memory.content === 'object' && memory.content !== null) {
      if ('text' in memory.content && typeof memory.content.text === 'string') {
        return memory.content.text;
      }
      return JSON.stringify(memory.content).substring(0, 100);
    }
    return String(memory.content);
  };

  // Group by date
  const groupedMemories = memories.reduce((acc, memory) => {
    const date = new Date(memory.created_at).toLocaleDateString();
    if (!acc[date]) acc[date] = [];
    acc[date].push(memory);
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
                  placeholder="Semantic search..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
                  className="pl-10"
                />
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Filter className="h-4 w-4 text-theme-muted" />
              <Select
                value={memoryTypeFilter}
                onChange={(e) => setMemoryTypeFilter(e.target.value as MemoryType | '')}
                className="w-32"
              >
                <option value="">All Types</option>
                <option value="factual">Factual</option>
                <option value="experiential">Experiential</option>
                <option value="working">Working</option>
              </Select>

              <Select
                value={outcomeFilter}
                onChange={(e) => setOutcomeFilter(e.target.value)}
                className="w-32"
              >
                <option value="">All Outcomes</option>
                <option value="success">Successful</option>
                <option value="failure">Failed</option>
              </Select>
            </div>

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
      {!loading && memories.length === 0 && !error && (
        <EmptyState
          icon={Brain}
          title="No memories found"
          description="This agent hasn't stored any memories yet"
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

              {dayMemories.map((memory) => {
                const config = memoryTypeConfig[memory.memory_type];
                const TypeIcon = config.icon;

                return (
                  <Card
                    key={memory.id}
                    className="ml-8 cursor-pointer hover:border-theme-primary/50 transition-colors"
                    onClick={() => onSelectMemory?.(memory)}
                  >
                    <CardContent className="p-4">
                      {/* Timeline dot */}
                      <div
                        className={cn(
                          'absolute -left-2 w-4 h-4 rounded-full bg-theme-surface border-2',
                          memory.outcome_success === true && 'border-theme-success',
                          memory.outcome_success === false && 'border-theme-danger',
                          memory.outcome_success === undefined && 'border-theme-muted'
                        )}
                      />

                      <div className="flex items-start justify-between gap-3">
                        <div className="flex items-start gap-3 flex-1 min-w-0">
                          <div className={cn('p-2 rounded-lg bg-theme-surface', config.color)}>
                            <TypeIcon className="h-4 w-4" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className="font-medium text-theme-primary font-mono text-sm">
                                {memory.entry_key}
                              </span>
                              <Badge variant="outline" size="sm" className={config.color}>
                                {config.label}
                              </Badge>
                              {memory.outcome_success === true && (
                                <CheckCircle className="h-4 w-4 text-theme-success" />
                              )}
                              {memory.outcome_success === false && (
                                <XCircle className="h-4 w-4 text-theme-danger" />
                              )}
                            </div>
                            <p className="text-sm text-theme-secondary mt-1 line-clamp-2">
                              {getContentPreview(memory)}
                            </p>
                            <div className="flex items-center gap-4 mt-2 text-xs text-theme-muted">
                              <span className="flex items-center gap-1">
                                <Clock className="h-3 w-3" />
                                {formatDate(memory.created_at)}
                              </span>
                              <span>
                                Importance: {Math.round(memory.importance_score * 100)}%
                              </span>
                              {memory.access_count > 0 && (
                                <span>{memory.access_count} accesses</span>
                              )}
                            </div>
                            {memory.context_tags?.length > 0 && (
                              <div className="flex flex-wrap gap-1 mt-2">
                                {memory.context_tags.slice(0, 5).map((tag) => (
                                  <Badge key={tag} variant="outline" size="sm">
                                    {tag}
                                  </Badge>
                                ))}
                                {memory.context_tags.length > 5 && (
                                  <Badge variant="outline" size="sm">
                                    +{memory.context_tags.length - 5}
                                  </Badge>
                                )}
                              </div>
                            )}
                          </div>
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
