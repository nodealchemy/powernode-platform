import React from 'react';
import { BarChart3, PieChart, TrendingUp } from 'lucide-react';

export interface TimeSeriesData {
  x: string;
  y: number;
}

export interface BarData {
  label: string;
  value: number;
}

export interface PieData {
  label: string;
  value: number;
}

export type ChartData = TimeSeriesData[] | BarData[] | PieData[];

interface AuditLogChartProps {
  title: string;
  type: 'line' | 'bar' | 'pie' | 'doughnut';
  data: ChartData;
  timeRange?: { label: string; value: string; days: number };
  height?: number;
  loading?: boolean;
}

export const AuditLogChart: React.FC<AuditLogChartProps> = ({
  title,
  type,
  data,
  timeRange,
  height = 300,
  loading = false
}) => {
  const chartIcon = {
    line: <TrendingUp className="w-4 h-4" />,
    bar: <BarChart3 className="w-4 h-4" />,
    pie: <PieChart className="w-4 h-4" />,
    doughnut: <PieChart className="w-4 h-4" />
  };

  const calculateTotal = (): number => {
    if (data.length === 0) return 0;

    let total = 0;
    for (const item of data) {
      if ('value' in item) {
        total += (item as BarData | PieData).value;
      } else if ('y' in item) {
        total += (item as TimeSeriesData).y;
      }
    }
    return total;
  };

  if (loading) {
    return (
      <div className="bg-theme-background rounded-lg border border-theme p-6">
        <div className="animate-pulse">
          <div className="h-6 bg-theme-surface rounded w-1/3 mb-4"></div>
          <div className="h-64 bg-theme-surface rounded"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-theme-background rounded-lg border border-theme p-6">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <div className="p-1 bg-theme-interactive-primary bg-opacity-10 rounded">
            {/* eslint-disable-next-line security/detect-object-injection */}
            {chartIcon[type]}
          </div>
          <h3 className="text-lg font-semibold text-theme-primary">{title}</h3>
        </div>
        {timeRange && (
          <div className="text-xs text-theme-secondary">
            {timeRange.label}
          </div>
        )}
      </div>

      <div className="relative" style={{ height }}>
        {data.length === 0 ? (
          <div className="flex items-center justify-center h-full text-theme-tertiary">
            No data available
          </div>
        ) : (
          <>
            {type === 'line' && <LineChart data={data as TimeSeriesData[]} height={height} />}
            {type === 'bar' && <BarChart data={data as BarData[]} height={height} />}
            {(type === 'pie' || type === 'doughnut') && <PieChartComponent data={data as PieData[]} height={height} isDoughnut={type === 'doughnut'} />}
          </>
        )}
      </div>

      <div className="mt-4 pt-4 border-t border-theme">
        <div className="flex items-center justify-between text-sm">
          <span className="text-theme-secondary">Total Events</span>
          <span className="font-semibold text-theme-primary">
            {calculateTotal().toLocaleString()}
          </span>
        </div>
      </div>
    </div>
  );
};

const LineChart: React.FC<{ data: TimeSeriesData[]; height: number }> = ({ data, height }) => {
  const chartHeight = height - 40;
  const chartWidth = 100;
  const maxValue = data.length > 0 ? Math.max(...data.map(d => d.y)) : 1;

  const points = data.map((d, i) => {
    const x = (i / Math.max(data.length - 1, 1)) * chartWidth;
    const y = chartHeight - (d.y / maxValue) * chartHeight;
    return `${x},${y}`;
  }).join(' ');

  return (
    <div className="w-full h-full flex items-center justify-center">
      <svg className="w-full h-full" viewBox={`0 0 ${chartWidth} ${chartHeight}`}>
        <defs>
          <linearGradient id="lineGradient" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" style={{ stopColor: '#3B82F6', stopOpacity: 0.3 }} />
            <stop offset="100%" style={{ stopColor: '#3B82F6', stopOpacity: 0 }} />
          </linearGradient>
        </defs>

        {/* Grid lines */}
        {[...Array(5)].map((_, i) => (
          <line
            key={i}
            x1="0"
            y1={i * (chartHeight / 4)}
            x2={chartWidth}
            y2={i * (chartHeight / 4)}
            stroke="#E5E7EB"
            strokeWidth="0.5"
          />
        ))}

        {/* Area */}
        <polygon
          points={`0,${chartHeight} ${points} ${chartWidth},${chartHeight}`}
          fill="url(#lineGradient)"
        />

        {/* Line */}
        <polyline
          points={points}
          fill="none"
          stroke="#3B82F6"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />

        {/* Points */}
        {data.map((d, i) => {
          const x = (i / Math.max(data.length - 1, 1)) * chartWidth;
          const y = chartHeight - (d.y / maxValue) * chartHeight;
          return (
            <circle
              key={i}
              cx={x}
              cy={y}
              r="2"
              fill="#3B82F6"
              stroke="white"
              strokeWidth="1"
            />
          );
        })}
      </svg>
    </div>
  );
};

const BarChart: React.FC<{ data: BarData[]; height: number }> = ({ data, height }) => {
  const chartHeight = height - 40;
  const maxValue = data.length > 0 ? Math.max(...data.map(d => d.value)) : 1;

  return (
    <div className="w-full h-full flex items-end justify-center gap-2 px-4">
      {data.map((item, i) => {
        const barHeight = (item.value / maxValue) * chartHeight;
        const colors = ['#3B82F6', '#10B981', '#F59E0B', '#EF4444', '#8B5CF6'];

        return (
          <div key={i} className="flex flex-col items-center gap-1">
            <div className="text-xs text-theme-secondary font-medium">
              {item.value}
            </div>
            <div
              className="w-8 rounded-t transition-all duration-300"
              style={{
                height: Math.max(barHeight, 4),
                backgroundColor: colors[i % colors.length]
              }}
            />
            <div className="text-xs text-theme-tertiary">
              {item.label.substring(0, 3)}
            </div>
          </div>
        );
      })}
    </div>
  );
};

const PieChartComponent: React.FC<{ data: PieData[]; height: number; isDoughnut?: boolean }> = ({ data, height, isDoughnut = false }) => {
  const total = data.length > 0 ? data.reduce((acc, item) => acc + item.value, 0) : 1;
  const colors = ['#3B82F6', '#10B981', '#F59E0B', '#EF4444', '#8B5CF6'];
  const size = Math.min(height - 60, 200);
  const radius = size / 2;
  const innerRadius = isDoughnut ? radius * 0.6 : 0;

  let currentAngle = 0;

  return (
    <div className="w-full h-full flex items-center justify-center">
      <div className="flex items-center gap-6">
        <svg width={size} height={size} className="transform -rotate-90">
          {data.map((item, i) => {
            const percentage = item.value / total;
            const angle = percentage * 360;
            const x1 = radius + radius * Math.cos((currentAngle * Math.PI) / 180);
            const y1 = radius + radius * Math.sin((currentAngle * Math.PI) / 180);
            const x2 = radius + radius * Math.cos(((currentAngle + angle) * Math.PI) / 180);
            const y2 = radius + radius * Math.sin(((currentAngle + angle) * Math.PI) / 180);

            const innerX1 = radius + innerRadius * Math.cos((currentAngle * Math.PI) / 180);
            const innerY1 = radius + innerRadius * Math.sin((currentAngle * Math.PI) / 180);
            const innerX2 = radius + innerRadius * Math.cos(((currentAngle + angle) * Math.PI) / 180);
            const innerY2 = radius + innerRadius * Math.sin(((currentAngle + angle) * Math.PI) / 180);

            const largeArcFlag = angle > 180 ? 1 : 0;

            const pathData = isDoughnut
              ? `M ${x1} ${y1} A ${radius} ${radius} 0 ${largeArcFlag} 1 ${x2} ${y2} L ${innerX2} ${innerY2} A ${innerRadius} ${innerRadius} 0 ${largeArcFlag} 0 ${innerX1} ${innerY1} Z`
              : `M ${radius} ${radius} L ${x1} ${y1} A ${radius} ${radius} 0 ${largeArcFlag} 1 ${x2} ${y2} Z`;

            currentAngle += angle;

            return (
              <path
                key={i}
                d={pathData}
                fill={colors[i % colors.length]}
                stroke="white"
                strokeWidth="2"
              />
            );
          })}
        </svg>

        <div className="space-y-2">
          {data.map((item, i) => (
            <div key={i} className="flex items-center gap-2">
              <div
                className="w-3 h-3 rounded-full"
                style={{ backgroundColor: colors[i % colors.length] }}
              />
              <span className="text-sm text-theme-primary">{item.label}</span>
              <span className="text-sm text-theme-secondary">({item.value})</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
