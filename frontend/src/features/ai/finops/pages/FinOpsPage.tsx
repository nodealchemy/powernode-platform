import React from 'react';
import { Routes, Route, Navigate, Link, useLocation } from 'react-router-dom';
import { DollarSign, TrendingUp, Wallet } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { CostOverviewPanel } from '../components/CostOverviewPanel';
import { CostTrendChart } from '../components/CostTrendChart';
import { BudgetUtilizationPanel } from '../components/BudgetUtilizationPanel';
import { OptimizationRecommendations } from '../components/OptimizationRecommendations';

const FINOPS_BASE = '/app/ai/cost/finops';

const TABS = [
  { key: 'overview', label: 'Overview', icon: TrendingUp },
  { key: 'cost-explorer', label: 'Cost Explorer', icon: DollarSign },
  { key: 'budget', label: 'Budget', icon: Wallet },
] as const;

/**
 * FinOpsContent — path-based tabs (per-tab URL segment), the canonical platform
 * tab pattern (see pages/app/admin/AdminSettingsPage.tsx). Reached via the
 * `/ai/cost/finops/*` wildcard route so the nested <Routes> handles tab matching.
 */
export const FinOpsContent: React.FC = () => {
  const { hasPermission } = usePermissions();
  const location = useLocation();

  if (!hasPermission('ai.finops.view')) {
    return (
      <div className="text-center py-12">
        <DollarSign className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">You do not have permission to view FinOps data.</p>
      </div>
    );
  }

  const activeTab = TABS.find((t) => location.pathname.endsWith(`/${t.key}`))?.key ?? 'overview';

  return (
    <div className="space-y-6">
      <nav className="flex gap-1 border-b border-theme">
        {TABS.map((t) => {
          const Icon = t.icon;
          const isActive = t.key === activeTab;
          return (
            <Link
              key={t.key}
              to={`${FINOPS_BASE}/${t.key}`}
              className={`flex items-center gap-2 px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
                isActive
                  ? 'border-theme-focus text-theme-primary'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <Icon className="h-4 w-4" />
              {t.label}
            </Link>
          );
        })}
      </nav>

      <Routes>
        <Route index element={<Navigate to="overview" replace />} />
        <Route
          path="overview"
          element={
            <div className="space-y-6">
              <CostOverviewPanel />
              <CostTrendChart />
            </div>
          }
        />
        <Route
          path="cost-explorer"
          element={
            <div className="space-y-6">
              <CostTrendChart />
              <OptimizationRecommendations />
            </div>
          }
        />
        <Route path="budget" element={<BudgetUtilizationPanel />} />
        <Route path="*" element={<Navigate to="overview" replace />} />
      </Routes>
    </div>
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
