import React from 'react';
import { DollarSign, Layers, Server } from 'lucide-react';
import { MetricCard } from '@/shared/components/ui/Card';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import type { AiOpsDashboard, CostAnalysis } from '@/shared/services/ai/AiOpsApiService';
import { CostAreaChart, CategoryBarChart } from '../AiOpsCharts';
import { formatCurrency, formatNumber, formatBucketLabel } from '../aiopsHelpers';
import { DashboardSection, AiOpsTimeRange } from './sectionShared';

const CostBody: React.FC<{ cost: CostAnalysis }> = ({ cost }) => {
  const totals = cost?.totals;
  const hourlyTrend = cost?.hourly_trend ?? [];
  const byProvider = cost?.by_provider ?? [];

  const trendData = hourlyTrend.map((point) => ({
    label: formatBucketLabel(point.hour),
    cost: Number(point.cost_usd) || 0,
  }));

  const providerData = byProvider.map((point) => ({
    name: point.provider_name || point.provider_id,
    cost: Number(point.cost_usd) || 0,
  }));

  const hasData = (totals?.total_cost ?? 0) > 0 || trendData.length > 0 || providerData.length > 0;

  if (!hasData) {
    return (
      <EmptyState
        icon={DollarSign}
        title="No cost data"
        description="No spend was attributed to AI operations in the selected time range."
      />
    );
  }

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <MetricCard
          title="Total Cost"
          value={formatCurrency(totals?.total_cost ?? 0)}
          icon={<DollarSign className="h-5 w-5 text-theme-success-fg" />}
        />
        <MetricCard
          title="Agent Cost"
          value={formatCurrency(totals?.agent_cost ?? 0)}
          icon={<Layers className="h-5 w-5 text-theme-info-fg" />}
        />
        <MetricCard
          title="Providers Billed"
          value={formatNumber(providerData.length)}
          icon={<Server className="h-5 w-5 text-theme-interactive-primary" />}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {trendData.length > 0 && (
          <CostAreaChart title="Spend Over Time" data={trendData} xKey="label" yKey="cost" name="Cost (USD)" />
        )}
        {providerData.length > 0 && (
          <CategoryBarChart title="Spend by Provider" data={providerData} xKey="name" yKey="cost" name="Cost (USD)" />
        )}
      </div>
    </div>
  );
};

/** Standalone, self-fetching cost KPIs + spend-over-time + spend-by-provider. */
export const CostSection: React.FC<{ timeRange?: AiOpsTimeRange }> = ({ timeRange }) => (
  <DashboardSection timeRange={timeRange}>
    {(dashboard: AiOpsDashboard) => <CostBody cost={dashboard.cost_analysis} />}
  </DashboardSection>
);

export default CostSection;
