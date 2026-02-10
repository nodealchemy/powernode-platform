import React from 'react';
import { Lightbulb, ChevronRight, DollarSign, AlertTriangle, CheckCircle, XCircle } from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { useOptimizationScore } from '../api/finopsApi';
import type { RecommendationPriority, RecommendationStatus } from '../types/finops';

const formatCost = (cost: number): string => {
  if (cost <= 0) return '$0.00';
  if (cost < 0.01) return `$${cost.toFixed(4)}`;
  if (cost >= 1000) return `$${(cost / 1000).toFixed(1)}K`;
  return `$${cost.toFixed(2)}`;
};

const PRIORITY_VARIANTS: Record<RecommendationPriority, 'danger' | 'warning' | 'info' | 'default'> = {
  critical: 'danger',
  high: 'warning',
  medium: 'default',
  low: 'info',
};

const STATUS_ICONS: Record<RecommendationStatus, React.FC<{ className?: string }>> = {
  pending: AlertTriangle,
  applied: CheckCircle,
  dismissed: XCircle,
};

export const OptimizationRecommendations: React.FC = () => {
  const { data: optimization, isLoading } = useOptimizationScore();

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-8" />;
  }

  if (!optimization || optimization.recommendations.length === 0) {
    return (
      <EmptyState
        icon={Lightbulb}
        title="No recommendations"
        description="Your AI cost configuration is already optimized, or there is not enough data yet to generate recommendations."
      />
    );
  }

  const { recommendations, score, max_score, potential_savings } = optimization;
  const pendingRecs = recommendations.filter((r) => r.status === 'pending');
  const appliedRecs = recommendations.filter((r) => r.status === 'applied');

  return (
    <div className="space-y-6">
      {/* Score Summary */}
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="h-12 w-12 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
              <Lightbulb className="h-6 w-6 text-theme-success" />
            </div>
            <div>
              <p className="text-sm text-theme-tertiary">Optimization Score</p>
              <p className="text-2xl font-bold text-theme-primary">
                {score} <span className="text-sm font-normal text-theme-tertiary">/ {max_score}</span>
              </p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-sm text-theme-tertiary">Potential Savings</p>
            <p className="text-xl font-bold text-theme-success">{formatCost(potential_savings)}</p>
            <p className="text-xs text-theme-tertiary">
              {pendingRecs.length} pending, {appliedRecs.length} applied
            </p>
          </div>
        </div>

        {/* Score progress bar */}
        <div className="mt-4">
          <div className="w-full bg-theme-accent rounded-full h-2">
            <div
              className="h-2 rounded-full bg-theme-success transition-all"
              style={{ width: `${max_score > 0 ? (score / max_score) * 100 : 0}%` }}
            />
          </div>
        </div>
      </Card>

      {/* Recommendations List */}
      <Card>
        <CardHeader title="Recommendations" />
        <CardContent>
          <div className="space-y-3">
            {recommendations.map((rec) => {
              const StatusIcon = STATUS_ICONS[rec.status];

              return (
                <div
                  key={rec.id}
                  className={`p-4 rounded-lg border bg-theme-surface ${
                    rec.status === 'applied'
                      ? 'border-theme-success opacity-70'
                      : rec.status === 'dismissed'
                        ? 'border-theme opacity-50'
                        : 'border-theme'
                  }`}
                >
                  <div className="flex items-start gap-3">
                    <div className="flex-shrink-0 mt-0.5">
                      <StatusIcon className={`h-5 w-5 ${
                        rec.status === 'applied' ? 'text-theme-success' :
                        rec.status === 'dismissed' ? 'text-theme-tertiary' :
                        'text-theme-warning'
                      }`} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-sm font-medium text-theme-primary">{rec.title}</span>
                        <Badge variant={PRIORITY_VARIANTS[rec.priority]} size="xs">
                          {rec.priority}
                        </Badge>
                        <Badge variant="default" size="xs">
                          {rec.category}
                        </Badge>
                      </div>
                      <p className="text-sm text-theme-secondary">{rec.description}</p>
                      {rec.affected_resources.length > 0 && (
                        <div className="flex flex-wrap gap-1 mt-2">
                          {rec.affected_resources.map((resource) => (
                            <span
                              key={resource}
                              className="text-xs px-2 py-0.5 rounded bg-theme-accent text-theme-tertiary"
                            >
                              {resource}
                            </span>
                          ))}
                        </div>
                      )}
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <div className="flex items-center gap-1 text-theme-success">
                        <DollarSign className="h-4 w-4" />
                        <span className="text-sm font-semibold">{formatCost(rec.potential_savings)}</span>
                      </div>
                      <ChevronRight className="h-4 w-4 text-theme-tertiary" />
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
