import React from 'react';
import { Lightbulb } from 'lucide-react';
import {
  CostAnalysis,
  ProviderRanking,
  OptimizationRecommendation
} from '@/shared/services/ai/ModelRouterApiService';

interface AnalyticsTabProps {
  costAnalysis: CostAnalysis | null;
  rankings: ProviderRanking[];
  recommendations: OptimizationRecommendation[];
}

export const AnalyticsTab: React.FC<AnalyticsTabProps> = ({ costAnalysis, rankings, recommendations }) => {
  return (
    <div className="space-y-6">
      {/* Cost Analysis */}
      {costAnalysis && (
        <div className="bg-theme-surface border border-theme rounded-lg p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Cost Analysis</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {Object.entries(costAnalysis).filter(([, value]) => typeof value === 'number').slice(0, 6).map(([key, value]) => (
              <div key={key} className="p-3 bg-theme-bg rounded-lg">
                <p className="text-xs text-theme-secondary">{key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</p>
                <p className="text-lg font-semibold text-theme-primary">
                  {key.includes('usd') || key.includes('cost') || key.includes('savings')
                    ? `$${(value as number).toFixed(2)}`
                    : (value as number).toLocaleString()}
                </p>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Provider Rankings */}
      {rankings.length > 0 && (
        <div className="bg-theme-surface border border-theme rounded-lg p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Provider Rankings</h3>
          <div className="space-y-3">
            {rankings.map((ranking, idx) => (
              <div key={ranking.provider_id || idx} className="flex items-center justify-between p-3 bg-theme-bg rounded-lg">
                <div className="flex items-center gap-3">
                  <span className="text-lg font-bold text-theme-accent">#{idx + 1}</span>
                  <span className="text-sm font-medium text-theme-primary">{ranking.provider_name || ranking.provider_id}</span>
                </div>
                <div className="flex gap-4 text-xs text-theme-secondary">
                  {ranking.latency_score > 0 && <span>Latency: {ranking.latency_score.toFixed(1)}</span>}
                  {ranking.success_rate > 0 && <span>{(ranking.success_rate * 100).toFixed(1)}% success</span>}
                  {ranking.cost_score > 0 && <span>Cost: {ranking.cost_score.toFixed(1)}</span>}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Recommendations */}
      {recommendations.length > 0 && (
        <div className="bg-theme-surface border border-theme rounded-lg p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Recommendations</h3>
          <div className="space-y-3">
            {recommendations.map((rec, idx) => (
              <div key={idx} className="flex items-start gap-3 p-3 bg-theme-bg rounded-lg">
                <Lightbulb size={16} className="text-theme-warning mt-0.5 flex-shrink-0" />
                <div>
                  <p className="text-sm font-medium text-theme-primary">{rec.title}</p>
                  {rec.description && <p className="text-xs text-theme-secondary mt-1">{rec.description}</p>}
                  {rec.potential_savings_usd && (
                    <span className="inline-block mt-1 text-xs text-theme-success">
                      Est. savings: ${rec.potential_savings_usd.toFixed(2)}
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
