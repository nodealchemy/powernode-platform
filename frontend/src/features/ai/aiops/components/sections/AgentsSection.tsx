import React from 'react';
import { Bot } from 'lucide-react';
import { DataTable, DataTableColumn } from '@/shared/components/ui/DataTable';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { EntityLink } from '@/shared/components/entity';
import type { AiOpsDashboard, AgentMetricRow } from '@/shared/services/ai/AiOpsApiService';
import {
  formatNumber, formatCurrency, formatDuration, formatPercent, formatTimestamp,
} from '../aiopsHelpers';
import { DashboardSection, AiOpsTimeRange } from './sectionShared';

const AgentsTable: React.FC<{ agents: AgentMetricRow[] }> = ({ agents }) => {
  if (agents.length === 0) {
    return (
      <EmptyState
        icon={Bot}
        title="No agent activity"
        description="No agent executions were recorded in the selected time range."
      />
    );
  }

  const columns: DataTableColumn<AgentMetricRow>[] = [
    {
      key: 'agent',
      header: 'Agent',
      render: (a) => (
        <div>
          <EntityLink type="ai_agent" id={a.agent_id} label={a.agent_name} className="font-medium" />
          <p className="text-xs text-theme-tertiary capitalize">{a.agent_type}</p>
        </div>
      ),
    },
    { key: 'status', header: 'Status', render: (a) => <span className="capitalize text-theme-secondary">{a.status || '—'}</span> },
    { key: 'provider', header: 'Provider', render: (a) => a.provider_name || '—' },
    { key: 'executions', header: 'Executions', render: (a) => formatNumber(a.metrics?.total_executions ?? 0) },
    { key: 'success_rate', header: 'Success', render: (a) => formatPercent(a.metrics?.success_rate) },
    { key: 'avg_duration', header: 'Avg Duration', render: (a) => formatDuration(a.metrics?.avg_duration_ms) },
    { key: 'tokens', header: 'Tokens', render: (a) => formatNumber(a.metrics?.total_tokens ?? 0) },
    { key: 'cost', header: 'Cost', render: (a) => formatCurrency(a.metrics?.total_cost ?? 0) },
    { key: 'last_execution', header: 'Last Run', render: (a) => formatTimestamp(a.last_execution_at) },
  ];

  return <DataTable<AgentMetricRow> columns={columns} data={agents} />;
};

/** Standalone, self-fetching per-agent execution/latency/cost table (metrics.total_cost). */
export const AgentsSection: React.FC<{ timeRange?: AiOpsTimeRange }> = ({ timeRange }) => (
  <DashboardSection timeRange={timeRange}>
    {(dashboard: AiOpsDashboard) => <AgentsTable agents={dashboard.agents ?? []} />}
  </DashboardSection>
);

export default AgentsSection;
