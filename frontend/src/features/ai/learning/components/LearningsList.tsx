import React, { useState, useCallback, useEffect, useRef } from 'react';
import { Search, ThumbsUp, Filter, BookOpen, ArrowUpDown, ChevronDown, ChevronUp, Maximize2, Minimize2 } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  fetchLearnings,
  reinforceLearning,
  CompoundLearning,
  LearningFilters,
  SortField,
  SortDir,
} from '../services/compoundLearningApi';

const PAGE_SIZE = 50;

const CATEGORIES = [
  'pattern', 'anti_pattern', 'best_practice', 'discovery',
  'fact', 'failure_mode', 'review_finding', 'performance_insight', 'reflexion',
];

const CATEGORY_BADGE_VARIANT: Record<string, 'info' | 'danger' | 'success' | 'warning' | 'default'> = {
  pattern: 'info',
  anti_pattern: 'danger',
  best_practice: 'success',
  discovery: 'warning',
  fact: 'default',
  failure_mode: 'danger',
  review_finding: 'warning',
  performance_insight: 'info',
  reflexion: 'warning',
};

const SORT_OPTIONS: { value: SortField; label: string }[] = [
  { value: 'created_at', label: 'Newest' },
  { value: 'importance_score', label: 'Importance' },
  { value: 'effectiveness_score', label: 'Effectiveness' },
  { value: 'injection_count', label: 'Most Used' },
  { value: 'confidence_score', label: 'Confidence' },
];

interface LearningsListProps {
  refreshKey?: number;
}

export const LearningsList: React.FC<LearningsListProps> = ({ refreshKey = 0 }) => {
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [learnings, setLearnings] = useState<CompoundLearning[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('');
  const [selectedScope, setSelectedScope] = useState('');
  const [sortBy, setSortBy] = useState<SortField>('created_at');
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const [reinforcing, setReinforcing] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [isListExpanded, setIsListExpanded] = useState(false);
  const { addNotification } = useNotifications();
  const sentinelRef = useRef<HTMLDivElement>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const hasMore = learnings.length < totalCount;

  const loadData = useCallback(async (append = false) => {
    try {
      if (append) {
        setLoadingMore(true);
      } else {
        setLoading(true);
      }

      const filters: LearningFilters = {
        limit: PAGE_SIZE,
        offset: append ? learnings.length : 0,
        sort_by: sortBy,
        sort_dir: sortDir,
      };
      if (searchQuery) filters.query = searchQuery;
      if (selectedCategory) filters.category = selectedCategory;
      if (selectedScope) filters.scope = selectedScope;

      const result = await fetchLearnings(filters);

      if (append) {
        setLearnings((prev) => [...prev, ...result.learnings]);
      } else {
        setLearnings(result.learnings);
      }
      setTotalCount(result.meta.total_count);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to load learnings' });
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [searchQuery, selectedCategory, selectedScope, sortBy, sortDir, learnings.length, addNotification]);

  // Reset and reload on filter/sort/refresh changes
  useEffect(() => {
    const debounce = setTimeout(() => loadData(false), 300);
    return () => clearTimeout(debounce);
  }, [searchQuery, selectedCategory, selectedScope, sortBy, sortDir, refreshKey]);

  // Infinite scroll via IntersectionObserver
  // When collapsed: scoped to scroll container. When expanded: scoped to page viewport.
  useEffect(() => {
    if (!sentinelRef.current || !hasMore || loadingMore || loading) return;

    const root = isListExpanded ? null : scrollContainerRef.current;
    if (!isListExpanded && !root) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasMore && !loadingMore) {
          loadData(true);
        }
      },
      { root, rootMargin: '200px' }
    );

    observer.observe(sentinelRef.current);
    return () => observer.disconnect();
  }, [hasMore, loadingMore, loading, loadData, isListExpanded]);

  const handleReinforce = async (e: React.MouseEvent, id: string) => {
    e.stopPropagation();
    try {
      setReinforcing(id);
      await reinforceLearning(id);
      addNotification({ type: 'success', message: 'Learning reinforced' });
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to reinforce learning' });
    } finally {
      setReinforcing(null);
    }
  };

  const handleSort = (field: SortField) => {
    if (sortBy === field) {
      setSortDir((d) => (d === 'desc' ? 'asc' : 'desc'));
    } else {
      setSortBy(field);
      setSortDir('desc');
    }
  };

  const ImportanceBar: React.FC<{ value: number }> = ({ value }) => {
    const pct = Math.round(value * 100);
    const color = pct >= 70 ? 'bg-theme-success' : pct >= 40 ? 'bg-theme-warning' : 'bg-theme-error';
    return (
      <span className="inline-flex items-center gap-1.5">
        <span className="w-20 h-2.5 rounded-full bg-theme-surface-hover inline-block">
          <span className={`block h-full rounded-full ${color}`} style={{ width: `${pct}%` }} />
        </span>
        <span className="text-theme-secondary tabular-nums">{pct}%</span>
      </span>
    );
  };

  return (
    <div className="space-y-4">
      {/* Filters & Sort */}
      <div className="flex flex-wrap gap-3 items-center">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
          <input
            type="text"
            placeholder="Search learnings..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg bg-theme-surface border border-theme text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          />
        </div>
        <div className="flex items-center gap-2">
          <Filter className="w-4 h-4 text-theme-tertiary" />
          <select
            value={selectedCategory}
            onChange={(e) => setSelectedCategory(e.target.value)}
            className="text-sm rounded-lg bg-theme-surface border border-theme text-theme-primary py-2 px-3 focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            <option value="">All Categories</option>
            {CATEGORIES.map((cat) => (
              <option key={cat} value={cat}>{cat.replace(/_/g, ' ')}</option>
            ))}
          </select>
          <select
            value={selectedScope}
            onChange={(e) => setSelectedScope(e.target.value)}
            className="text-sm rounded-lg bg-theme-surface border border-theme text-theme-primary py-2 px-3 focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            <option value="">All Scopes</option>
            <option value="team">Team</option>
            <option value="global">Global</option>
          </select>
          <div className="flex items-center gap-1 ml-2">
            <ArrowUpDown className="w-4 h-4 text-theme-tertiary" />
            {SORT_OPTIONS.map((opt) => (
              <button
                key={opt.value}
                onClick={() => handleSort(opt.value)}
                className={`px-2 py-1 text-xs rounded transition-colors ${
                  sortBy === opt.value
                    ? 'bg-theme-info/20 text-theme-info font-medium'
                    : 'text-theme-tertiary hover:text-theme-primary hover:bg-theme-surface-hover'
                }`}
              >
                {opt.label}
                {sortBy === opt.value && (
                  sortDir === 'desc'
                    ? <ChevronDown className="inline w-3 h-3 ml-0.5" />
                    : <ChevronUp className="inline w-3 h-3 ml-0.5" />
                )}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Count + expand toggle */}
      {!loading && learnings.length > 0 && (
        <div className="flex items-center justify-between">
          <p className="text-xs text-theme-tertiary">
            Showing {learnings.length} of {totalCount.toLocaleString()} learnings
          </p>
          <button
            onClick={() => setIsListExpanded((v) => !v)}
            className="flex items-center gap-1 text-xs text-theme-tertiary hover:text-theme-primary transition-colors"
            title={isListExpanded ? 'Collapse to fixed viewport' : 'Expand to full height'}
          >
            {isListExpanded ? <Minimize2 className="w-3.5 h-3.5" /> : <Maximize2 className="w-3.5 h-3.5" />}
            {isListExpanded ? 'Collapse' : 'Expand'}
          </button>
        </div>
      )}

      {/* Scrollable results viewport */}
      {loading ? (
        <LoadingSpinner />
      ) : learnings.length === 0 ? (
        <Card>
          <CardContent className="p-8 text-center text-theme-tertiary">
            <BookOpen className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>No learnings found matching your filters.</p>
          </CardContent>
        </Card>
      ) : (
        <div
          ref={scrollContainerRef}
          className={`space-y-3 pt-2 pr-1 ${isListExpanded ? '' : 'overflow-y-auto'}`}
          style={isListExpanded ? undefined : { maxHeight: 'calc(100vh - 28rem)' }}
        >
          {learnings.map((learning) => {
            const isExpanded = expandedId === learning.id;
            return (
              <div
                key={learning.id}
                onClick={() => setExpandedId(isExpanded ? null : learning.id)}
                className="relative flex items-start gap-3 pt-5 pb-2 px-3 rounded-lg bg-theme-surface border border-theme hover:border-theme-primary transition-colors cursor-pointer"
              >
                <div className="absolute -top-2 left-2 z-10">
                  <Badge variant={CATEGORY_BADGE_VARIANT[learning.category] || 'default'} size="xs">
                    {learning.category.replace(/_/g, ' ')}
                  </Badge>
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium text-theme-primary truncate">
                      {learning.title || learning.content.substring(0, 80)}
                    </p>
                    {learning.scope === 'global' && <Badge variant="info">global</Badge>}
                  </div>
                  <p className={`text-xs text-theme-secondary mt-0.5 ${isExpanded ? 'whitespace-pre-wrap' : 'line-clamp-2'}`}>
                    {learning.content}
                  </p>
                  <div className="flex items-center gap-4 mt-2 text-xs text-theme-tertiary">
                    <ImportanceBar value={learning.importance_score} />
                    {learning.effectiveness_score !== null && (
                      <span>Effectiveness: {Math.round(learning.effectiveness_score * 100)}%</span>
                    )}
                    <span>{learning.injection_count} injections</span>
                    <span>{learning.extraction_method}</span>
                    {learning.tags.length > 0 && (
                      <span className="flex gap-1 flex-wrap">
                        {learning.tags.slice(0, 8).map((tag) => (
                          <span key={tag} className="px-1.5 py-0.5 rounded bg-theme-surface-hover text-theme-tertiary">
                            {tag}
                          </span>
                        ))}
                      </span>
                    )}
                  </div>
                </div>
                <button
                  onClick={(e) => handleReinforce(e, learning.id)}
                  disabled={reinforcing === learning.id}
                  className="shrink-0 p-2 rounded-md hover:bg-theme-surface-hover text-theme-tertiary hover:text-theme-success transition-colors disabled:opacity-50"
                  title="Mark as useful"
                >
                  <ThumbsUp className="w-4 h-4" />
                </button>
              </div>
            );
          })}

          {/* Infinite scroll sentinel */}
          <div ref={sentinelRef} className="h-1" />
          {loadingMore && (
            <div className="flex justify-center py-4">
              <LoadingSpinner />
            </div>
          )}
        </div>
      )}
    </div>
  );
};
