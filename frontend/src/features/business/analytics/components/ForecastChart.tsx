import React from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  Area,
  ComposedChart,
} from 'recharts';
import type { RevenueForecast } from '../types/predictive';

interface ForecastChartProps {
  forecasts: RevenueForecast[];
  height?: number;
  showConfidenceInterval?: boolean;
}

const formatCurrency = (value: number): string => {
  if (value >= 1000000) {
    return `$${(value / 1000000).toFixed(1)}M`;
  }
  if (value >= 1000) {
    return `$${(value / 1000).toFixed(0)}K`;
  }
  return `$${value.toFixed(0)}`;
};

const formatDate = (dateStr: string): string => {
  const date = new Date(dateStr);
  return date.toLocaleDateString('en-US', { month: 'short', year: '2-digit' });
};

export const ForecastChart: React.FC<ForecastChartProps> = ({
  forecasts,
  height = 400,
  showConfidenceInterval = true,
}) => {
  const chartData = forecasts.map((forecast) => ({
    date: formatDate(forecast.forecast_date),
    projected: forecast.projections.mrr,
    actual: forecast.actuals?.mrr || null,
    lowerBound: forecast.confidence.lower_bound,
    upperBound: forecast.confidence.upper_bound,
    newRevenue: forecast.projections.new_revenue,
    churned: forecast.projections.churned_revenue,
  }));

  if (chartData.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 bg-theme-bg-secondary rounded-lg">
        <p className="text-theme-text-secondary">No forecast data available</p>
      </div>
    );
  }

  return (
    <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
      <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
        Revenue Forecast
      </h3>

      <ResponsiveContainer width="100%" height={height}>
        <ComposedChart data={chartData}>
          <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
          <XAxis
            dataKey="date"
            tick={{ fontSize: 12 }}
            className="text-theme-text-secondary"
          />
          <YAxis
            tickFormatter={formatCurrency}
            tick={{ fontSize: 12 }}
            className="text-theme-text-secondary"
          />
          <Tooltip
            formatter={(value: number, name: string) => [formatCurrency(value), name]}
            contentStyle={{
              backgroundColor: 'var(--theme-bg-secondary)',
              border: '1px solid var(--theme-border)',
              borderRadius: '8px',
            }}
          />
          <Legend />

          {/* Confidence Interval */}
          {showConfidenceInterval && (
            <Area
              type="monotone"
              dataKey="upperBound"
              stroke="none"
              fill="#3B82F6"
              fillOpacity={0.1}
              name="Upper Bound"
            />
          )}

          {/* Projected Line */}
          <Line
            type="monotone"
            dataKey="projected"
            name="Projected MRR"
            stroke="#3B82F6"
            strokeWidth={2}
            dot={false}
            strokeDasharray="5 5"
          />

          {/* Actual Line */}
          <Line
            type="monotone"
            dataKey="actual"
            name="Actual MRR"
            stroke="#10B981"
            strokeWidth={2}
            dot={{ fill: '#10B981', strokeWidth: 2 }}
            connectNulls={false}
          />
        </ComposedChart>
      </ResponsiveContainer>

      {/* Summary Stats */}
      <div className="mt-6 grid grid-cols-4 gap-4">
        <div className="text-center p-3 bg-theme-bg-secondary rounded-lg">
          <p className="text-sm text-theme-text-secondary">Next Month</p>
          <p className="text-lg font-bold text-theme-text-primary">
            {chartData[0] ? formatCurrency(chartData[0].projected) : '-'}
          </p>
        </div>
        <div className="text-center p-3 bg-theme-bg-secondary rounded-lg">
          <p className="text-sm text-theme-text-secondary">3 Months</p>
          <p className="text-lg font-bold text-theme-text-primary">
            {chartData[2] ? formatCurrency(chartData[2].projected) : '-'}
          </p>
        </div>
        <div className="text-center p-3 bg-theme-bg-secondary rounded-lg">
          <p className="text-sm text-theme-text-secondary">6 Months</p>
          <p className="text-lg font-bold text-theme-text-primary">
            {chartData[5] ? formatCurrency(chartData[5].projected) : '-'}
          </p>
        </div>
        <div className="text-center p-3 bg-theme-bg-secondary rounded-lg">
          <p className="text-sm text-theme-text-secondary">12 Months</p>
          <p className="text-lg font-bold text-theme-text-primary">
            {chartData[11] ? formatCurrency(chartData[11].projected) : '-'}
          </p>
        </div>
      </div>
    </div>
  );
};

export default ForecastChart;
