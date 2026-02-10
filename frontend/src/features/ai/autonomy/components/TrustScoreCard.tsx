import React from 'react';
import { Shield, TrendingUp, TrendingDown } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { TrustScore } from '../types/autonomy';

const TIER_CONFIG: Record<TrustScore['tier'], { label: string; variant: 'warning' | 'info' | 'success' | 'default' }> = {
  supervised: { label: 'Supervised', variant: 'warning' },
  monitored: { label: 'Monitored', variant: 'info' },
  trusted: { label: 'Trusted', variant: 'success' },
  autonomous: { label: 'Autonomous', variant: 'default' },
};

const DIMENSIONS: { key: keyof Pick<TrustScore, 'reliability' | 'cost_efficiency' | 'safety' | 'quality' | 'speed'>; label: string }[] = [
  { key: 'reliability', label: 'Reliability' },
  { key: 'cost_efficiency', label: 'Cost Efficiency' },
  { key: 'safety', label: 'Safety' },
  { key: 'quality', label: 'Quality' },
  { key: 'speed', label: 'Speed' },
];

interface TrustScoreCardProps {
  score: TrustScore;
}

export const TrustScoreCard: React.FC<TrustScoreCardProps> = ({ score }) => {
  const tierConfig = TIER_CONFIG[score.tier];

  const getBarColor = (value: number): string => {
    if (value >= 0.7) return 'bg-theme-success';
    if (value >= 0.4) return 'bg-theme-warning';
    return 'bg-theme-error';
  };

  const formatDate = (dateStr?: string): string => {
    if (!dateStr) return 'Never';
    return new Date(dateStr).toLocaleDateString();
  };

  return (
    <Card className="p-0 overflow-hidden">
      <CardContent className="p-4">
        <div className="flex items-start justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
              <Shield className="h-5 w-5 text-theme-info" />
            </div>
            <div>
              <h3 className="font-semibold text-theme-primary">{score.agent_name}</h3>
              <div className="flex items-center gap-2 mt-0.5">
                <Badge variant={tierConfig.variant} size="sm">{tierConfig.label}</Badge>
                {score.promotable && (
                  <span className="inline-flex items-center gap-0.5 text-xs text-theme-success">
                    <TrendingUp className="h-3 w-3" /> Promotable
                  </span>
                )}
                {score.demotable && (
                  <span className="inline-flex items-center gap-0.5 text-xs text-theme-error">
                    <TrendingDown className="h-3 w-3" /> Demotable
                  </span>
                )}
              </div>
            </div>
          </div>
          <div className="text-right">
            <p className="text-2xl font-bold text-theme-primary">
              {Math.round(score.overall_score * 100)}
            </p>
            <p className="text-xs text-theme-muted">Overall</p>
          </div>
        </div>

        <div className="space-y-2">
          {DIMENSIONS.map(({ key, label }) => {
            const value = score[key];
            const pct = Math.round(value * 100);
            return (
              <div key={key} className="flex items-center gap-3">
                <span className="text-xs text-theme-muted w-24 shrink-0">{label}</span>
                <div className="flex-1 h-2 rounded-full bg-theme-border overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all ${getBarColor(value)}`}
                    style={{ width: `${pct}%` }}
                  />
                </div>
                <span className="text-xs font-medium text-theme-primary w-8 text-right">{pct}%</span>
              </div>
            );
          })}
        </div>

        <div className="flex items-center justify-between mt-4 pt-3 border-t border-theme-border text-xs text-theme-muted">
          <span>{score.evaluation_count} evaluations</span>
          <span>Last: {formatDate(score.last_evaluated_at)}</span>
        </div>
      </CardContent>
    </Card>
  );
};
