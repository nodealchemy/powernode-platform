import React from 'react';
import { Link2, AlertTriangle } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';

interface Correlation {
  ai_failure: Record<string, unknown>;
  correlated_devops_events: Record<string, unknown>[];
  confidence: number;
  suggested_cause: string;
}

interface HealthCorrelationViewProps {
  correlations: Correlation[];
}

export const HealthCorrelationView: React.FC<HealthCorrelationViewProps> = ({ correlations }) => {
  if (correlations.length === 0) {
    return (
      <div className="text-center py-8 text-theme-muted">
        <Link2 className="w-8 h-8 mx-auto mb-2 opacity-50" />
        <p className="text-sm">No cross-system correlations detected</p>
      </div>
    );
  }

  return (
    <div className="space-y-3 max-h-96 overflow-y-auto">
      {correlations.map((correlation, index) => {
        const confidencePercent = Math.round(correlation.confidence * 100);
        const confidenceColor = confidencePercent >= 70
          ? 'text-theme-error'
          : confidencePercent >= 40
            ? 'text-theme-warning'
            : 'text-theme-muted';

        return (
          <div
            key={index}
            className="p-3 rounded-lg bg-theme-surface border border-theme-border"
          >
            <div className="flex items-start gap-2">
              <AlertTriangle className="w-4 h-4 mt-0.5 text-theme-warning" />
              <div className="flex-1">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-theme-primary">
                    Correlation #{index + 1}
                  </span>
                  <Badge variant={confidencePercent >= 70 ? 'danger' : confidencePercent >= 40 ? 'warning' : 'default'}>
                    {confidencePercent}% confidence
                  </Badge>
                </div>
                <p className="text-xs text-theme-secondary mt-1">
                  {correlation.suggested_cause}
                </p>
                <div className="mt-2 flex items-center gap-2 text-xs text-theme-muted">
                  <span>{correlation.correlated_devops_events.length} linked event(s)</span>
                  <span className={confidenceColor}>
                    Confidence: {confidencePercent}%
                  </span>
                </div>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
};
