import React from 'react';
import { Server } from 'lucide-react';
import { DataTable, DataTableColumn } from '@/shared/components/ui/DataTable';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { EntityLink } from '@/shared/components/entity';
import type { AiOpsDashboard, ProviderMetricRow } from '@/shared/services/ai/AiOpsApiService';
import {
  formatNumber, formatCurrency, formatDuration, formatPercent,
  getHealthBadge, getCircuitBadge,
} from '../aiopsHelpers';
import { DashboardSection, AiOpsTimeRange } from './sectionShared';

const ProvidersTable: React.FC<{ providers: ProviderMetricRow[] }> = ({ providers }) => {
  if (providers.length === 0) {
    return (
      <EmptyState
        icon={Server}
        title="No provider activity"
        description="No AI provider metrics were recorded in the selected time range."
      />
    );
  }

  const columns: DataTableColumn<ProviderMetricRow>[] = [
    {
      key: 'provider',
      header: 'Provider',
      render: (p) => (
        <div>
          <EntityLink type="ai_provider" id={p.provider_id} label={p.provider_name} className="font-medium" />
          <p className="text-xs text-theme-tertiary capitalize">{p.provider_type}</p>
        </div>
      ),
    },
    { key: 'health', header: 'Health', render: (p) => getHealthBadge(p.health_status) },
    { key: 'requests', header: 'Requests', render: (p) => formatNumber(p.metrics?.request_count ?? 0) },
    { key: 'success_rate', header: 'Success', render: (p) => formatPercent(p.metrics?.success_rate) },
    { key: 'avg_latency', header: 'Avg Latency', render: (p) => formatDuration(p.metrics?.avg_latency_ms) },
    { key: 'p95_latency', header: 'p95', render: (p) => formatDuration(p.metrics?.p95_latency_ms) },
    { key: 'tokens', header: 'Tokens', render: (p) => formatNumber(p.metrics?.total_tokens ?? 0) },
    { key: 'cost', header: 'Cost', render: (p) => formatCurrency(p.metrics?.total_cost_usd ?? 0) },
    {
      key: 'circuit',
      header: 'Circuit',
      render: (p) => (
        <div className="flex items-center gap-2">
          {getCircuitBadge(p.circuit_breaker?.state)}
          {(p.circuit_breaker?.consecutive_failures ?? 0) > 0 && (
            <span className="text-xs text-theme-error-fg">{p.circuit_breaker.consecutive_failures} fails</span>
          )}
        </div>
      ),
    },
  ];

  return <DataTable<ProviderMetricRow> columns={columns} data={providers} />;
};

/** Standalone, self-fetching per-provider request/latency/cost/circuit table. */
export const ProvidersSection: React.FC<{ timeRange?: AiOpsTimeRange }> = ({ timeRange }) => (
  <DashboardSection timeRange={timeRange}>
    {(dashboard: AiOpsDashboard) => <ProvidersTable providers={dashboard.providers ?? []} />}
  </DashboardSection>
);

export default ProvidersSection;
