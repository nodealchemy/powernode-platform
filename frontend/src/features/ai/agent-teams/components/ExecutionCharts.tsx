import React from 'react';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell,
} from 'recharts';
import type { TeamAnalytics } from '@/shared/services/ai/TeamsApiService';
import {
  KpiCard, CHART_COLORS, tooltipStyle,
  formatDuration, mapToChartData, mapTimeSeriesData, renderPieLabel,
} from './teamAnalyticsHelpers';

interface ExecutionChartsProps {
  performance: TeamAnalytics['performance'];
}

export const ExecutionCharts: React.FC<ExecutionChartsProps> = ({ performance }) => (
  <div className="space-y-6">
    <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
      <KpiCard label="Avg Duration" value={formatDuration(performance.avg_duration_ms)} />
      <KpiCard label="Median Duration" value={formatDuration(performance.median_duration_ms)} />
      <KpiCard label="P95 Duration" value={formatDuration(performance.p95_duration_ms)} />
      <KpiCard label="Min Duration" value={formatDuration(performance.min_duration_ms)} />
      <KpiCard label="Max Duration" value={formatDuration(performance.max_duration_ms)} />
    </div>

    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
      <KpiCard label="Avg Tasks/Execution" value={performance.avg_tasks_per_execution} />
      <KpiCard label="Avg Messages/Execution" value={performance.avg_messages_per_execution} />
      <KpiCard label="Throughput/Day" value={performance.throughput_per_day} />
    </div>

    {Object.keys(performance.status_breakdown).length > 0 && (
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <h4 className="text-sm font-medium text-theme-primary mb-3">Status Breakdown</h4>
          <ResponsiveContainer width="100%" height={250}>
            <PieChart>
              <Pie data={mapToChartData(performance.status_breakdown)} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={90} label={renderPieLabel}>
                {mapToChartData(performance.status_breakdown).map((_, i) => (
                  <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                ))}
              </Pie>
              <Tooltip contentStyle={tooltipStyle} />
            </PieChart>
          </ResponsiveContainer>
        </div>

        {Object.keys(performance.duration_by_day).length > 0 && (
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <h4 className="text-sm font-medium text-theme-primary mb-3">Avg Duration Over Time</h4>
            <ResponsiveContainer width="100%" height={250}>
              <AreaChart data={mapTimeSeriesData(performance.duration_by_day)}>
                <defs>
                  <linearGradient id="durGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="var(--color-interactive-primary, #8B5CF6)" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="var(--color-interactive-primary, #8B5CF6)" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                <YAxis tickFormatter={(v) => formatDuration(v)} tick={{ fontSize: 11 }} />
                <Tooltip contentStyle={tooltipStyle} formatter={(v) => formatDuration(Number(v))} />
                <Area type="monotone" dataKey="value" name="Avg Duration" stroke="var(--color-interactive-primary, #8B5CF6)" fillOpacity={1} fill="url(#durGrad)" />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>
    )}

    {performance.slowest_executions.length > 0 && (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Slowest Executions</h4>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-theme text-left">
                <th className="pb-2 text-theme-secondary font-medium">Execution</th>
                <th className="pb-2 text-theme-secondary font-medium">Objective</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Duration</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Tasks</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Date</th>
              </tr>
            </thead>
            <tbody>
              {performance.slowest_executions.map(e => (
                <tr key={e.id} className="border-b border-theme/50">
                  <td className="py-2 font-mono text-xs text-theme-primary">{e.execution_id.slice(0, 8)}</td>
                  <td className="py-2 text-theme-primary truncate max-w-[200px]">{e.objective || '—'}</td>
                  <td className="py-2 text-right text-theme-primary">{formatDuration(e.duration_ms)}</td>
                  <td className="py-2 text-right text-theme-secondary">{e.tasks_total}</td>
                  <td className="py-2 text-right text-theme-secondary text-xs">{new Date(e.created_at).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    )}
  </div>
);
