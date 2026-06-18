import React from 'react';
import {
  AreaChart, Area, LineChart, Line, BarChart, Bar,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from 'recharts';
import { CHART_COLORS, tooltipStyle } from '@/features/ai/agent-teams/components/teamAnalyticsHelpers';

/**
 * Recharts wrappers for the AIOps dashboard. Each takes already-mapped data so
 * the section components stay declarative. Theme tokens supply chart colors via
 * CSS variables (see `CHART_COLORS`); axis/grid styling matches the agent-teams
 * charts for visual consistency.
 */

export interface TrendSeries {
  key: string;
  name: string;
  color: string;
}

interface ChartFrameProps {
  title: string;
  height?: number;
  children: React.ReactElement;
}

const ChartFrame: React.FC<ChartFrameProps> = ({ title, height = 260, children }) => (
  <div className="bg-theme-surface border border-theme rounded-lg p-4">
    <h4 className="text-sm font-medium text-theme-primary mb-3">{title}</h4>
    <ResponsiveContainer width="100%" height={height}>
      {children}
    </ResponsiveContainer>
  </div>
);

/** Single-series filled area chart, used for cost-over-time. */
export const CostAreaChart: React.FC<{
  title: string;
  data: Array<Record<string, number | string>>;
  xKey: string;
  yKey: string;
  name: string;
}> = ({ title, data, xKey, yKey, name }) => (
  <ChartFrame title={title}>
    <AreaChart data={data}>
      <defs>
        <linearGradient id="aiopsCostGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="5%" stopColor="var(--color-success, #10B981)" stopOpacity={0.3} />
          <stop offset="95%" stopColor="var(--color-success, #10B981)" stopOpacity={0} />
        </linearGradient>
      </defs>
      <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
      <XAxis dataKey={xKey} tick={{ fontSize: 11 }} />
      <YAxis tick={{ fontSize: 11 }} />
      <Tooltip contentStyle={tooltipStyle} />
      <Area type="monotone" dataKey={yKey} name={name} stroke="var(--color-success, #10B981)" fillOpacity={1} fill="url(#aiopsCostGrad)" />
    </AreaChart>
  </ChartFrame>
);

/** Horizontal bar chart for categorical cost breakdowns (e.g. by provider). */
export const CategoryBarChart: React.FC<{
  title: string;
  data: Array<Record<string, number | string>>;
  xKey: string;
  yKey: string;
  name: string;
}> = ({ title, data, xKey, yKey, name }) => (
  <ChartFrame title={title} height={Math.max(200, data.length * 44)}>
    <BarChart data={data} layout="vertical">
      <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
      <XAxis type="number" tick={{ fontSize: 11 }} />
      <YAxis type="category" dataKey={xKey} tick={{ fontSize: 11 }} width={120} />
      <Tooltip contentStyle={tooltipStyle} />
      <Bar dataKey={yKey} name={name} fill="var(--color-info, #3B82F6)" />
    </BarChart>
  </ChartFrame>
);

/** Multi-series line chart for hourly trend buckets. */
export const TrendLineChart: React.FC<{
  title: string;
  data: Array<Record<string, number | string>>;
  xKey: string;
  series: TrendSeries[];
}> = ({ title, data, xKey, series }) => (
  <ChartFrame title={title}>
    <LineChart data={data}>
      <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
      <XAxis dataKey={xKey} tick={{ fontSize: 11 }} />
      <YAxis tick={{ fontSize: 11 }} />
      <Tooltip contentStyle={tooltipStyle} />
      {series.map((s, i) => (
        <Line
          key={s.key}
          type="monotone"
          dataKey={s.key}
          name={s.name}
          stroke={s.color || CHART_COLORS[i % CHART_COLORS.length]}
          dot={false}
          strokeWidth={2}
        />
      ))}
    </LineChart>
  </ChartFrame>
);
