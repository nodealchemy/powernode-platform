import React, { useState, useMemo } from 'react';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, BarChart, Bar, ComposedChart, Line, Legend,
} from 'recharts';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import type { PieLabelRenderProps } from 'recharts';
import type { TeamAnalytics } from '@/shared/services/ai/TeamsApiService';

interface TeamAnalyticsDashboardProps {
  analytics: TeamAnalytics;
  onPeriodChange: (days: number) => void;
}

// -- Helpers --
const PERIOD_OPTIONS = [7, 14, 30, 90];
const CHART_COLORS = [
  'var(--color-success, #10B981)',
  'var(--color-info, #3B82F6)',
  'var(--color-warning, #F59E0B)',
  'var(--color-interactive-primary, #8B5CF6)',
  'var(--color-danger, #EF4444)',
  '#06B6D4', '#EC4899', '#84CC16', '#F97316', '#6366F1',
];

const tooltipStyle = {
  backgroundColor: 'var(--theme-bg-secondary)',
  border: '1px solid var(--theme-border)',
  borderRadius: '8px',
  fontSize: '12px',
};

const formatCurrency = (v: number): string =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(v);

const formatDuration = (ms: number | null | undefined): string => {
  if (ms == null) return '—';
  if (ms < 1000) return `${Math.round(ms)}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  return `${(ms / 60000).toFixed(1)}m`;
};

const formatNumber = (n: number | null | undefined): string => {
  if (n == null) return '—';
  return n.toLocaleString();
};

const mapToChartData = (record: Record<string, number>): Array<{ name: string; value: number }> =>
  Object.entries(record).map(([name, value]) => ({ name, value: Number(value) || 0 }));

const mapTimeSeriesData = (primary: Record<string, number>, secondary?: Record<string, number>, primaryKey = 'value', secondaryKey = 'value2') =>
  Object.entries(primary).map(([date, val]) => ({
    date: new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    [primaryKey]: Number(val) || 0,
    ...(secondary ? { [secondaryKey]: Number(secondary[date]) || 0 } : {}),
  }));

// KPI Card
const KpiCard: React.FC<{ label: string; value: string | number; subtext?: string }> = ({ label, value, subtext }) => (
  <div className="bg-theme-surface border border-theme rounded-lg p-4">
    <p className="text-xs text-theme-secondary truncate">{label}</p>
    <p className="text-xl font-bold text-theme-primary mt-1">{value}</p>
    {subtext && <p className="text-xs text-theme-secondary mt-1">{subtext}</p>}
  </div>
);

// Custom pie label
const renderPieLabel = (props: PieLabelRenderProps) => {
  const name = props.name ?? '';
  const percent = typeof props.percent === 'number' ? props.percent : 0;
  return percent > 0.05 ? `${name} (${(percent * 100).toFixed(0)}%)` : '';
};

const TeamAnalyticsDashboard: React.FC<TeamAnalyticsDashboardProps> = ({ analytics, onPeriodChange }) => {
  const [analyticsTab, setAnalyticsTab] = useState('overview');
  const { overview, performance, cost, agents, communication, quality } = analytics;

  const tabs = useMemo(() => [
    { id: 'overview', label: 'Overview' },
    { id: 'performance', label: 'Performance' },
    { id: 'cost', label: 'Cost' },
    { id: 'agents', label: 'Agents' },
    { id: 'communication', label: 'Communication' },
    { id: 'quality', label: 'Quality' },
  ], []);

  return (
    <div className="space-y-4">
      {/* Period selector */}
      <div className="flex items-center justify-between">
        <div className="flex gap-2">
          {PERIOD_OPTIONS.map(d => (
            <button
              key={d}
              onClick={() => onPeriodChange(d)}
              className={`px-3 py-1.5 text-sm rounded-md transition-colors ${
                analytics.period_days === d
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-surface text-theme-secondary hover:text-theme-primary border border-theme'
              }`}
            >
              {d}d
            </button>
          ))}
        </div>
        <span className="text-xs text-theme-secondary">
          Generated {new Date(analytics.generated_at).toLocaleString()}
        </span>
      </div>

      <TabContainer
        tabs={tabs}
        activeTab={analyticsTab}
        onTabChange={setAnalyticsTab}
        variant="pills"
        size="sm"
      >
        {/* ===== OVERVIEW ===== */}
        <TabPanel tabId="overview" activeTab={analyticsTab}>
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

            {/* Executions by day */}
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

            {/* Cost by day */}
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
        </TabPanel>

        {/* ===== PERFORMANCE ===== */}
        <TabPanel tabId="performance" activeTab={analyticsTab}>
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

            {/* Status breakdown pie */}
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

                {/* Duration over time */}
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

            {/* Slowest executions */}
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
        </TabPanel>

        {/* ===== COST ===== */}
        <TabPanel tabId="cost" activeTab={analyticsTab}>
          <div className="space-y-6">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <KpiCard label="Total Cost" value={formatCurrency(cost.total_cost_usd)} />
              <KpiCard label="Total Tokens" value={formatNumber(cost.total_tokens)} />
              <KpiCard label="Avg Cost/Execution" value={formatCurrency(cost.avg_cost_per_execution)} />
              <KpiCard label="Avg Tokens/Execution" value={formatNumber(cost.avg_tokens_per_execution)} />
            </div>

            {/* Cost + Tokens by day composed chart */}
            {Object.keys(cost.cost_by_day).length > 0 && (
              <div className="bg-theme-surface border border-theme rounded-lg p-4">
                <h4 className="text-sm font-medium text-theme-primary mb-3">Daily Cost & Tokens</h4>
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

            {/* Cost by status */}
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

            {/* Top cost drivers */}
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
        </TabPanel>

        {/* ===== AGENTS ===== */}
        <TabPanel tabId="agents" activeTab={analyticsTab}>
          <div className="space-y-6">
            {/* Workload by role */}
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

            {/* Agent leaderboard */}
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
              {/* Task type distribution */}
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

              {/* Top tools */}
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
        </TabPanel>

        {/* ===== COMMUNICATION ===== */}
        <TabPanel tabId="communication" activeTab={analyticsTab}>
          <div className="space-y-6">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <KpiCard label="Total Messages" value={formatNumber(communication.total_messages)} />
              <KpiCard label="Response Rate" value={`${communication.response_rate}%`} />
              <KpiCard label="Avg Response Time" value={communication.avg_response_time_seconds > 0 ? `${communication.avg_response_time_seconds.toFixed(1)}s` : '—'} />
              <KpiCard label="Escalations" value={formatNumber(communication.escalation_count)} subtext={`${communication.escalation_rate}% escalation rate`} />
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Message type distribution */}
              {Object.keys(communication.message_type_distribution).length > 0 && (
                <div className="bg-theme-surface border border-theme rounded-lg p-4">
                  <h4 className="text-sm font-medium text-theme-primary mb-3">Message Types</h4>
                  <ResponsiveContainer width="100%" height={250}>
                    <PieChart>
                      <Pie data={mapToChartData(communication.message_type_distribution)} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={90} label={renderPieLabel}>
                        {mapToChartData(communication.message_type_distribution).map((_, i) => (
                          <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                        ))}
                      </Pie>
                      <Tooltip contentStyle={tooltipStyle} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
              )}

              {/* Messages over time */}
              {Object.keys(communication.messages_by_day).length > 0 && (
                <div className="bg-theme-surface border border-theme rounded-lg p-4">
                  <h4 className="text-sm font-medium text-theme-primary mb-3">Messages Over Time</h4>
                  <ResponsiveContainer width="100%" height={250}>
                    <AreaChart data={mapTimeSeriesData(communication.messages_by_day)}>
                      <defs>
                        <linearGradient id="msgGrad" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="5%" stopColor="var(--color-warning, #F59E0B)" stopOpacity={0.3} />
                          <stop offset="95%" stopColor="var(--color-warning, #F59E0B)" stopOpacity={0} />
                        </linearGradient>
                      </defs>
                      <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
                      <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                      <YAxis tick={{ fontSize: 11 }} allowDecimals={false} />
                      <Tooltip contentStyle={tooltipStyle} />
                      <Area type="monotone" dataKey="value" name="Messages" stroke="var(--color-warning, #F59E0B)" fillOpacity={1} fill="url(#msgGrad)" />
                    </AreaChart>
                  </ResponsiveContainer>
                </div>
              )}
            </div>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <KpiCard label="Questions Asked" value={formatNumber(communication.questions_asked)} />
              <KpiCard label="Questions Answered" value={formatNumber(communication.questions_answered)} />
              <KpiCard label="Pending Responses" value={formatNumber(communication.pending_responses)} />
              <KpiCard label="High Priority" value={formatNumber(communication.high_priority_count)} />
            </div>

            {/* Role interaction matrix */}
            {communication.role_interactions.length > 0 && (
              <div className="bg-theme-surface border border-theme rounded-lg p-4">
                <h4 className="text-sm font-medium text-theme-primary mb-3">Role Interactions</h4>
                <RoleInteractionMatrix interactions={communication.role_interactions} />
              </div>
            )}
          </div>
        </TabPanel>

        {/* ===== QUALITY ===== */}
        <TabPanel tabId="quality" activeTab={analyticsTab}>
          <div className="space-y-6">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <KpiCard label="Total Reviews" value={formatNumber(quality.total_reviews)} />
              <KpiCard label="Approved" value={formatNumber(quality.approved_count)} />
              <KpiCard label="Rejected" value={formatNumber(quality.rejected_count)} />
              <KpiCard label="Approval Rate" value={`${quality.approval_rate}%`} />
            </div>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <KpiCard label="Avg Quality Score" value={quality.avg_quality_score} />
              <KpiCard label="Avg Review Duration" value={formatDuration(quality.avg_review_duration_ms)} />
              <KpiCard label="Avg Revisions" value={quality.avg_revision_count} />
              <KpiCard label="Pending Reviews" value={formatNumber(quality.pending_count)} />
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Review outcomes pie */}
              {quality.total_reviews > 0 && (
                <div className="bg-theme-surface border border-theme rounded-lg p-4">
                  <h4 className="text-sm font-medium text-theme-primary mb-3">Review Outcomes</h4>
                  <ResponsiveContainer width="100%" height={250}>
                    <PieChart>
                      <Pie
                        data={[
                          { name: 'Approved', value: quality.approved_count },
                          { name: 'Rejected', value: quality.rejected_count },
                          { name: 'Revision Requested', value: quality.revision_requested_count },
                          { name: 'Pending', value: quality.pending_count },
                        ].filter(d => d.value > 0)}
                        dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={90} label={renderPieLabel}
                      >
                        <Cell fill="var(--color-success, #10B981)" />
                        <Cell fill="var(--color-danger, #EF4444)" />
                        <Cell fill="var(--color-warning, #F59E0B)" />
                        <Cell fill="var(--color-info, #3B82F6)" />
                      </Pie>
                      <Tooltip contentStyle={tooltipStyle} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
              )}

              {/* Quality score distribution */}
              {Object.keys(quality.quality_score_distribution).length > 0 && (
                <div className="bg-theme-surface border border-theme rounded-lg p-4">
                  <h4 className="text-sm font-medium text-theme-primary mb-3">Quality Score Distribution</h4>
                  <ResponsiveContainer width="100%" height={250}>
                    <BarChart data={mapToChartData(quality.quality_score_distribution)}>
                      <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
                      <XAxis dataKey="name" tick={{ fontSize: 11 }} />
                      <YAxis tick={{ fontSize: 11 }} allowDecimals={false} />
                      <Tooltip contentStyle={tooltipStyle} />
                      <Bar dataKey="value" name="Reviews" fill="var(--color-interactive-primary, #8B5CF6)" />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              )}
            </div>

            {/* Findings */}
            {(Object.keys(quality.findings_by_severity).length > 0 || Object.keys(quality.findings_by_category).length > 0) && (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {Object.keys(quality.findings_by_severity).length > 0 && (
                  <div className="bg-theme-surface border border-theme rounded-lg p-4">
                    <h4 className="text-sm font-medium text-theme-primary mb-3">Findings by Severity</h4>
                    <ResponsiveContainer width="100%" height={200}>
                      <BarChart data={mapToChartData(quality.findings_by_severity)} layout="vertical">
                        <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
                        <XAxis type="number" tick={{ fontSize: 11 }} allowDecimals={false} />
                        <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={80} />
                        <Tooltip contentStyle={tooltipStyle} />
                        <Bar dataKey="value" name="Findings" fill="var(--color-danger, #EF4444)" />
                      </BarChart>
                    </ResponsiveContainer>
                  </div>
                )}

                {Object.keys(quality.findings_by_category).length > 0 && (
                  <div className="bg-theme-surface border border-theme rounded-lg p-4">
                    <h4 className="text-sm font-medium text-theme-primary mb-3">Findings by Category</h4>
                    <ResponsiveContainer width="100%" height={200}>
                      <BarChart data={mapToChartData(quality.findings_by_category)} layout="vertical">
                        <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
                        <XAxis type="number" tick={{ fontSize: 11 }} allowDecimals={false} />
                        <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={100} />
                        <Tooltip contentStyle={tooltipStyle} />
                        <Bar dataKey="value" name="Findings" fill="var(--color-warning, #F59E0B)" />
                      </BarChart>
                    </ResponsiveContainer>
                  </div>
                )}
              </div>
            )}

            {/* Learning metrics */}
            {quality.learning.total_learnings > 0 && (
              <>
                <h4 className="text-base font-medium text-theme-primary">Compound Learning</h4>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <KpiCard label="Total Learnings" value={formatNumber(quality.learning.total_learnings)} />
                  <KpiCard label="Avg Importance" value={quality.learning.avg_importance} />
                  <KpiCard label="Avg Confidence" value={quality.learning.avg_confidence} />
                  <KpiCard label="Avg Effectiveness" value={quality.learning.avg_effectiveness} />
                </div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <KpiCard label="Total Injections" value={formatNumber(quality.learning.total_injections)} />
                  <KpiCard label="Positive Outcomes" value={formatNumber(quality.learning.positive_outcomes)} />
                  <KpiCard label="Negative Outcomes" value={formatNumber(quality.learning.negative_outcomes)} />
                  <KpiCard label="Injection Success Rate" value={`${quality.learning.injection_success_rate}%`} />
                </div>

                {Object.keys(quality.learning.by_category).length > 0 && (
                  <div className="bg-theme-surface border border-theme rounded-lg p-4">
                    <h4 className="text-sm font-medium text-theme-primary mb-3">Learnings by Category</h4>
                    <ResponsiveContainer width="100%" height={Math.max(150, Object.keys(quality.learning.by_category).length * 35)}>
                      <BarChart data={mapToChartData(quality.learning.by_category)} layout="vertical">
                        <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
                        <XAxis type="number" tick={{ fontSize: 11 }} allowDecimals={false} />
                        <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={120} />
                        <Tooltip contentStyle={tooltipStyle} />
                        <Bar dataKey="value" name="Learnings" fill="var(--color-success, #10B981)" />
                      </BarChart>
                    </ResponsiveContainer>
                  </div>
                )}
              </>
            )}
          </div>
        </TabPanel>
      </TabContainer>
    </div>
  );
};

// Role Interaction Matrix sub-component
const RoleInteractionMatrix: React.FC<{ interactions: Array<{ from: string; to: string; count: number }> }> = ({ interactions }) => {
  const { roles, matrix, maxCount } = useMemo(() => {
    const roleSet = new Set<string>();
    interactions.forEach(i => { roleSet.add(i.from); roleSet.add(i.to); });
    const roleList = Array.from(roleSet).sort();
    const m: Record<string, Record<string, number>> = {};
    roleList.forEach(r => { m[r] = {}; roleList.forEach(c => { m[r][c] = 0; }); });
    let max = 0;
    interactions.forEach(i => { m[i.from][i.to] = i.count; if (i.count > max) max = i.count; });
    return { roles: roleList, matrix: m, maxCount: max };
  }, [interactions]);

  if (roles.length === 0) return null;

  return (
    <div className="overflow-x-auto">
      <table className="text-sm">
        <thead>
          <tr>
            <th className="p-2 text-theme-secondary font-medium text-left">From \ To</th>
            {roles.map(r => (
              <th key={r} className="p-2 text-theme-secondary font-medium text-center">{r}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {roles.map(from => (
            <tr key={from}>
              <td className="p-2 text-theme-primary font-medium">{from}</td>
              {roles.map(to => {
                const count = matrix[from][to];
                const opacity = maxCount > 0 ? Math.max(0.1, count / maxCount) : 0;
                return (
                  <td
                    key={to}
                    className="p-2 text-center text-xs"
                    style={count > 0 ? { backgroundColor: `rgba(99, 102, 241, ${opacity})`, color: opacity > 0.5 ? 'white' : undefined } : {}}
                  >
                    {count || '—'}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

export default TeamAnalyticsDashboard;
