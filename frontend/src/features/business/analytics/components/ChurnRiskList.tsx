import React from 'react';
import type { ChurnPrediction } from '../types/predictive';

interface ChurnRiskListProps {
  predictions: ChurnPrediction[];
  onSelect?: (prediction: ChurnPrediction) => void;
  onIntervene?: (prediction: ChurnPrediction) => void;
}

const getRiskTierColor = (tier: string): string => {
  const colors: Record<string, string> = {
    critical: 'bg-red-100 text-red-800 border-red-200',
    high: 'bg-orange-100 text-orange-800 border-orange-200',
    medium: 'bg-yellow-100 text-yellow-800 border-yellow-200',
    low: 'bg-blue-100 text-blue-800 border-blue-200',
    minimal: 'bg-green-100 text-green-800 border-green-200',
  };
  return colors[tier] || 'bg-gray-100 text-gray-800';
};

const getRiskIndicatorColor = (tier: string): string => {
  const colors: Record<string, string> = {
    critical: 'bg-red-500',
    high: 'bg-orange-500',
    medium: 'bg-yellow-500',
    low: 'bg-blue-500',
    minimal: 'bg-green-500',
  };
  return colors[tier] || 'bg-gray-500';
};

export const ChurnRiskList: React.FC<ChurnRiskListProps> = ({
  predictions,
  onSelect,
  onIntervene,
}) => {
  if (predictions.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-bg-primary rounded-lg border border-theme-border">
        <svg
          className="mx-auto h-12 w-12 text-green-500"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
          />
        </svg>
        <h3 className="mt-2 text-sm font-medium text-theme-text-primary">
          No high-risk customers
        </h3>
        <p className="mt-1 text-sm text-theme-text-secondary">
          All customers are showing healthy engagement.
        </p>
      </div>
    );
  }

  return (
    <div className="bg-theme-bg-primary rounded-lg border border-theme-border overflow-hidden">
      <div className="divide-y divide-theme-border">
        {predictions.map((prediction) => (
          <div
            key={prediction.id}
            onClick={() => onSelect?.(prediction)}
            className={`p-4 hover:bg-theme-bg-secondary transition-colors ${
              onSelect ? 'cursor-pointer' : ''
            }`}
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-4">
                {/* Risk Indicator */}
                <div className="relative">
                  <div className={`w-12 h-12 rounded-full flex items-center justify-center ${getRiskIndicatorColor(prediction.risk_tier)} text-white font-bold`}>
                    {prediction.probability_percentage}%
                  </div>
                </div>

                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-theme-text-primary">
                      Account {prediction.account_id.substring(0, 8)}...
                    </span>
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium border ${getRiskTierColor(prediction.risk_tier)}`}>
                      {prediction.risk_tier.charAt(0).toUpperCase() + prediction.risk_tier.slice(1)} Risk
                    </span>
                    {prediction.intervention_triggered && (
                      <span className="px-2 py-0.5 bg-blue-100 text-blue-800 rounded-full text-xs font-medium">
                        Intervention Active
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-4 mt-1 text-sm text-theme-text-secondary">
                    {prediction.primary_risk_factor && (
                      <span>Primary: {prediction.primary_risk_factor.replace('_', ' ')}</span>
                    )}
                    {prediction.days_until_churn && (
                      <span>Est. {prediction.days_until_churn} days</span>
                    )}
                    <span>Confidence: {((prediction.confidence_score || 0) * 100).toFixed(0)}%</span>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-3">
                {prediction.recommended_actions.length > 0 && !prediction.intervention_triggered && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onIntervene?.(prediction);
                    }}
                    className="btn-theme btn-theme-primary btn-theme-sm"
                  >
                    Intervene
                  </button>
                )}
                <svg
                  className="w-5 h-5 text-theme-text-secondary"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M9 5l7 7-7 7"
                  />
                </svg>
              </div>
            </div>

            {/* Recommended Actions Preview */}
            {prediction.recommended_actions.length > 0 && (
              <div className="mt-3 flex flex-wrap gap-2">
                {prediction.recommended_actions.slice(0, 3).map((action, index) => (
                  <span
                    key={index}
                    className={`px-2 py-1 rounded text-xs ${
                      action.priority === 'high'
                        ? 'bg-red-50 text-red-700'
                        : action.priority === 'medium'
                        ? 'bg-yellow-50 text-yellow-700'
                        : 'bg-gray-50 text-gray-700'
                    }`}
                  >
                    {action.description}
                  </span>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};

export default ChurnRiskList;
