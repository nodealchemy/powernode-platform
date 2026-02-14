import React from 'react';
import {
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, BarChart, Bar,
} from 'recharts';
import type { TeamAnalytics } from '@/shared/services/ai/TeamsApiService';
import {
  KpiCard, CHART_COLORS, tooltipStyle,
  formatCurrency, formatDuration, formatNumber, mapToChartData, renderPieLabel,
} from './teamAnalyticsHelpers';

interface AgentUtilizationChartProps {
  agents: TeamAnalytics['agents'];
}

export const AgentUtilizationChart: React.FC<AgentUtilizationChartProps> = ({ agents }) => (
  <div className="space-y-6">
    {Object.keys(agents.workload_by_role).length > 0 && (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Workload by Role</h4>
        <ResponsiveContainer width="100%" height={Math.max(150, Object.keys(agents.workload_by_role).length * 40)}>
          <BarChart data={mapToChartData(agents.workload_by_role)} layout="vertical">
            <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
            <XAxis type="number" tick={{ fontSize: 11 }} allowDecimals={false} />
            <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={120} />
            <Tooltip contentStyle={tooltipStyle} />
            <Bar dataKey="value" name="Tasks" fill="var(--color-interactive-primary, #8B5CF6)" />
          </BarChart>
        </ResponsiveContainer>
      </div>
    )}

    {agents.role_stats.length > 0 && (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Agent Leaderboard</h4>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-theme text-left">
                <th className="pb-2 text-theme-secondary font-medium">Role</th>
                <th className="pb-2 text-theme-secondary font-medium">Agent</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Tasks</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Success</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Avg Duration</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Tokens</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Cost</th>
                <th className="pb-2 text-theme-secondary font-medium text-right">Messages</th>
              </tr>
            </thead>
            <tbody>
              {[...agents.role_stats].sort((a, b) => b.success_rate - a.success_rate).map(rs => (
                <tr key={rs.role_id} className="border-b border-theme/50">
                  <td className="py-2 text-theme-primary">
                    <span className="font-medium">{rs.role_name}</span>
                    <span className="ml-2 text-xs px-1.5 py-0.5 bg-theme-accent/10 text-theme-accent rounded">{rs.role_type}</span>
                  </td>
                  <td className="py-2 text-theme-secondary">{rs.agent_name || '—'}</td>
                  <td className="py-2 text-right text-theme-primary">{rs.tasks_total}</td>
                  <td className="py-2 text-right">
                    <span className={rs.success_rate >= 80 ? 'text-theme-success' : rs.success_rate >= 50 ? 'text-theme-warning' : 'text-theme-danger'}>
                      {rs.success_rate}%
                    </span>
                  </td>
                  <td className="py-2 text-right text-theme-secondary">{formatDuration(rs.avg_duration_ms)}</td>
                  <td className="py-2 text-right text-theme-secondary">{formatNumber(rs.total_tokens)}</td>
                  <td className="py-2 text-right text-theme-secondary">{formatCurrency(rs.total_cost_usd)}</td>
                  <td className="py-2 text-right text-theme-secondary">{rs.messages_sent + rs.messages_received}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    )}

    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
      {Object.keys(agents.task_type_distribution).length > 0 && (
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <h4 className="text-sm font-medium text-theme-primary mb-3">Task Type Distribution</h4>
          <ResponsiveContainer width="100%" height={250}>
            <PieChart>
              <Pie data={mapToChartData(agents.task_type_distribution)} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={90} label={renderPieLabel}>
                {mapToChartData(agents.task_type_distribution).map((_, i) => (
                  <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                ))}
              </Pie>
              <Tooltip contentStyle={tooltipStyle} />
            </PieChart>
          </ResponsiveContainer>
        </div>
      )}

      {Object.keys(agents.top_tools).length > 0 && (
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <h4 className="text-sm font-medium text-theme-primary mb-3">Top Tools</h4>
          <ResponsiveContainer width="100%" height={250}>
            <BarChart data={mapToChartData(agents.top_tools)} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
              <XAxis type="number" tick={{ fontSize: 11 }} allowDecimals={false} />
              <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={120} />
              <Tooltip contentStyle={tooltipStyle} />
              <Bar dataKey="value" name="Usage Count" fill="var(--color-info, #3B82F6)" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>

    <KpiCard label="Unassigned Tasks" value={agents.unassigned_tasks} />
  </div>
);
