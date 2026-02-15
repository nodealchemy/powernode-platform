import React from 'react';
import { DollarSign, TrendingUp, TrendingDown } from 'lucide-react';
import type { CampaignStatistics } from '../types';

interface CampaignROIChartProps {
  statistics: CampaignStatistics | null;
  loading?: boolean;
}

export const CampaignROIChart: React.FC<CampaignROIChartProps> = ({ statistics, loading }) => {
  if (loading || !statistics) {
    return (
      <div className="card-theme p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Return on Investment</h3>
        <div className="animate-pulse space-y-4">
          <div className="h-8 bg-theme-surface rounded w-1/3" />
          <div className="h-32 bg-theme-surface rounded" />
        </div>
      </div>
    );
  }

  const formatCurrency = (cents: number): string => {
    return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2 })}`;
  };

  const roiPositive = statistics.roi_percentage >= 0;

  return (
    <div className="card-theme p-6">
      <h3 className="text-lg font-medium text-theme-primary mb-4">Return on Investment</h3>

      {/* ROI Headline */}
      <div className="flex items-center gap-4 mb-6">
        <div className={`p-3 rounded-lg ${roiPositive ? 'bg-theme-success bg-opacity-10' : 'bg-theme-error bg-opacity-10'}`}>
          {roiPositive ? (
            <TrendingUp className={`w-8 h-8 text-theme-success`} />
          ) : (
            <TrendingDown className={`w-8 h-8 text-theme-error`} />
          )}
        </div>
        <div>
          <p className={`text-3xl font-bold ${roiPositive ? 'text-theme-success' : 'text-theme-error'}`}>
            {statistics.roi_percentage >= 0 ? '+' : ''}{statistics.roi_percentage.toFixed(1)}%
          </p>
          <p className="text-sm text-theme-secondary">Overall ROI</p>
        </div>
      </div>

      {/* Revenue vs Spend */}
      <div className="grid grid-cols-2 gap-4 mb-6">
        <div className="p-4 rounded-lg bg-theme-surface">
          <div className="flex items-center gap-2 mb-1">
            <DollarSign className="w-4 h-4 text-theme-success" />
            <p className="text-xs text-theme-secondary">Total Revenue</p>
          </div>
          <p className="text-xl font-semibold text-theme-primary">{formatCurrency(statistics.total_revenue_cents)}</p>
        </div>
        <div className="p-4 rounded-lg bg-theme-surface">
          <div className="flex items-center gap-2 mb-1">
            <DollarSign className="w-4 h-4 text-theme-error" />
            <p className="text-xs text-theme-secondary">Total Spent</p>
          </div>
          <p className="text-xl font-semibold text-theme-primary">{formatCurrency(statistics.total_spent_cents)}</p>
        </div>
      </div>

      {/* Bar Visualization */}
      <div className="space-y-3">
        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs text-theme-secondary">Revenue</span>
            <span className="text-xs text-theme-primary">{formatCurrency(statistics.total_revenue_cents)}</span>
          </div>
          <div className="h-4 bg-theme-surface rounded-full overflow-hidden">
            <div
              className="h-full bg-theme-success rounded-full transition-all"
              style={{
                width: `${Math.min(100, statistics.total_spent_cents > 0
                  ? (statistics.total_revenue_cents / Math.max(statistics.total_revenue_cents, statistics.total_spent_cents)) * 100
                  : 100)}%`
              }}
            />
          </div>
        </div>
        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs text-theme-secondary">Spend</span>
            <span className="text-xs text-theme-primary">{formatCurrency(statistics.total_spent_cents)}</span>
          </div>
          <div className="h-4 bg-theme-surface rounded-full overflow-hidden">
            <div
              className="h-full bg-theme-error rounded-full transition-all"
              style={{
                width: `${Math.min(100, statistics.total_revenue_cents > 0
                  ? (statistics.total_spent_cents / Math.max(statistics.total_revenue_cents, statistics.total_spent_cents)) * 100
                  : 100)}%`
              }}
            />
          </div>
        </div>
      </div>

      {/* Campaign Breakdown */}
      <div className="mt-6 pt-4 border-t border-theme-border">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Campaign Breakdown</h4>
        <div className="grid grid-cols-3 gap-4 text-center">
          <div>
            <p className="text-lg font-semibold text-theme-primary">{statistics.total_campaigns}</p>
            <p className="text-xs text-theme-secondary">Total</p>
          </div>
          <div>
            <p className="text-lg font-semibold text-theme-success">{statistics.active_campaigns}</p>
            <p className="text-xs text-theme-secondary">Active</p>
          </div>
          <div>
            <p className="text-lg font-semibold text-theme-primary">{statistics.completed_campaigns}</p>
            <p className="text-xs text-theme-secondary">Completed</p>
          </div>
        </div>
      </div>
    </div>
  );
};
