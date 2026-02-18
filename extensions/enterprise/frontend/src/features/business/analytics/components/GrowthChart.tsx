import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  Bar,
  ComposedChart,
  Area,
  AreaChart
} from 'recharts';
import { format, parseISO } from 'date-fns';
import { useChartColors } from '@/shared/hooks/useThemeColors';

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
    } catch (_error) {
      return dateString;
    }
  };

  // Use the built-in growth color function
  const getGrowthColor = colors.getGrowthColor;

  interface TooltipPayload {
    name: string;
    value: number;
    color: string;
  }

  interface CustomTooltipProps {
    active?: boolean;
    payload?: TooltipPayload[];
    label?: string;
  }

  const CustomTooltip = ({ active, payload, label }: CustomTooltipProps) => {
    if (active && payload && payload.length) {
      return (
        <div className="card-theme p-4 border-theme rounded-lg shadow-lg">
          <p className="font-semibold text-theme-primary">{formatDate(label || '')}</p>
          {payload.map((entry, index: number) => (
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

  // Guard against empty data
  if (!data || data.length === 0) {
    return (
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">{title}</h3>
        <div className="h-64 flex items-center justify-center">
          <p className="text-theme-secondary">No growth data available</p>
        </div>
      </div>
    );
  }

  if (compact) {
    return (
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">{title}</h3>
        <div className="h-64" style={{ minHeight: 256, minWidth: 0 }}>
          <ResponsiveContainer width="100%" height={256} debounce={100}>
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
      <div className="card-theme rounded-lg shadow-sm border-theme p-4 sm:p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Growth Metrics</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
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
      <div className="card-theme rounded-lg shadow-sm border-theme p-4 sm:p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Monthly Growth Rate</h3>
        <div className="h-64 sm:h-80 lg:h-96" style={{ minHeight: 256, minWidth: 0 }}>
          <ResponsiveContainer width="100%" height={256} debounce={100}>
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
      <div className="card-theme rounded-lg shadow-sm border-theme p-4 sm:p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Revenue Growth Components</h3>
        <div className="h-64 sm:h-80 lg:h-96" style={{ minHeight: 256, minWidth: 0 }}>
          <ResponsiveContainer width="100%" height={256} debounce={100}>
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
      <div className="card-theme rounded-lg shadow-sm border-theme p-4 sm:p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Growth Rate by Month</h3>
        <div className="grid grid-cols-2 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-12 gap-2">
          {data.map((item, index) => (
            <div key={index} className="text-center">
              <div
                className="growth-heatmap-cell w-full h-12 sm:h-14 md:h-16 rounded-lg flex items-center justify-center text-white font-semibold text-xs sm:text-sm shadow-sm"
                style={{ backgroundColor: getGrowthColor(item.growth_rate) }}
                title={`${formatDate(item.date)}: ${formatPercentage(item.growth_rate)}`}
              >
                {formatPercentage(item.growth_rate)}
              </div>
              <p className="text-xs text-theme-secondary mt-1 truncate">
                {formatDate(item.date)}
              </p>
            </div>
          ))}
        </div>
        
        {/* Legend */}
        <div className="flex flex-wrap items-center justify-center gap-3 mt-4 text-xs">
          <div className="flex items-center space-x-2">
            <div className="w-3 h-3 rounded bg-theme-danger-solid shadow-sm"></div>
            <span className="text-theme-secondary">High Decline (&lt;-5%)</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-3 h-3 rounded bg-theme-warning-solid shadow-sm"></div>
            <span className="text-theme-secondary">Slight Decline (-5% to 0%)</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-3 h-3 rounded bg-theme-info-solid shadow-sm"></div>
            <span className="text-theme-secondary">Positive Growth (0% to 5%)</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-3 h-3 rounded bg-theme-success-solid shadow-sm"></div>
            <span className="text-theme-secondary">High Growth (&gt;5%)</span>
          </div>
        </div>
      </div>
    </div>
  );
};