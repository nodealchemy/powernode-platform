import React from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { LayoutDashboard, CreditCard, DollarSign, TrendingUp, Receipt } from 'lucide-react';
import { PageContainer, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { SubNavRail } from '@/shared/components/navigation/SubNavRail';
import { PathTabSpec, firstAccessibleTabPath } from '@/shared/components/navigation/PathTabs';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { aiCrumbs } from '@/shared/utils/breadcrumbs';
import { CreditsContent } from '@/pages/app/ai/CreditsPage';
import { OutcomeBillingContent } from '@/pages/app/ai/OutcomeBillingPage';
import { FinOpsContent } from '@/features/ai/finops';
import { RoiDashboardContent } from '@/features/ai/roi/components/RoiDashboard';
import { CostOverviewPanel } from '@/features/ai/finops/components/CostOverviewPanel';
import { CostTrendChart } from '@/features/ai/finops/components/CostTrendChart';

/**
 * CostPage — the single, domain-aligned home for everything financial in the AI
 * category: Credits, FinOps, ROI, and Outcome Billing. It replaces the orphan
 * "Cost" sidebar section and the deep `Observability ▸ Credits & FinOps ▸ …`
 * nesting.
 *
 * Per the IA rule "avoid nested horizontal tabs; use a sidebar where nesting is
 * needed", the hub uses ONE vertical `SubNavRail` for its leaves; the only
 * leaves that carry further sub-views (Credits, FinOps, Outcome Billing) render
 * a single `PathTabs` row, so total depth never exceeds rail → one tab row.
 *
 * Every leaf/sub-tab is path-based, so navigation updates the URL and the
 * breadcrumb trail (computed below from the active path segments).
 */

const COST_BASE = '/app/ai/cost';

/** Cost sub-navigation rail items. Permissions match each leaf's own gating. */
export const COST_NAV: PathTabSpec[] = [
  { key: 'overview', label: 'Overview', permission: 'ai.finops.view', icon: <LayoutDashboard size={16} /> },
  { key: 'credits', label: 'Credits', permission: 'ai.analytics.read', icon: <CreditCard size={16} /> },
  { key: 'finops', label: 'FinOps', permission: 'ai.finops.view', icon: <DollarSign size={16} /> },
  { key: 'roi', label: 'ROI', permission: 'ai.roi.read', icon: <TrendingUp size={16} /> },
  { key: 'outcome-billing', label: 'Outcome Billing', permission: 'ai.analytics.read', icon: <Receipt size={16} /> },
];

/** Title-case a URL segment for breadcrumb display (e.g. `cost-explorer` → `Cost Explorer`). */
const humanize = (seg: string): string =>
  seg
    .split('-')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');

/** Cost overview — a lightweight cross-cutting snapshot reusing FinOps panels. */
const CostOverview: React.FC = () => (
  <div className="space-y-6">
    <CostOverviewPanel />
    <CostTrendChart />
  </div>
);

export const CostPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const location = useLocation();

  // Derive the active leaf (+ optional sub-tab) from the URL for breadcrumbs,
  // so every rail/tab selection updates the trail as well as the path.
  const segments = location.pathname.slice(COST_BASE.length).split('/').filter(Boolean);
  const leaf = COST_NAV.find((n) => n.key === segments[0]);
  const trail: BreadcrumbItem[] = [{ label: 'Cost', href: COST_BASE }];
  if (leaf) {
    trail.push({ label: leaf.label, href: `${COST_BASE}/${leaf.key}` });
    if (segments[1]) trail.push({ label: humanize(segments[1]) });
  }
  const breadcrumbs = aiCrumbs(...trail);

  const fallback =
    firstAccessibleTabPath(COST_NAV, COST_BASE, hasPermission) ?? `${COST_BASE}/overview`;

  return (
    <PageContainer
      title="Cost"
      description="AI cost management — credits, FinOps, ROI, and outcome billing"
      breadcrumbs={breadcrumbs}
    >
      <SubNavRail
        items={COST_NAV}
        basePath={COST_BASE}
        hasPermission={hasPermission}
        ariaLabel="Cost navigation"
        emptyState={
          <p className="text-theme-secondary">You do not have permission to view cost data.</p>
        }
      >
        <Routes>
          <Route index element={<Navigate to={fallback} replace />} />
          <Route path="overview" element={<CostOverview />} />
          <Route path="credits/*" element={<CreditsContent basePath={`${COST_BASE}/credits`} />} />
          <Route path="finops/*" element={<FinOpsContent />} />
          <Route path="roi" element={<RoiDashboardContent />} />
          <Route
            path="outcome-billing/*"
            element={<OutcomeBillingContent basePath={`${COST_BASE}/outcome-billing`} />}
          />
          <Route path="*" element={<Navigate to={fallback} replace />} />
        </Routes>
      </SubNavRail>
    </PageContainer>
  );
};

export default CostPage;
