import React, { useState } from 'react';
import { DollarSign, TrendingUp, Wallet } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { CostOverviewPanel } from '../components/CostOverviewPanel';
import { CostTrendChart } from '../components/CostTrendChart';
import { BudgetUtilizationPanel } from '../components/BudgetUtilizationPanel';
import { OptimizationRecommendations } from '../components/OptimizationRecommendations';

export const FinOpsContent: React.FC = () => {
  const { hasPermission } = usePermissions();
  const [activeTab, setActiveTab] = useState('overview');

  const canView = hasPermission('ai.finops.view');

  if (!canView) {
    return (
      <div className="text-center py-12">
        <DollarSign className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">You do not have permission to view FinOps data.</p>
      </div>
    );
  }

  const tabs = [
    {
      id: 'overview',
      label: 'Overview',
      icon: <TrendingUp className="h-4 w-4" />,
      content: (
        <div className="space-y-6">
          <CostOverviewPanel />
          <CostTrendChart />
        </div>
      ),
    },
    {
      id: 'cost-explorer',
      label: 'Cost Explorer',
      icon: <DollarSign className="h-4 w-4" />,
      content: (
        <div className="space-y-6">
          <CostTrendChart />
          <OptimizationRecommendations />
        </div>
      ),
    },
    {
      id: 'budget',
      label: 'Budget',
      icon: <Wallet className="h-4 w-4" />,
      content: <BudgetUtilizationPanel />,
    },
  ];

  return (
    <TabContainer
      tabs={tabs}
      activeTab={activeTab}
      onTabChange={setActiveTab}
      variant="underline"
    />
  );
};

export const FinOpsPage: React.FC = () => (
  <PageContainer
    title="AI FinOps"
    description="Monitor AI costs, token usage, budgets, and optimization opportunities"
    breadcrumbs={[
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'FinOps' },
    ]}
  >
    <FinOpsContent />
  </PageContainer>
);
