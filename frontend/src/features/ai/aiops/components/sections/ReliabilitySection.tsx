import React from 'react';
import { CheckCircle2, ShieldAlert, XCircle } from 'lucide-react';
import { DataTable, DataTableColumn } from '@/shared/components/ui/DataTable';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { EntityLink } from '@/shared/components/entity';
import type { CircuitBreaker, RecentError } from '@/shared/services/ai/AiOpsApiService';
import { getCircuitBadge, formatTimestamp } from '../aiopsHelpers';
import { useAiOpsDashboard, useAiOpsRecentErrors } from '../../api/aiopsApi';
import { SectionShell, AiOpsTimeRange, DEFAULT_TIME_RANGE } from './sectionShared';

interface ReliabilityBodyProps {
  circuitBreakers: CircuitBreaker[];
  recentErrors?: RecentError[];
}

const ReliabilityBody: React.FC<ReliabilityBodyProps> = ({ circuitBreakers, recentErrors }) => {
  const breakerRows = circuitBreakers ?? [];
  const errorRows = recentErrors ?? [];

  const breakerColumns: DataTableColumn<CircuitBreaker>[] = [
    {
      key: 'provider',
      header: 'Provider',
      render: (cb) => <EntityLink type="ai_provider" id={cb.provider_id} label={cb.provider_name} className="font-medium" />,
    },
    { key: 'state', header: 'State', render: (cb) => getCircuitBadge(cb.state) },
    { key: 'failures', header: 'Consecutive Failures', render: (cb) => cb.consecutive_failures ?? 0 },
    { key: 'last_failure', header: 'Last Failure', render: (cb) => formatTimestamp(cb.last_failure_at) },
    { key: 'last_success', header: 'Last Success', render: (cb) => formatTimestamp(cb.last_success_at) },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-theme-primary mb-3 flex items-center gap-2">
          <ShieldAlert className="h-5 w-5" />
          Circuit Breakers
        </h3>
        {breakerRows.length === 0 ? (
          <EmptyState
            icon={CheckCircle2}
            title="No circuit breakers tripped"
            description="All provider circuits are closed and operating normally."
          />
        ) : (
          <DataTable<CircuitBreaker> columns={breakerColumns} data={breakerRows} />
        )}
      </div>

      {errorRows.length > 0 && (
        <div>
          <h3 className="text-lg font-semibold text-theme-primary mb-3 flex items-center gap-2">
            <XCircle className="h-5 w-5 text-theme-error-fg" />
            Recent Errors
          </h3>
          <div className="space-y-2">
            {errorRows.map((err, idx) => (
              <div key={`${err.execution_id}-${idx}`} className="bg-theme-error-bg border border-theme-error-border rounded-lg p-3">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="text-sm font-medium text-theme-error-fg">{err.agent_name || 'Unknown agent'}</p>
                    <p className="text-sm text-theme-secondary mt-1">{err.error}</p>
                  </div>
                  <span className="text-xs text-theme-tertiary whitespace-nowrap">{formatTimestamp(err.failed_at)}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

/**
 * Standalone, self-fetching reliability surface: circuit-breaker table + the
 * optional recent-errors feed. Deliberately renders NO generic alerts list — the
 * Observability Alerts tab already owns alerting via AlertManagementCenter, and
 * provider-health alerts live in OverviewSection's compact callout.
 */
export const ReliabilitySection: React.FC<{ timeRange?: AiOpsTimeRange }> = ({ timeRange = DEFAULT_TIME_RANGE }) => {
  const { data, isLoading, isError, refetch } = useAiOpsDashboard(timeRange);
  const recentErrorsQuery = useAiOpsRecentErrors();

  return (
    <SectionShell isLoading={isLoading} isError={isError} onRetry={() => refetch()}>
      {data && (
        <ReliabilityBody circuitBreakers={data.circuit_breakers ?? []} recentErrors={recentErrorsQuery.data} />
      )}
    </SectionShell>
  );
};

export default ReliabilitySection;
