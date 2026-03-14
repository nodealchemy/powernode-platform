import { useState, useEffect } from 'react';
import { BookOpen, ChevronDown, ChevronRight } from 'lucide-react';
import { sharedLearningsApi, type Learning } from '../services/sharedLearningsApi';

const CATEGORY_CONFIG: Record<string, { label: string; color: string }> = {
  fact: { label: 'Facts', color: 'bg-theme-info/10 text-theme-info' },
  pattern: { label: 'Patterns', color: 'bg-theme-success/10 text-theme-success' },
  anti_pattern: { label: 'Anti-Patterns', color: 'bg-theme-danger/10 text-theme-danger' },
  best_practice: { label: 'Best Practices', color: 'bg-theme-accent/10 text-theme-accent' },
  discovery: { label: 'Discoveries', color: 'bg-theme-warning/10 text-theme-warning' },
};

function ImportanceBadge({ importance }: { importance: number }) {
  const level = importance >= 0.8 ? 'High' : importance >= 0.6 ? 'Medium' : 'Low';
  const className = importance >= 0.8
    ? 'bg-theme-error/10 text-theme-error'
    : importance >= 0.6
      ? 'bg-theme-warning/10 text-theme-warning'
      : 'bg-theme-secondary/10 text-theme-secondary';

  return (
    <span className={`px-1.5 py-0.5 text-xs rounded ${className}`}>
      {level}
    </span>
  );
}

interface CategorySectionProps {
  category: string;
  learnings: Learning[];
}

function CategorySection({ category, learnings }: CategorySectionProps) {
  const [expanded, setExpanded] = useState(true);
  const config = CATEGORY_CONFIG[category] || { label: category, color: 'bg-theme-accent text-theme-primary' };

  return (
    <div className="border border-theme rounded-lg overflow-hidden">
      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center justify-between px-4 py-3 bg-theme-surface hover:bg-theme-surface-hover transition-colors"
      >
        <div className="flex items-center gap-2">
          {expanded ? <ChevronDown className="h-4 w-4 text-theme-secondary" /> : <ChevronRight className="h-4 w-4 text-theme-secondary" />}
          <span className={`px-2 py-0.5 text-xs font-medium rounded-full ${config.color}`}>
            {config.label}
          </span>
          <span className="text-xs text-theme-secondary">({learnings.length})</span>
        </div>
      </button>
      {expanded && (
        <div className="divide-y divide-theme">
          {learnings.map((learning, idx) => (
            <div key={idx} className="px-4 py-3 flex items-start justify-between gap-4">
              <p className="text-sm text-theme-primary flex-1">{learning.content}</p>
              <ImportanceBadge importance={learning.importance || 0.5} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

interface SharedLearningsPanelProps {
  poolId?: string;
}

export function SharedLearningsPanel({ poolId }: SharedLearningsPanelProps) {
  const [learnings, setLearnings] = useState<Learning[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      try {
        const data = poolId
          ? await sharedLearningsApi.fetchPoolLearnings(poolId)
          : await sharedLearningsApi.fetchGlobalLearnings();
        setLearnings(data);
      } catch {
        // Silently handle
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [poolId]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
      </div>
    );
  }

  if (learnings.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <BookOpen size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No Shared Learnings</h3>
        <p className="text-theme-secondary text-sm">
          Learnings will appear here as agents discover patterns and facts during execution.
        </p>
      </div>
    );
  }

  // Group by category
  const grouped = learnings.reduce<Record<string, Learning[]>>((acc, l) => {
    const cat = l.category || 'discovery';
    if (!acc[cat]) acc[cat] = [];
    acc[cat].push(l);
    return acc;
  }, {});

  const categoryOrder = ['anti_pattern', 'best_practice', 'pattern', 'discovery', 'fact'];

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 mb-2">
        <BookOpen className="h-4 w-4 text-theme-primary" />
        <h4 className="text-sm font-semibold text-theme-primary">
          Shared Learnings ({learnings.length})
        </h4>
      </div>
      {categoryOrder
        .filter((cat) => grouped[cat]?.length)
        .map((cat) => (
          <CategorySection key={cat} category={cat} learnings={grouped[cat]} />
        ))}
    </div>
  );
}
