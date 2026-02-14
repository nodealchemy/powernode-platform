import React from 'react';
import {
  AlertTriangle,
  Lightbulb,
  TrendingDown,
  TrendingUp,
  Zap,
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Insight, Recommendation } from '@/shared/services/ai';

interface InsightsPanelProps {
  insights: Insight[];
  recommendations: Recommendation[];
}

export const InsightsPanel: React.FC<InsightsPanelProps> = ({
  insights,
  recommendations,
}) => {
  if (insights.length === 0 && recommendations.length === 0) {
    return null;
  }

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
      {/* Insights */}
      {insights.length > 0 && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Lightbulb className="h-5 w-5 text-theme-warning" />
            Insights
          </h3>
          <div className="space-y-3">
            {insights.slice(0, 5).map((insight, index) => (
              <div
                key={index}
                className={`p-3 rounded-lg border ${
                  insight.severity === 'critical'
                    ? 'bg-theme-error-background border-theme-error'
                    : insight.severity === 'warning'
                    ? 'bg-theme-warning-background border-theme-warning'
                    : 'bg-theme-surface border-theme'
                }`}
              >
                <div className="flex items-start gap-2">
                  {insight.severity === 'critical' && <AlertTriangle className="h-4 w-4 text-theme-error mt-0.5" />}
                  {insight.severity === 'warning' && <AlertTriangle className="h-4 w-4 text-theme-warning mt-0.5" />}
                  <div>
                    <p className="font-medium text-theme-primary">{insight.title}</p>
                    <p className="text-sm text-theme-tertiary mt-1">{insight.description}</p>
                    {insight.impact && (
                      <p className="text-xs text-theme-tertiary mt-1">Impact: {insight.impact}</p>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Recommendations */}
      {recommendations.length > 0 && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Zap className="h-5 w-5 text-theme-success" />
            Recommendations
          </h3>
          <div className="space-y-3">
            {recommendations.slice(0, 5).map((rec) => (
              <div key={rec.id} className="p-3 bg-theme-surface rounded-lg">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <p className="font-medium text-theme-primary">{rec.title}</p>
                      <Badge
                        variant={rec.priority === 'high' ? 'danger' : rec.priority === 'medium' ? 'warning' : 'outline'}
                        size="sm"
                      >
                        {rec.priority}
                      </Badge>
                    </div>
                    <p className="text-sm text-theme-tertiary mt-1">{rec.description}</p>
                    {(rec.potential_savings_usd || rec.potential_improvement_percentage) && (
                      <div className="flex items-center gap-3 mt-2">
                        {rec.potential_savings_usd && (
                          <span className="text-xs text-theme-success flex items-center gap-1">
                            <TrendingDown className="h-3 w-3" />
                            Save ${rec.potential_savings_usd.toFixed(2)}
                          </span>
                        )}
                        {rec.potential_improvement_percentage && (
                          <span className="text-xs text-theme-success flex items-center gap-1">
                            <TrendingUp className="h-3 w-3" />
                            +{rec.potential_improvement_percentage}% improvement
                          </span>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
};
