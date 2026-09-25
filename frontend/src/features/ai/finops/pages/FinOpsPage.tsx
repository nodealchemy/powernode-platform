import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { DollarSign } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { CostTrendChart } from '../components/CostTrendChart';
import { OptimizationRecommendations } from '../components/OptimizationRecommendations';

/**
 * FinOpsContent — spend analytics (the cost explorer). Reached via the
 * `/ai/cost/finops/*` wildcard route. No "Overview" here — it duplicated
 * CostPage's own `/app/ai/cost/overview`, which is canonical — and no budget
 * view: agent budgets live on the one Budgets page (/app/ai/control/budgets).
 * With a single view left there is no tab strip.
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
    <Routes>
      <Route index element={<Navigate to="cost-explorer" replace />} />
      <Route
        path="cost-explorer"
        element={
          <div className="space-y-6">
            <CostTrendChart />
            <OptimizationRecommendations />
          </div>
        }
      />
      <Route path="*" element={<Navigate to="cost-explorer" replace />} />
    </Routes>
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
