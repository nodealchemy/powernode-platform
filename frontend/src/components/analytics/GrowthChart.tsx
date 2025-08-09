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
  BarChart,
  Bar,
  ComposedChart,
  Area,
  AreaChart
} from 'recharts';
import { format, parseISO } from 'date-fns';
import { useChartColors } from '../../hooks/useThemeColors';

interface GrowthChartProps {
  data: Array<{
    date: string;
    mrr: number;
    growth_rate: number;
    new_revenue: number;
    churned_revenue: number;
  }>;
  compoundGrowthRate?: number;
  forecasting?: {
    next_month_projection: number;
    confidence_interval: string;
  };
  title: string;
  compact?: boolean;
}

export const GrowthChart: React.FC<GrowthChartProps> = ({ 
  data, 
  compoundGrowthRate,
  forecasting,
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

  const formatPercentage = (value: number) => {
    return `${value.toFixed(1)}%`;
  };

  const formatDate = (dateString: string) => {
    try {
      return format(parseISO(dateString), 'MMM yyyy');
    } catch {
      return dateString;
    }
  };

  // Use the built-in growth color function
  const getGrowthColor = colors.getGrowthColor;

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div className="card-theme p-4 border-theme rounded-lg shadow-lg">
          <p className="font-semibold text-theme-primary">{formatDate(label)}</p>
          {payload.map((entry: any, index: number) => (
            <p key={index} className="text-sm" style={{ color: entry.color }}>
              {entry.name}: {
                entry.name.includes('Rate') || entry.name.includes('%') 
                  ? formatPercentage(entry.value)
                  : formatCurrency(entry.value)
              }
            </p>
          ))}
        </div>
      );
    }
    return null;
  };

  const GrowthRateCell = ({ data: cellData }: any) => {
    const color = getGrowthColor(cellData.growth_rate);
    return (
      <g>
        <rect
          x={cellData.x - 15}
          y={cellData.y - 10}
          width={30}
          height={20}
          fill={color}
          opacity={0.8}
          rx={4}
        />
        <text
          x={cellData.x}
          y={cellData.y + 3}
          textAnchor="middle"
          fontSize={10}
          fill="white"
          fontWeight="bold"
        >
          {formatPercentage(cellData.growth_rate)}
        </text>
      </g>
    );
  };

  if (compact) {
    return (
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">{title}</h3>
        <div className="h-64">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke={colors.border} />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
                tick={{ fontSize: 12 }}
              />
              <YAxis 
                tickFormatter={formatPercentage}
                tick={{ fontSize: 12 }}
              />
              <Tooltip content={<CustomTooltip />} />
              <Line
                type="monotone"
                dataKey="growth_rate"
                stroke={colors.success}
                strokeWidth={2}
                dot={{ fill: colors.success, strokeWidth: 0, r: 4 }}
                activeDot={{ r: 6, stroke: colors.success, strokeWidth: 2 }}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Growth Metrics Summary */}
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Growth Metrics</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {compoundGrowthRate !== undefined && (
            <div>
              <p className="text-sm text-theme-secondary">Compound Monthly Growth Rate</p>
              <p className={`text-2xl font-bold ${compoundGrowthRate >= 0 ? 'text-theme-success' : 'text-theme-error'}`}>
                {formatPercentage(compoundGrowthRate)}
              </p>
            </div>
          )}
          {forecasting && (
            <>
              <div>
                <p className="text-sm text-theme-secondary">Next Month Projection</p>
                <p className="text-2xl font-bold text-theme-info">
                  {formatCurrency(forecasting.next_month_projection)}
                </p>
              </div>
              <div>
                <p className="text-sm text-theme-secondary">Confidence Interval</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {forecasting.confidence_interval}
                </p>
              </div>
            </>
          )}
        </div>
      </div>

      {/* Growth Rate Trend */}
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Monthly Growth Rate</h3>
        <div className="h-96">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={data}>
              <defs>
                <linearGradient id="growthGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor={colors.success} stopOpacity={0.8}/>
                  <stop offset="95%" stopColor={colors.success} stopOpacity={0.1}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke={colors.border} />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
              />
              <YAxis 
                tickFormatter={formatPercentage}
              />
              <Tooltip content={<CustomTooltip />} />
              <Area
                type="monotone"
                dataKey="growth_rate"
                stroke={colors.success}
                strokeWidth={3}
                fill="url(#growthGradient)"
                name="Growth Rate %"
                dot={{ fill: colors.success, strokeWidth: 0, r: 4 }}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Revenue Components */}
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Revenue Growth Components</h3>
        <div className="h-96">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke={colors.border} />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
              />
              <YAxis yAxisId="left" tickFormatter={(value) => formatCurrency(value)} />
              <YAxis yAxisId="right" orientation="right" />
              <Tooltip content={<CustomTooltip />} />
              <Legend />
              <Bar
                yAxisId="left"
                dataKey="new_revenue"
                fill={colors.success}
                name="New Revenue"
                opacity={0.8}
              />
              <Bar
                yAxisId="left"
                dataKey="churned_revenue"
                fill={colors.error}
                name="Churned Revenue"
                opacity={0.8}
              />
              <Line
                yAxisId="right"
                type="monotone"
                dataKey="mrr"
                stroke={colors.info}
                strokeWidth={3}
                name="Total MRR"
                dot={{ fill: colors.info, strokeWidth: 0, r: 4 }}
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Growth Rate Heatmap */}
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Growth Rate by Month</h3>
        <div className="grid grid-cols-4 md:grid-cols-6 lg:grid-cols-12 gap-2">
          {data.map((item, index) => (
            <div key={index} className="text-center">
              <div
                className="w-full h-16 rounded-md flex items-center justify-center text-white font-semibold text-sm"
                style={{ backgroundColor: getGrowthColor(item.growth_rate) }}
              >
                {formatPercentage(item.growth_rate)}
              </div>
              <p className="text-xs text-theme-tertiary mt-1">
                {formatDate(item.date)}
              </p>
            </div>
          ))}
        </div>
        
        {/* Legend */}
        <div className="flex items-center justify-center space-x-4 mt-4 text-xs">
          <div className="flex items-center space-x-1">
            <div className="w-3 h-3 rounded bg-theme-error"></div>
            <span>High Decline (&lt;-5%)</span>
          </div>
          <div className="flex items-center space-x-1">
            <div className="w-3 h-3 rounded bg-theme-warning"></div>
            <span>Slight Decline (-5% to 0%)</span>
          </div>
          <div className="flex items-center space-x-1">
            <div className="w-3 h-3 rounded bg-theme-info"></div>
            <span>Positive Growth (0% to 5%)</span>
          </div>
          <div className="flex items-center space-x-1">
            <div className="w-3 h-3 rounded bg-theme-success"></div>
            <span>High Growth (&gt;5%)</span>
          </div>
        </div>
      </div>
    </div>
  );
};