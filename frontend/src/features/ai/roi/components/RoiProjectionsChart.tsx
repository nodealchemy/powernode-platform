import React from 'react';
import {
  BarChart3,
  PieChart,
  TrendingDown,
  TrendingUp,
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { RoiProjections, PeriodComparison } from '@/shared/services/ai';

interface RoiProjectionsChartProps {
  projections: RoiProjections | null;
  comparison: PeriodComparison | null;
  formatCurrency: (amount: number) => string;
  formatHours: (hours: number) => string;
  getTrendIcon: (direction: string) => React.ReactNode;
}

export const RoiProjectionsChart: React.FC<RoiProjectionsChartProps> = ({
  projections,
  comparison,
  formatCurrency,
  formatHours,
  getTrendIcon,
}) => {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
      {/* Period Comparison */}
      {comparison && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <BarChart3 className="h-5 w-5" />
            Period Comparison
          </h3>
          <div className="space-y-4">
            <div className="grid grid-cols-3 gap-4 text-center">
              <div>
                <p className="text-xs text-theme-tertiary">Metric</p>
              </div>
              <div>
                <p className="text-xs text-theme-tertiary">Current</p>
              </div>
              <div>
                <p className="text-xs text-theme-tertiary">Change</p>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4 p-3 bg-theme-surface rounded-lg">
              <p className="text-sm font-medium text-theme-primary">ROI</p>
              <p className="text-sm text-center">{comparison.current_period.roi_percentage.toFixed(0)}%</p>
              <div className="flex items-center justify-center gap-1">
                {comparison.changes.roi_change_points >= 0 ? (
                  <TrendingUp className="h-3 w-3 text-theme-success" />
                ) : (
                  <TrendingDown className="h-3 w-3 text-theme-error" />
                )}
                <span className={comparison.changes.roi_change_points >= 0 ? 'text-theme-success' : 'text-theme-error'}>
                  {comparison.changes.roi_change_points >= 0 ? '+' : ''}{comparison.changes.roi_change_points.toFixed(1)} pts
                </span>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4 p-3 bg-theme-surface rounded-lg">
              <p className="text-sm font-medium text-theme-primary">Value</p>
              <p className="text-sm text-center">{formatCurrency(comparison.current_period.value_usd)}</p>
              <div className="flex items-center justify-center gap-1">
                {comparison.changes.value_change_percentage >= 0 ? (
                  <TrendingUp className="h-3 w-3 text-theme-success" />
                ) : (
                  <TrendingDown className="h-3 w-3 text-theme-error" />
                )}
                <span className={comparison.changes.value_change_percentage >= 0 ? 'text-theme-success' : 'text-theme-error'}>
                  {comparison.changes.value_change_percentage >= 0 ? '+' : ''}{comparison.changes.value_change_percentage.toFixed(1)}%
                </span>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4 p-3 bg-theme-surface rounded-lg">
              <p className="text-sm font-medium text-theme-primary">Cost</p>
              <p className="text-sm text-center">{formatCurrency(comparison.current_period.cost_usd)}</p>
              <div className="flex items-center justify-center gap-1">
                {comparison.changes.cost_change_percentage <= 0 ? (
                  <TrendingDown className="h-3 w-3 text-theme-success" />
                ) : (
                  <TrendingUp className="h-3 w-3 text-theme-error" />
                )}
                <span className={comparison.changes.cost_change_percentage <= 0 ? 'text-theme-success' : 'text-theme-error'}>
                  {comparison.changes.cost_change_percentage >= 0 ? '+' : ''}{comparison.changes.cost_change_percentage.toFixed(1)}%
                </span>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4 p-3 bg-theme-surface rounded-lg">
              <p className="text-sm font-medium text-theme-primary">Time Saved</p>
              <p className="text-sm text-center">{formatHours(comparison.current_period.time_saved_hours)}</p>
              <div className="flex items-center justify-center gap-1">
                {comparison.changes.time_saved_change_percentage >= 0 ? (
                  <TrendingUp className="h-3 w-3 text-theme-success" />
                ) : (
                  <TrendingDown className="h-3 w-3 text-theme-error" />
                )}
                <span className={comparison.changes.time_saved_change_percentage >= 0 ? 'text-theme-success' : 'text-theme-error'}>
                  {comparison.changes.time_saved_change_percentage >= 0 ? '+' : ''}{comparison.changes.time_saved_change_percentage.toFixed(1)}%
                </span>
              </div>
            </div>
          </div>
        </Card>
      )}

      {/* Projections */}
      {projections && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <PieChart className="h-5 w-5" />
            Projections
          </h3>

          <div className="space-y-4">
            <div className="p-4 bg-theme-surface rounded-lg">
              <p className="text-sm text-theme-tertiary mb-2">Monthly Projection</p>
              <div className="grid grid-cols-3 gap-4">
                <div>
                  <p className="text-xs text-theme-tertiary">Cost</p>
                  <p className="font-semibold">{formatCurrency(projections.monthly_projection.projected_cost_usd)}</p>
                </div>
                <div>
                  <p className="text-xs text-theme-tertiary">Value</p>
                  <p className="font-semibold text-theme-success">{formatCurrency(projections.monthly_projection.projected_value_usd)}</p>
                </div>
                <div>
                  <p className="text-xs text-theme-tertiary">ROI</p>
                  <p className="font-semibold">{projections.monthly_projection.projected_roi_percentage.toFixed(0)}%</p>
                </div>
              </div>
              <div className="mt-2">
                <Badge variant="outline" size="sm">
                  {(projections.monthly_projection.confidence * 100).toFixed(0)}% confidence
                </Badge>
              </div>
            </div>

            <div className="p-4 bg-theme-surface rounded-lg">
              <p className="text-sm text-theme-tertiary mb-2">Quarterly Projection</p>
              <div className="grid grid-cols-3 gap-4">
                <div>
                  <p className="text-xs text-theme-tertiary">Cost</p>
                  <p className="font-semibold">{formatCurrency(projections.quarterly_projection.projected_cost_usd)}</p>
                </div>
                <div>
                  <p className="text-xs text-theme-tertiary">Value</p>
                  <p className="font-semibold text-theme-success">{formatCurrency(projections.quarterly_projection.projected_value_usd)}</p>
                </div>
                <div>
                  <p className="text-xs text-theme-tertiary">ROI</p>
                  <p className="font-semibold">{projections.quarterly_projection.projected_roi_percentage.toFixed(0)}%</p>
                </div>
              </div>
            </div>

            <div className="p-4 bg-theme-surface rounded-lg">
              <p className="text-sm text-theme-tertiary mb-2">Trend Analysis</p>
              <div className="grid grid-cols-3 gap-4">
                <div className="flex items-center gap-2">
                  {getTrendIcon(projections.trend_analysis.cost_trend)}
                  <span className="text-sm">Cost</span>
                </div>
                <div className="flex items-center gap-2">
                  {getTrendIcon(projections.trend_analysis.value_trend)}
                  <span className="text-sm">Value</span>
                </div>
                <div className="flex items-center gap-2">
                  {getTrendIcon(projections.trend_analysis.roi_trend)}
                  <span className="text-sm">ROI</span>
                </div>
              </div>
            </div>
          </div>
        </Card>
      )}
    </div>
  );
};
