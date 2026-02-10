import React, { useState } from 'react';
import { TrendingUp } from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Button } from '@/shared/components/ui/Button';
import { useCostTrends } from '../api/finopsApi';
import type { TrendPeriod } from '../types/finops';

const formatCost = (cost: number): string => {
  if (cost <= 0) return '$0.00';
  if (cost < 0.01) return `$${cost.toFixed(4)}`;
  if (cost >= 1000) return `$${(cost / 1000).toFixed(1)}K`;
  return `$${cost.toFixed(2)}`;
};

const PERIOD_OPTIONS: { id: TrendPeriod; label: string }[] = [
  { id: '7d', label: '7 Days' },
  { id: '14d', label: '14 Days' },
  { id: '30d', label: '30 Days' },
  { id: '90d', label: '90 Days' },
];

export const CostTrendChart: React.FC = () => {
  const [period, setPeriod] = useState<TrendPeriod>('30d');
  const { data: trends, isLoading } = useCostTrends({ period });

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-8" />;
  }

  if (!trends || trends.data.length === 0) {
    return (
      <EmptyState
        icon={TrendingUp}
        title="No cost data yet"
        description="Cost trends will appear once AI agents start processing requests."
      />
    );
  }

  const maxCost = Math.max(...trends.data.map((p) => p.cost), 0.01);
  const chartHeight = 200;

  return (
    <Card>
      <CardHeader
        title="Cost Trends"
        action={
          <div className="flex items-center gap-1">
            {PERIOD_OPTIONS.map((opt) => (
              <Button
                key={opt.id}
                variant={period === opt.id ? 'primary' : 'outline'}
                size="xs"
                onClick={() => setPeriod(opt.id)}
              >
                {opt.label}
              </Button>
            ))}
          </div>
        }
      />
      <CardContent>
        {/* Summary row */}
        <div className="flex items-center justify-between mb-4">
          <div>
            <p className="text-sm text-theme-tertiary">Total for period</p>
            <p className="text-xl font-bold text-theme-primary">{formatCost(trends.total_cost)}</p>
          </div>
          <div className="text-right">
            <p className="text-sm text-theme-tertiary">Daily average</p>
            <p className="text-lg font-semibold text-theme-secondary">{formatCost(trends.avg_daily_cost)}</p>
          </div>
        </div>

        {/* Chart - SVG bar chart */}
        <div className="relative" style={{ height: chartHeight + 40 }}>
          <svg
            className="w-full"
            viewBox={`0 0 ${trends.data.length * 24 + 40} ${chartHeight + 40}`}
            preserveAspectRatio="none"
          >
            {/* Y-axis gridlines */}
            {[0, 0.25, 0.5, 0.75, 1].map((frac) => (
              <line
                key={frac}
                x1="40"
                y1={chartHeight - frac * chartHeight + 10}
                x2={trends.data.length * 24 + 40}
                y2={chartHeight - frac * chartHeight + 10}
                className="stroke-theme-border"
                strokeWidth="0.5"
                strokeDasharray="4 2"
              />
            ))}

            {/* Bars */}
            {trends.data.map((point, idx) => {
              const barHeight = (point.cost / maxCost) * chartHeight;
              const x = idx * 24 + 44;
              const y = chartHeight - barHeight + 10;

              return (
                <g key={point.date}>
                  <rect
                    x={x}
                    y={y}
                    width="16"
                    height={barHeight}
                    rx="2"
                    className="fill-theme-interactive-primary opacity-80 hover:opacity-100 transition-opacity"
                  />
                  {/* Date label (show every nth based on data length) */}
                  {(idx % Math.max(Math.floor(trends.data.length / 8), 1) === 0) && (
                    <text
                      x={x + 8}
                      y={chartHeight + 30}
                      textAnchor="middle"
                      className="fill-theme-tertiary"
                      fontSize="8"
                    >
                      {new Date(point.date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
                    </text>
                  )}
                </g>
              );
            })}

            {/* Y-axis labels */}
            {[0, 0.5, 1].map((frac) => (
              <text
                key={frac}
                x="36"
                y={chartHeight - frac * chartHeight + 14}
                textAnchor="end"
                className="fill-theme-tertiary"
                fontSize="8"
              >
                {formatCost(maxCost * frac)}
              </text>
            ))}
          </svg>
        </div>

        {/* Data table below chart */}
        <div className="mt-4 border-t border-theme pt-4">
          <div className="grid grid-cols-3 gap-4 text-center">
            <div>
              <p className="text-xs text-theme-tertiary">Highest Day</p>
              <p className="text-sm font-semibold text-theme-primary">
                {formatCost(Math.max(...trends.data.map((d) => d.cost)))}
              </p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary">Lowest Day</p>
              <p className="text-sm font-semibold text-theme-primary">
                {formatCost(Math.min(...trends.data.map((d) => d.cost)))}
              </p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary">Data Points</p>
              <p className="text-sm font-semibold text-theme-primary">{trends.data.length}</p>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
