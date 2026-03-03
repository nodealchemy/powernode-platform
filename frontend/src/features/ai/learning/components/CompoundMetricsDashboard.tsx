import React, { useState, useCallback, useEffect } from 'react';
import { BarChart3, TrendingUp, Zap, Target, Award } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { fetchCompoundMetrics, CompoundMetrics, CompoundLearning } from '../services/compoundLearningApi';

const CATEGORY_COLORS: Record<string, string> = {
  pattern: 'info',
  anti_pattern: 'danger',
  best_practice: 'success',
  discovery: 'warning',
  fact: 'default',
  failure_mode: 'danger',
  review_finding: 'warning',
  performance_insight: 'info',
};

const ScoreGauge: React.FC<{ score: number; label: string }> = ({ score, label }) => {
  const percentage = Math.round(score);
  const getColor = () => {
    if (percentage >= 70) return 'text-theme-success';
    if (percentage >= 40) return 'text-theme-warning';
    return 'text-theme-error';
  };

  return (
    <div className="flex flex-col items-center">
      <div className="relative w-24 h-24">
        <svg className="w-24 h-24 transform -rotate-90" viewBox="0 0 36 36">
          <circle cx="18" cy="18" r="15.91" fill="none" className="stroke-theme-border" strokeWidth="3" />
          <circle
            cx="18" cy="18" r="15.91" fill="none"
            className={getColor().replace('text-', 'stroke-')}
            strokeWidth="3"
            strokeDasharray={`${percentage} ${100 - percentage}`}
            strokeLinecap="round"
          />
        </svg>
        <div className="absolute inset-0 flex items-center justify-center">
          <span className={`text-lg font-bold ${getColor()}`}>{percentage}%</span>
        </div>
      </div>
      <span className="text-xs text-theme-muted mt-1">{label}</span>
    </div>
  );
};

const LearningRow: React.FC<{ learning: CompoundLearning }> = ({ learning }) => (
  <div className="flex items-start gap-3 p-3 rounded-lg bg-theme-surface border border-theme-border">
    <Badge variant={(CATEGORY_COLORS[learning.category] || 'default') as 'info' | 'danger' | 'success' | 'warning' | 'default'}>
      {learning.category.replace('_', ' ')}
    </Badge>
    <div className="flex-1 min-w-0">
      <p className="text-sm font-medium text-theme-primary truncate">
        {learning.title || learning.content.substring(0, 80)}
      </p>
      <p className="text-xs text-theme-muted mt-0.5 line-clamp-2">{learning.content}</p>
    </div>
    <div className="text-right shrink-0">
      {learning.effectiveness_score !== null && (
        <p className="text-xs text-theme-muted">
          {Math.round(learning.effectiveness_score * 100)}% effective
        </p>
      )}
      <p className="text-xs text-theme-muted">{learning.injection_count} uses</p>
    </div>
  </div>
);

export const CompoundMetricsDashboard: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [metrics, setMetrics] = useState<CompoundMetrics | null>(null);
  const { addNotification } = useNotifications();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const data = await fetchCompoundMetrics();
      setMetrics(data);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to load compound metrics' });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  if (loading) return <LoadingSpinner />;
  if (!metrics) return null;

  const categoryEntries = Object.entries(metrics.by_category).sort(([, a], [, b]) => b - a);

  return (
    <div className="space-y-6">
      {/* Top-level metrics */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
        <Card>
          <CardContent className="p-4 flex flex-col items-center">
            <ScoreGauge score={metrics.compound_score} label="Compound Score" />
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <Zap className="w-8 h-8 text-theme-primary" />
            <div>
              <p className="text-sm text-theme-muted">Active</p>
              <p className="text-2xl font-bold text-theme-primary">{metrics.active_learnings}</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <BarChart3 className="w-8 h-8 text-theme-info" />
            <div>
              <p className="text-sm text-theme-muted">Total</p>
              <p className="text-2xl font-bold text-theme-primary">{metrics.total_learnings}</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <Target className="w-8 h-8 text-theme-warning" />
            <div>
              <p className="text-sm text-theme-muted">Avg Importance</p>
              <p className="text-2xl font-bold text-theme-primary">{(metrics.avg_importance * 100).toFixed(0)}%</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <TrendingUp className="w-8 h-8 text-theme-success" />
            <div>
              <p className="text-sm text-theme-muted">Avg Effectiveness</p>
              <p className="text-2xl font-bold text-theme-primary">
                {metrics.avg_effectiveness !== null ? `${(metrics.avg_effectiveness * 100).toFixed(0)}%` : 'N/A'}
              </p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Category breakdown */}
      {categoryEntries.length > 0 && (
        <Card>
          <CardHeader title="Learnings by Category" />
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              {categoryEntries.map(([category, count]) => (
                <div key={category} className="flex items-center justify-between p-3 rounded-lg bg-theme-surface border border-theme-border">
                  <Badge variant={(CATEGORY_COLORS[category] || 'default') as 'info' | 'danger' | 'success' | 'warning' | 'default'}>
                    {category.replace('_', ' ')}
                  </Badge>
                  <span className="text-lg font-semibold text-theme-primary">{count}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Most effective learnings */}
      {metrics.most_effective.length > 0 && (
        <Card>
          <CardHeader title="Most Effective Learnings" />
          <CardContent>
            <div className="space-y-2">
              {metrics.most_effective.map((learning) => (
                <LearningRow key={learning.id} learning={learning} />
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Recently added */}
      {metrics.recently_added.length > 0 && (
        <Card>
          <CardHeader title="Recently Added" />
          <CardContent>
            <div className="space-y-2">
              {metrics.recently_added.slice(0, 5).map((learning) => (
                <LearningRow key={learning.id} learning={learning} />
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {metrics.active_learnings === 0 && (
        <Card>
          <CardContent className="p-8 text-center">
            <Award className="w-12 h-12 mx-auto mb-4 text-theme-warning opacity-40" />
            <p className="text-theme-primary font-medium mb-2">No compound learnings yet</p>
            <p className="text-sm text-theme-muted max-w-md mx-auto mb-4">
              Learnings are automatically extracted when agent teams execute tasks.
              Each execution can produce insights across several categories:
            </p>
            <div className="flex flex-wrap justify-center gap-2 mb-4">
              <Badge variant="info">patterns</Badge>
              <Badge variant="success">best practices</Badge>
              <Badge variant="warning">discoveries</Badge>
              <Badge variant="danger">failure modes</Badge>
            </div>
            <p className="text-xs text-theme-muted max-w-sm mx-auto">
              As learnings accumulate, their effectiveness is tracked and the most impactful
              ones are promoted across teams to improve future executions.
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  );
};
