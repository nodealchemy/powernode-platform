import React, { useMemo } from 'react';
import { Card } from '@/shared/components/ui';

interface UsageChartProps {
  trends: Record<string, number>;
  title?: string;
}

export const UsageChart: React.FC<UsageChartProps> = ({ trends, title = 'Usage Trends' }) => {
  const chartData = useMemo(() => {
    const entries = Object.entries(trends).sort(([a], [b]) => a.localeCompare(b));
    const values = entries.map(([, v]) => v);
    const maxValue = Math.max(...values, 1);

    return entries.map(([date, value]) => ({
      date,
      value,
      height: (value / maxValue) * 100,
    }));
  }, [trends]);

  const totalUsage = useMemo(() => {
    return Object.values(trends).reduce((sum, val) => sum + val, 0);
  }, [trends]);

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  };

  const formatNumber = (num: number) => {
    if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
    if (num >= 1000) return `${(num / 1000).toFixed(1)}K`;
    return num.toLocaleString();
  };

  if (chartData.length === 0) {
    return (
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">{title}</h3>
        <p className="text-center text-theme-tertiary py-8">
          No usage data available for this period.
        </p>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-theme-primary">{title}</h3>
        <div className="text-right">
          <p className="text-2xl font-bold text-theme-primary">{formatNumber(totalUsage)}</p>
          <p className="text-sm text-theme-tertiary">Total (30 days)</p>
        </div>
      </div>

      <div className="relative">
        <div className="flex items-end justify-between h-48 gap-1">
          {chartData.slice(-30).map((point, index) => (
            <div
              key={point.date}
              className="relative flex-1 group"
            >
              <div
                className="w-full bg-theme-interactive-primary hover:bg-theme-interactive-primary-hover rounded-t transition-all cursor-pointer"
                style={{ height: `${Math.max(point.height, 2)}%` }}
              />

              {/* Tooltip */}
              <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-2 py-1 bg-theme-inverse text-theme-inverse-primary text-xs rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none z-10">
                <p className="font-medium">{formatNumber(point.value)}</p>
                <p className="text-theme-inverse-tertiary">{formatDate(point.date)}</p>
              </div>

              {/* X-axis labels (show every 5th) */}
              {index % 5 === 0 && (
                <span className="absolute top-full mt-2 left-1/2 -translate-x-1/2 text-xs text-theme-tertiary">
                  {formatDate(point.date)}
                </span>
              )}
            </div>
          ))}
        </div>

        {/* Y-axis reference lines */}
        <div className="absolute inset-0 flex flex-col justify-between pointer-events-none">
          {[100, 75, 50, 25, 0].map((percent) => (
            <div key={percent} className="flex items-center">
              <span className="text-xs text-theme-tertiary w-12 text-right pr-2">
                {formatNumber(Math.round(Math.max(...chartData.map(d => d.value), 1) * percent / 100))}
              </span>
              <div className="flex-1 border-t border-theme border-dashed" />
            </div>
          ))}
        </div>
      </div>
    </Card>
  );
};
