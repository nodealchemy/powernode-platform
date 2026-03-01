import React from 'react';
import {
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  BarChart, Bar, ComposedChart, Line, Legend,
} from 'recharts';
import type { TeamAnalytics } from '@/shared/services/ai/TeamsApiService';
import {
  KpiCard, tooltipStyle,
  formatCurrency, formatNumber, mapToChartData, mapTimeSeriesData,
} from './teamAnalyticsHelpers';

interface CostBreakdownChartProps {
  cost: TeamAnalytics['cost'];
}

export const CostBreakdownChart: React.FC<CostBreakdownChartProps> = ({ cost }) => (
  <div className="space-y-6">
    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
      <KpiCard label="Total Cost" value={formatCurrency(cost.total_cost_usd)} />
      <KpiCard label="Total Tokens" value={formatNumber(cost.total_tokens)} />
      <KpiCard label="Avg Cost/Execution" value={formatCurrency(cost.avg_cost_per_execution)} />
      <KpiCard label="Avg Tokens/Execution" value={formatNumber(cost.avg_tokens_per_execution)} />
    </div>

    {Object.keys(cost.cost_by_day).length > 0 && (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Daily Cost &amp; Tokens</h4>
        <ResponsiveContainer width="100%" height={300}>
          <ComposedChart data={mapTimeSeriesData(cost.cost_by_day, cost.tokens_by_day, 'cost', 'tokens')}>
            <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
            <XAxis dataKey="date" tick={{ fontSize: 11 }} />
            <YAxis yAxisId="left" tickFormatter={(v) => `$${v}`} tick={{ fontSize: 11 }} />
            <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 11 }} />
            <Tooltip contentStyle={tooltipStyle} />
            <Legend />
            <Bar yAxisId="left" dataKey="cost" name="Cost (USD)" fill="var(--color-success, #10B981)" opacity={0.7} />
            <Line yAxisId="right" type="monotone" dataKey="tokens" name="Tokens" stroke="var(--color-info, #3B82F6)" strokeWidth={2} dot={false} />
          </ComposedChart>
        </ResponsiveContainer>
      </div>
    )}

    {Object.keys(cost.cost_by_status).length > 0 && (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Cost by Status</h4>
        <ResponsiveContainer width="100%" height={200}>
          <BarChart data={mapToChartData(cost.cost_by_status)} layout="vertical">
            <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
            <XAxis type="number" tickFormatter={(v) => `$${v}`} tick={{ fontSize: 11 }} />
            <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={80} />
            <Tooltip contentStyle={tooltipStyle} formatter={(v) => formatCurrency(Number(v))} />
            <Bar dataKey="value" name="Cost" fill="var(--color-warning, #F59E0B)" />
          </BarChart>
        </ResponsiveContainer>
      </div>
    )}

    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      <KpiCard label="Cost Per Task" value={formatCurrency(cost.cost_per_task)} />
      <KpiCard label="Cost Per Message" value={formatCurrency(cost.cost_per_message)} />
    </div>

    {cost.top_cost_executions.length > 0 && (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Top Cost Drivers</h4>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-theme text-left">
                <th className="pb-2 text-theme-secondary font-medium">Execution</th>
                <th className="pb-2 text-theme-secondary font-medium">Objective</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Cost</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Tokens</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Date</th>
              </tr>
            </thead>
            <tbody>
              {cost.top_cost_executions.map(e => (
                <tr key={e.id} className="border-b border-theme/50">
                  <td className="py-2 font-mono text-xs text-theme-primary">{e.execution_id.slice(0, 8)}</td>
                  <td className="py-2 text-theme-primary truncate max-w-[200px]">{e.objective || '—'}</td>
                  <td className="py-2 text-right text-theme-primary">{formatCurrency(e.cost_usd)}</td>
                  <td className="py-2 text-right text-theme-secondary">{formatNumber(e.tokens)}</td>
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
