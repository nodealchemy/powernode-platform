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
  // BarChart, // TODO: Use for bar chart visualization
  Bar,
  ComposedChart
} from 'recharts';
import { format, parseISO } from 'date-fns';
import { useChartColors } from '@/shared/hooks/useThemeColors';

interface RevenueChartProps {
  data: Array<{
    date: string;
    mrr: number;
    arr: number;
    active_subscriptions: number;
    new_subscriptions: number;
    churned_subscriptions: number;
  }>;
  currentMetrics?: {
    mrr: number;
    arr: number;
    active_subscriptions: number;
    total_customers: number;
    arpu: number;
    growth_rate: number;
  };
  title: string;
  compact?: boolean;
}

export const RevenueChart: React.FC<RevenueChartProps> = ({ 
RevenueChart.displayName = 'RevenueChart';
  data, 
  currentMetrics, 
  title, 
  compact = false 
}) => {
  // Use theme-aware colors that update automatically
  const colors = useChartColors();

  const formatCurrency = (value: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(value);
  };

  const formatDate = (dateString: string) => {
    try {
      return format(parseISO(dateString), 'MMM yyyy');
    } catch {
      return dateString;
    }
  };

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div className="card-theme p-4 border-theme rounded-lg shadow-lg">
          <p className="font-semibold text-theme-primary">{formatDate(label)}</p>
          {payload.map((entry: any, index: number) => (
            <p key={index} className="text-sm" style={{ color: entry.color }}>
              {entry.name}: {entry.name.includes('MRR') || entry.name.includes('ARR') 
                ? formatCurrency(entry.value) 
                : entry.value.toLocaleString()}
            </p>
          ))}
        </div>
      );
    }
    return null;
  };

  if (compact) {
    return (
      <div className="card-theme rounded-lg shadow-sm border-theme p-4 sm:p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">{title}</h3>
        <div className="h-48 sm:h-56 md:h-64">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke={colors.border} />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
                tick={{ fontSize: 11 }}
                interval="preserveStartEnd"
              />
              <YAxis 
                tickFormatter={(value) => formatCurrency(value)}
                tick={{ fontSize: 12 }}
              />
              <Tooltip content={<CustomTooltip />} />
              <Line
                type="monotone"
                dataKey="mrr"
                stroke={colors.info}
                strokeWidth={2}
                dot={{ fill: colors.info, strokeWidth: 0, r: 4 }}
                activeDot={{ r: 6, stroke: colors.info, strokeWidth: 2 }}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Current Metrics Summary */}
      {currentMetrics && (
        <div className="card-theme rounded-lg shadow-sm border-theme p-4 sm:p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Current Revenue Metrics</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
            <div>
              <p className="text-sm text-theme-secondary">Monthly Recurring Revenue</p>
              <p className="text-2xl font-bold text-theme-info">{formatCurrency(currentMetrics.mrr)}</p>
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Annual Recurring Revenue</p>
              <p className="text-2xl font-bold text-theme-success">{formatCurrency(currentMetrics.arr)}</p>
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Active Subscriptions</p>
              <p className="text-2xl font-bold text-theme-primary">{currentMetrics.active_subscriptions.toLocaleString()}</p>
            </div>
          </div>
        </div>
      )}

      {/* MRR vs ARR Trend */}
      <div className="card-theme rounded-lg shadow-sm border-theme p-4 sm:p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Revenue Trend</h3>
        <div className="h-64 sm:h-80 lg:h-96">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke={colors.border} />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
              />
              <YAxis 
                tickFormatter={(value) => formatCurrency(value)}
              />
              <Tooltip content={<CustomTooltip />} />
              <Legend />
              <Line
                type="monotone"
                dataKey="mrr"
                stroke={colors.info}
                strokeWidth={3}
                name="Monthly Recurring Revenue"
                dot={{ fill: colors.info, strokeWidth: 0, r: 4 }}
                activeDot={{ r: 6, stroke: colors.info, strokeWidth: 2 }}
              />
              <Line
                type="monotone"
                dataKey="arr"
                stroke={colors.success}
                strokeWidth={3}
                name="Annual Recurring Revenue"
                dot={{ fill: colors.success, strokeWidth: 0, r: 4 }}
                activeDot={{ r: 6, stroke: colors.success, strokeWidth: 2 }}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Subscription Activity */}
      <div className="card-theme rounded-lg shadow-sm border-theme p-4 sm:p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Subscription Activity</h3>
        <div className="h-64 sm:h-80 lg:h-96">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke={colors.border} />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
              />
              <YAxis yAxisId="left" />
              <YAxis yAxisId="right" orientation="right" />
              <Tooltip content={<CustomTooltip />} />
              <Legend />
              <Bar
                yAxisId="left"
                dataKey="new_subscriptions"
                fill={colors.success}
                name="New Subscriptions"
                opacity={0.8}
              />
              <Bar
                yAxisId="left"
                dataKey="churned_subscriptions"
                fill={colors.error}
                name="Churned Subscriptions"
                opacity={0.8}
              />
              <Line
                yAxisId="right"
                type="monotone"
                dataKey="active_subscriptions"
                stroke={colors.info}
                strokeWidth={3}
                name="Active Subscriptions"
                dot={{ fill: colors.info, strokeWidth: 0, r: 4 }}
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  );
};