import React from 'react';
import { LineChart as LineChartIcon } from 'lucide-react';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import type { AiOpsTrends, CostHourlyTrendPoint } from '@/shared/services/ai/AiOpsApiService';
import { TrendLineChart, CostAreaChart } from '../AiOpsCharts';
import { formatBucketLabel } from '../aiopsHelpers';
import { useAiOpsDashboard, useAiOpsTrends } from '../../api/aiopsApi';
import { SectionShell, AiOpsTimeRange, DEFAULT_TIME_RANGE } from './sectionShared';

interface TrendsBodyProps {
  trends?: AiOpsTrends;
  costHourlyTrend: CostHourlyTrendPoint[];
}

const TrendsBody: React.FC<TrendsBodyProps> = ({ trends, costHourlyTrend }) => {
  if (trends) {
    const latencyData = (trends.latency ?? []).map((p) => ({
      label: formatBucketLabel(p.bucket), avg: p.avg_ms, p95: p.p95_ms, p99: p.p99_ms,
    }));
    const errorData = (trends.error_rate ?? []).map((p) => ({
      label: formatBucketLabel(p.bucket), error_pct: (Number(p.error_rate) || 0) * 100,
    }));
    const throughputData = (trends.throughput ?? []).map((p) => ({
      label: formatBucketLabel(p.bucket), rpm: p.requests_per_minute,
    }));
    const costData = (trends.cost ?? []).map((p) => ({
      label: formatBucketLabel(p.bucket), cost: p.cost_usd,
    }));

    return (
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {latencyData.length > 0 && (
          <TrendLineChart
            title="Latency"
            data={latencyData}
            xKey="label"
            series={[
              { key: 'avg', name: 'Avg (ms)', color: 'var(--color-info, #3B82F6)' },
              { key: 'p95', name: 'p95 (ms)', color: 'var(--color-warning, #F59E0B)' },
              { key: 'p99', name: 'p99 (ms)', color: 'var(--color-danger, #EF4444)' },
            ]}
          />
        )}
        {errorData.length > 0 && (
          <TrendLineChart
            title="Error Rate"
            data={errorData}
            xKey="label"
            series={[{ key: 'error_pct', name: 'Error Rate (%)', color: 'var(--color-danger, #EF4444)' }]}
          />
        )}
        {throughputData.length > 0 && (
          <TrendLineChart
            title="Throughput"
            data={throughputData}
            xKey="label"
            series={[{ key: 'rpm', name: 'Requests / min', color: 'var(--color-success, #10B981)' }]}
          />
        )}
        {costData.length > 0 && (
          <TrendLineChart
            title="Cost"
            data={costData}
            xKey="label"
            series={[{ key: 'cost', name: 'Cost (USD)', color: 'var(--color-interactive-primary, #8B5CF6)' }]}
          />
        )}
      </div>
    );
  }

  // Fallback: derive a single cost trend from the always-present dashboard payload.
  const fallbackData = (costHourlyTrend ?? []).map((p) => ({
    label: formatBucketLabel(p.hour),
    cost: Number(p.cost_usd) || 0,
  }));

  if (fallbackData.length === 0) {
    return (
      <EmptyState
        icon={LineChartIcon}
        title="No trend data"
        description="Hourly trends will appear here once operational metrics accumulate."
      />
    );
  }

  return (
    <div className="space-y-4">
      <p className="text-sm text-theme-tertiary">
        Detailed latency/error/throughput trends are not available yet — showing cost trend from the dashboard payload.
      </p>
      <CostAreaChart title="Cost Trend (hourly)" data={fallbackData} xKey="label" yKey="cost" name="Cost (USD)" />
    </div>
  );
};

/**
 * Standalone, self-fetching trend charts. Uses the optional `trends` endpoint
 * when present, otherwise falls back to the dashboard's hourly cost trend so the
 * section is never empty. Gating is driven by the dashboard query (always
 * available); a failing optional trends query simply triggers the fallback.
 */
export const TrendsSection: React.FC<{ timeRange?: AiOpsTimeRange }> = ({ timeRange = DEFAULT_TIME_RANGE }) => {
  const trendsQuery = useAiOpsTrends(timeRange);
  const { data, isLoading, isError, refetch } = useAiOpsDashboard(timeRange);

  return (
    <SectionShell isLoading={isLoading} isError={isError} onRetry={() => refetch()}>
      {data && (
        <TrendsBody trends={trendsQuery.data} costHourlyTrend={data.cost_analysis?.hourly_trend ?? []} />
      )}
    </SectionShell>
  );
};

export default TrendsSection;
