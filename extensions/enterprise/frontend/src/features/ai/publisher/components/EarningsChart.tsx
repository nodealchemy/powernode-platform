import React, { useMemo } from 'react';
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
  AreaChart,
} from 'recharts';
import { formatDate } from '@/shared/utils/formatters';
import type { EarningsSnapshot, DailyMetric } from '../types';

interface EarningsChartProps {
  data: EarningsSnapshot[] | DailyMetric[];
  type?: 'earnings' | 'revenue';
  height?: number;
}

const formatCurrency = (value: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value);
};

export const EarningsChart: React.FC<EarningsChartProps> = ({
  data,
  type = 'earnings',
  height = 300,
}) => {
  const chartData = useMemo(() => {
    if (!data || data.length === 0) return [];

    return [...data].reverse().map((item) => {
      if (type === 'earnings' && 'gross_earnings' in item) {
        return {
          date: formatDate(item.date),
          gross: item.gross_earnings,
          net: item.net_earnings,
          paidOut: item.paid_out,
        };
      } else if ('revenue' in item) {
        return {
          date: formatDate(item.date),
          revenue: item.revenue,
          installations: item.installations,
        };
      }
      return null;
    }).filter(Boolean);
  }, [data, type]);

  if (chartData.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 bg-theme-bg-secondary rounded-lg">
        <p className="text-theme-text-secondary">No data available</p>
      </div>
    );
  }

  if (type === 'earnings') {
    return (
      <div className="bg-theme-bg-primary rounded-lg p-4">
        <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
          Earnings History
        </h3>
        <ResponsiveContainer width="100%" height={height}>
          <AreaChart data={chartData}>
            <defs>
              <linearGradient id="colorGross" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="var(--color-success, #10B981)" stopOpacity={0.3} />
                <stop offset="95%" stopColor="var(--color-success, #10B981)" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="colorNet" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="var(--color-info, #3B82F6)" stopOpacity={0.3} />
                <stop offset="95%" stopColor="var(--color-info, #3B82F6)" stopOpacity={0} />
              </linearGradient>
            </defs>
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
              formatter={(value) => formatCurrency(Number(value))}
              contentStyle={{
                backgroundColor: 'var(--theme-bg-secondary)',
                border: '1px solid var(--theme-border)',
                borderRadius: '8px',
              }}
            />
            <Legend />
            <Area
              type="monotone"
              dataKey="gross"
              name="Gross Earnings"
              stroke="var(--color-success, #10B981)"
              fillOpacity={1}
              fill="url(#colorGross)"
            />
            <Area
              type="monotone"
              dataKey="net"
              name="Net Earnings"
              stroke="var(--color-info, #3B82F6)"
              fillOpacity={1}
              fill="url(#colorNet)"
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    );
  }

  return (
    <div className="bg-theme-bg-primary rounded-lg p-4">
      <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
        Revenue Trend
      </h3>
      <ResponsiveContainer width="100%" height={height}>
        <LineChart data={chartData}>
          <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
          <XAxis
            dataKey="date"
            tick={{ fontSize: 12 }}
            className="text-theme-text-secondary"
          />
          <YAxis
            yAxisId="left"
            tickFormatter={formatCurrency}
            tick={{ fontSize: 12 }}
            className="text-theme-text-secondary"
          />
          <YAxis
            yAxisId="right"
            orientation="right"
            tick={{ fontSize: 12 }}
            className="text-theme-text-secondary"
          />
          <Tooltip
            formatter={(value, name) =>
              name === 'revenue' ? formatCurrency(Number(value)) : value
            }
            contentStyle={{
              backgroundColor: 'var(--theme-bg-secondary)',
              border: '1px solid var(--theme-border)',
              borderRadius: '8px',
            }}
          />
          <Legend />
          <Line
            yAxisId="left"
            type="monotone"
            dataKey="revenue"
            name="Revenue"
            stroke="var(--color-success, #10B981)"
            strokeWidth={2}
            dot={false}
          />
          <Line
            yAxisId="right"
            type="monotone"
            dataKey="installations"
            name="Installations"
            stroke="var(--color-interactive-primary, #8B5CF6)"
            strokeWidth={2}
            dot={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
};

export default EarningsChart;
