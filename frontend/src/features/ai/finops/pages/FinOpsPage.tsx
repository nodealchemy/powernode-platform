import React from 'react';
import { DollarSign } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { CostTrendChart } from '../components/CostTrendChart';
import { OptimizationRecommendations } from '../components/OptimizationRecommendations';

/**
 * FinOpsContent — spend analytics (the cost explorer), rendered at the Cost
 * hub's `/app/ai/cost/finops`. No "Overview" here — it duplicated CostPage's
 * own `/app/ai/cost/overview`, which is canonical — and no budget view: agent
 * budgets live on AI → Control → Budgets (/app/ai/control/budgets). With a single
 * view left there are no sub-routes, so an old FinOps sub-path is an unknown
 * Cost path, handled like any other.
 */
export const FinOpsContent: React.FC = () => {
  const { hasPermission } = usePermissions();

  if (!hasPermission('ai.finops.view')) {
    return (
      <div className="text-center py-12">
        <DollarSign className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">You do not have permission to view FinOps data.</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <CostTrendChart />
      <OptimizationRecommendations />
    </div>
  );
};

export const FinOpsPage: React.FC = () => (
  <PageContainer
    title="AI FinOps"
    description="Monitor AI costs, token usage, and optimization opportunities"
    breadcrumbs={[
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'FinOps' },
    ]}
  >
    <FinOpsContent />
  </PageContainer>
);
