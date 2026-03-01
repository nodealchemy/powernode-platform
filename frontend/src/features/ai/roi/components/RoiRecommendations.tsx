import React from 'react';
import {
  DollarSign,
  Lightbulb,
  TrendingUp,
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { RoiRecommendation } from '@/shared/services/ai';

interface RoiRecommendationsProps {
  recommendations: RoiRecommendation[];
  formatCurrency: (amount: number) => string;
}

export const RoiRecommendations: React.FC<RoiRecommendationsProps> = ({
  recommendations,
  formatCurrency,
}) => {
  if (recommendations.length === 0) return null;

  return (
    <Card className="p-6">
      <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
        <Lightbulb className="h-5 w-5 text-theme-warning" />
        Optimization Recommendations
      </h3>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {recommendations.slice(0, 4).map((rec) => (
          <div key={rec.id} className="p-4 bg-theme-surface rounded-lg border border-theme">
            <div className="flex items-start justify-between mb-2">
              <div>
                <p className="font-medium text-theme-primary">{rec.title}</p>
                <Badge
                  variant={rec.priority === 'high' ? 'danger' : rec.priority === 'medium' ? 'warning' : 'outline'}
                  size="sm"
                  className="mt-1"
                >
                  {rec.priority} priority
                </Badge>
              </div>
              <Badge variant="outline" size="sm">{rec.category}</Badge>
            </div>
            <p className="text-sm text-theme-secondary mt-2">{rec.description}</p>
            {(rec.potential_savings_usd || rec.potential_roi_improvement) && (
              <div className="flex items-center gap-4 mt-3">
                {rec.potential_savings_usd && (
                  <span className="text-xs text-theme-success flex items-center gap-1">
                    <DollarSign className="h-3 w-3" />
                    Save {formatCurrency(rec.potential_savings_usd)}
                  </span>
                )}
                {rec.potential_roi_improvement && (
                  <span className="text-xs text-theme-success flex items-center gap-1">
                    <TrendingUp className="h-3 w-3" />
                    +{rec.potential_roi_improvement}% ROI
                  </span>
                )}
              </div>
            )}
          </div>
        ))}
      </div>
    </Card>
  );
};
