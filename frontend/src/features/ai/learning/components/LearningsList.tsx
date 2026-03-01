import React, { useState, useCallback, useEffect } from 'react';
import { Search, ThumbsUp, Filter, BookOpen } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { fetchLearnings, reinforceLearning, CompoundLearning, LearningFilters } from '../services/compoundLearningApi';

const CATEGORIES = [
  'pattern', 'anti_pattern', 'best_practice', 'discovery',
  'fact', 'failure_mode', 'review_finding', 'performance_insight'
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
};

export const LearningsList: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [learnings, setLearnings] = useState<CompoundLearning[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('');
  const [selectedScope, setSelectedScope] = useState('');
  const [reinforcing, setReinforcing] = useState<string | null>(null);
  const { addNotification } = useNotifications();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const filters: LearningFilters = { limit: 100 };
      if (searchQuery) filters.query = searchQuery;
      if (selectedCategory) filters.category = selectedCategory;
      if (selectedScope) filters.scope = selectedScope;

      const data = await fetchLearnings(filters);
      setLearnings(data);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to load learnings' });
    } finally {
      setLoading(false);
    }
  }, [searchQuery, selectedCategory, selectedScope, addNotification]);

  useEffect(() => {
    const debounce = setTimeout(loadData, 300);
    return () => clearTimeout(debounce);
  }, [loadData]);

  const handleReinforce = async (id: string) => {
    try {
      setReinforcing(id);
      await reinforceLearning(id);
      addNotification({ type: 'success', message: 'Learning reinforced' });
      loadData();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to reinforce learning' });
    } finally {
      setReinforcing(null);
    }
  };

  const ImportanceBar: React.FC<{ value: number }> = ({ value }) => {
    const width = Math.round(value * 100);
    const color = width >= 70 ? 'bg-theme-success' : width >= 40 ? 'bg-theme-warning' : 'bg-theme-error';
    return (
      <div className="w-16 h-1.5 rounded-full bg-theme-border">
        <div className={`h-full rounded-full ${color}`} style={{ width: `${width}%` }} />
      </div>
    );
  };

  return (
    <div className="space-y-4">
      {/* Filters */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-wrap gap-3 items-center">
            <div className="relative flex-1 min-w-[200px]">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-muted" />
              <input
                type="text"
                placeholder="Search learnings..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-sm rounded-lg bg-theme-surface border border-theme-border text-theme-primary placeholder:text-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-primary"
              />
            </div>
            <div className="flex items-center gap-2">
              <Filter className="w-4 h-4 text-theme-muted" />
              <select
                value={selectedCategory}
                onChange={(e) => setSelectedCategory(e.target.value)}
                className="text-sm rounded-lg bg-theme-surface border border-theme-border text-theme-primary py-2 px-3 focus:outline-none focus:ring-2 focus:ring-theme-primary"
              >
                <option value="">All Categories</option>
                {CATEGORIES.map((cat) => (
                  <option key={cat} value={cat}>{cat.replace('_', ' ')}</option>
                ))}
              </select>
              <select
                value={selectedScope}
                onChange={(e) => setSelectedScope(e.target.value)}
                className="text-sm rounded-lg bg-theme-surface border border-theme-border text-theme-primary py-2 px-3 focus:outline-none focus:ring-2 focus:ring-theme-primary"
              >
                <option value="">All Scopes</option>
                <option value="team">Team</option>
                <option value="global">Global</option>
              </select>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Results */}
      {loading ? (
        <LoadingSpinner />
      ) : learnings.length === 0 ? (
        <Card>
          <CardContent className="p-8 text-center text-theme-muted">
            <BookOpen className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>No learnings found matching your filters.</p>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader title={`${learnings.length} Learnings`} />
          <CardContent>
            <div className="space-y-2">
              {learnings.map((learning) => (
                <div
                  key={learning.id}
                  className="flex items-start gap-3 p-3 rounded-lg bg-theme-surface border border-theme-border hover:border-theme-primary transition-colors"
                >
                  <div className="shrink-0 mt-0.5">
                    <Badge variant={CATEGORY_BADGE_VARIANT[learning.category] || 'default'}>
                      {learning.category.replace('_', ' ')}
                    </Badge>
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="text-sm font-medium text-theme-primary truncate">
                        {learning.title || learning.content.substring(0, 80)}
                      </p>
                      {learning.scope === 'global' && (
                        <Badge variant="info">global</Badge>
                      )}
                    </div>
                    <p className="text-xs text-theme-secondary mt-0.5 line-clamp-2">{learning.content}</p>
                    <div className="flex items-center gap-4 mt-2 text-xs text-theme-muted">
                      <span className="flex items-center gap-1">
                        Importance: <ImportanceBar value={learning.importance_score} />
                      </span>
                      {learning.effectiveness_score !== null && (
                        <span>{Math.round(learning.effectiveness_score * 100)}% effective</span>
                      )}
                      <span>{learning.injection_count} injections</span>
                      <span>{learning.extraction_method}</span>
                    </div>
                  </div>
                  <button
                    onClick={() => handleReinforce(learning.id)}
                    disabled={reinforcing === learning.id}
                    className="shrink-0 p-2 rounded-md hover:bg-theme-surface-hover text-theme-muted hover:text-theme-success transition-colors disabled:opacity-50"
                    title="Mark as useful"
                  >
                    <ThumbsUp className="w-4 h-4" />
                  </button>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
};
