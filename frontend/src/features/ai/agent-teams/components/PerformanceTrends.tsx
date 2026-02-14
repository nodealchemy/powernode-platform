import React, { useMemo } from 'react';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, BarChart, Bar,
} from 'recharts';
import type { TeamAnalytics } from '@/shared/services/ai/TeamsApiService';
import {
  KpiCard, CHART_COLORS, tooltipStyle,
  formatDuration, formatNumber, mapToChartData, mapTimeSeriesData, renderPieLabel,
} from './teamAnalyticsHelpers';

interface PerformanceTrendsProps {
  communication?: TeamAnalytics['communication'];
  quality?: TeamAnalytics['quality'];
  section: 'communication' | 'quality';
}

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

export const PerformanceTrends: React.FC<PerformanceTrendsProps> = ({ communication, quality, section }) => {
  if (section === 'communication' && communication) {
    return (
      <div className="space-y-6">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <KpiCard label="Total Messages" value={formatNumber(communication.total_messages)} />
          <KpiCard label="Response Rate" value={`${communication.response_rate}%`} />
          <KpiCard label="Avg Response Time" value={communication.avg_response_time_seconds > 0 ? `${communication.avg_response_time_seconds.toFixed(1)}s` : '—'} />
          <KpiCard label="Escalations" value={formatNumber(communication.escalation_count)} subtext={`${communication.escalation_rate}% escalation rate`} />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
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

        {communication.role_interactions.length > 0 && (
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <h4 className="text-sm font-medium text-theme-primary mb-3">Role Interactions</h4>
            <RoleInteractionMatrix interactions={communication.role_interactions} />
          </div>
        )}
      </div>
    );
  }

  // Quality section
  if (!quality) return null;

  return (
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
  );
};
