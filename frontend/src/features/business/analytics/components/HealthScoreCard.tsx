import React from 'react';
import type { CustomerHealthScore } from '../types/predictive';

interface HealthScoreCardProps {
  healthScore: CustomerHealthScore;
  showDetails?: boolean;
  onClick?: () => void;
}

const getStatusColor = (status: string): string => {
  const colors: Record<string, string> = {
    thriving: 'text-theme-success',
    healthy: 'text-theme-success',
    needs_attention: 'text-theme-warning',
    at_risk: 'text-theme-warning',
    critical: 'text-theme-error',
  };
  return colors[status] || 'text-theme-text-secondary';
};

const getStatusBg = (status: string): string => {
  const colors: Record<string, string> = {
    thriving: 'bg-theme-success-background',
    healthy: 'bg-theme-success-background',
    needs_attention: 'bg-theme-warning-background',
    at_risk: 'bg-theme-warning-background',
    critical: 'bg-theme-error-background',
  };
  return colors[status] || 'bg-theme-bg-secondary';
};

const getTrendIcon = (direction: string) => {
  switch (direction) {
    case 'improving':
      return (
        <svg className="w-4 h-4 text-theme-success" fill="currentColor" viewBox="0 0 20 20">
          <path fillRule="evenodd" d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z" clipRule="evenodd" />
        </svg>
      );
    case 'declining':
    case 'critical_decline':
      return (
        <svg className="w-4 h-4 text-theme-error" fill="currentColor" viewBox="0 0 20 20">
          <path fillRule="evenodd" d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z" clipRule="evenodd" />
        </svg>
      );
    default:
      return (
        <svg className="w-4 h-4 text-theme-text-secondary" fill="currentColor" viewBox="0 0 20 20">
          <path fillRule="evenodd" d="M5 10a1 1 0 011-1h8a1 1 0 110 2H6a1 1 0 01-1-1z" clipRule="evenodd" />
        </svg>
      );
  }
};

export const HealthScoreCard: React.FC<HealthScoreCardProps> = ({
  healthScore,
  showDetails = false,
  onClick,
}) => {
  const scorePercent = healthScore.overall_score;
  const circumference = 2 * Math.PI * 40;
  const offset = circumference - (scorePercent / 100) * circumference;

  return (
    <div
      onClick={onClick}
      className={`bg-theme-bg-primary rounded-lg p-6 border border-theme-border ${
        onClick ? 'cursor-pointer hover:shadow-md transition-shadow' : ''
      } ${healthScore.at_risk ? 'border-l-4 border-l-theme-error' : ''}`}
    >
      <div className="flex items-center justify-between mb-4">
        <div>
          <h4 className="font-medium text-theme-text-primary">Health Score</h4>
          <div className="flex items-center gap-2 mt-1">
            <span className={`text-sm font-medium ${getStatusColor(healthScore.health_status)}`}>
              {healthScore.health_status.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}
            </span>
            {getTrendIcon(healthScore.trend_direction)}
            {healthScore.score_change_30d !== null && (
              <span className={`text-xs ${healthScore.score_change_30d >= 0 ? 'text-theme-success' : 'text-theme-error'}`}>
                {healthScore.score_change_30d >= 0 ? '+' : ''}{healthScore.score_change_30d.toFixed(1)}
              </span>
            )}
          </div>
        </div>

        {/* Circular Score */}
        <div className="relative w-20 h-20">
          <svg className="transform -rotate-90 w-20 h-20">
            <circle
              cx="40"
              cy="40"
              r="40"
              stroke="currentColor"
              strokeWidth="8"
              fill="none"
              className="text-theme-bg-tertiary"
            />
            <circle
              cx="40"
              cy="40"
              r="40"
              stroke="currentColor"
              strokeWidth="8"
              fill="none"
              strokeDasharray={circumference}
              strokeDashoffset={offset}
              strokeLinecap="round"
              className={getStatusColor(healthScore.health_status)}
            />
          </svg>
          <div className="absolute inset-0 flex items-center justify-center">
            <span className="text-xl font-bold text-theme-text-primary">
              {Math.round(scorePercent)}
            </span>
          </div>
        </div>
      </div>

      {/* Risk Factors */}
      {healthScore.at_risk && healthScore.risk_factors.length > 0 && (
        <div className={`p-3 rounded-lg ${getStatusBg(healthScore.health_status)}`}>
          <p className="text-sm font-medium text-theme-text-primary mb-2">Risk Factors:</p>
          <ul className="space-y-1">
            {healthScore.risk_factors.slice(0, 3).map((factor, index) => (
              <li key={index} className="text-sm text-theme-text-secondary flex items-center gap-2">
                <span className="w-1.5 h-1.5 rounded-full bg-theme-error" />
                {factor}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Component Scores */}
      {showDetails && (
        <div className="mt-4 grid grid-cols-5 gap-2">
          {Object.entries(healthScore.components).map(([component, score]) => (
            <div key={component} className="text-center">
              <p className="text-xs text-theme-text-secondary capitalize">{component}</p>
              <p className="text-sm font-medium text-theme-text-primary">
                {score !== null ? Math.round(score) : '-'}
              </p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default HealthScoreCard;
