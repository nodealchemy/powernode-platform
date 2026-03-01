import React from 'react';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from 'recharts';
import type { TeamAnalytics } from '@/shared/services/ai/TeamsApiService';
import { KpiCard, tooltipStyle, formatCurrency, formatNumber, mapTimeSeriesData } from './teamAnalyticsHelpers';

interface TeamOverviewMetricsProps {
  overview: TeamAnalytics['overview'];
}

export const TeamOverviewMetrics: React.FC<TeamOverviewMetricsProps> = ({ overview }) => (
  <div className="space-y-6">
    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
      <KpiCard label="Total Executions" value={formatNumber(overview.total_executions)} />
      <KpiCard label="Completed" value={formatNumber(overview.completed_executions)} />
      <KpiCard label="Failed" value={formatNumber(overview.failed_executions)} />
      <KpiCard label="Success Rate" value={`${overview.success_rate}%`} />
      <KpiCard label="Total Tasks" value={formatNumber(overview.total_tasks)} subtext={`${overview.completed_tasks} completed, ${overview.failed_tasks} failed`} />
      <KpiCard label="Total Messages" value={formatNumber(overview.total_messages)} />
      <KpiCard label="Total Tokens" value={formatNumber(overview.total_tokens_used)} />
      <KpiCard label="Total Cost" value={formatCurrency(overview.total_cost_usd)} />
    </div>

    {Object.keys(overview.executions_by_day).length > 0 && (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Executions Over Time</h4>
        <ResponsiveContainer width="100%" height={250}>
          <AreaChart data={mapTimeSeriesData(overview.executions_by_day)}>
            <defs>
              <linearGradient id="execGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="var(--color-info, #3B82F6)" stopOpacity={0.3} />
                <stop offset="95%" stopColor="var(--color-info, #3B82F6)" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
            <XAxis dataKey="date" tick={{ fontSize: 11 }} />
            <YAxis tick={{ fontSize: 11 }} allowDecimals={false} />
            <Tooltip contentStyle={tooltipStyle} />
            <Area type="monotone" dataKey="value" name="Executions" stroke="var(--color-info, #3B82F6)" fillOpacity={1} fill="url(#execGrad)" />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    )}

    {Object.keys(overview.cost_by_day).length > 0 && (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Cost Trend</h4>
        <ResponsiveContainer width="100%" height={250}>
          <AreaChart data={mapTimeSeriesData(overview.cost_by_day)}>
            <defs>
              <linearGradient id="costGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="var(--color-success, #10B981)" stopOpacity={0.3} />
                <stop offset="95%" stopColor="var(--color-success, #10B981)" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
            <XAxis dataKey="date" tick={{ fontSize: 11 }} />
            <YAxis tickFormatter={(v) => `$${v}`} tick={{ fontSize: 11 }} />
            <Tooltip contentStyle={tooltipStyle} formatter={(v) => formatCurrency(Number(v))} />
            <Area type="monotone" dataKey="value" name="Cost (USD)" stroke="var(--color-success, #10B981)" fillOpacity={1} fill="url(#costGrad)" />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    )}
  </div>
);
