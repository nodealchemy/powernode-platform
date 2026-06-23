import React, { useState } from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { LayoutDashboard, CreditCard, DollarSign, TrendingUp, Receipt } from 'lucide-react';
import { PageContainer, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { SubNavRail } from '@/shared/components/navigation/SubNavRail';
import { PathTabSpec, firstAccessibleTabPath } from '@/shared/components/navigation/PathTabs';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { aiCrumbs } from '@/shared/utils/breadcrumbs';
import { CreditsContent } from '@/pages/app/ai/CreditsPage';
import { FinOpsContent } from '@/features/ai/finops';
import { RoiDashboardContent } from '@/features/ai/roi/components/RoiDashboard';
import { CostOverviewPanel } from '@/features/ai/finops/components/CostOverviewPanel';
import { CostTrendChart } from '@/features/ai/finops/components/CostTrendChart';
import { featureRegistry } from '@/shared/services/featureRegistry';

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

/**
 * Slot id for the optional success-based-billing leaf. An extension fills this
 * slot (via featureRegistry.registerComponentSlots) to add the leaf to the Cost
 * hub; when no extension provides it, the leaf is omitted. The slotted component
 * accepts an optional `basePath` (the hub-relative URL prefix).
 */
const BILLING_LEAF_SLOT = 'ai.cost.outcome-billing';

/** The success-based-billing rail item, appended only when an extension fills the slot. */
const BILLING_LEAF_NAV: PathTabSpec = {
  key: 'outcome-billing', label: 'Outcome Billing', permission: 'ai.analytics.read', icon: <Receipt size={16} />,
};

/** Cost sub-navigation rail items. Permissions match each leaf's own gating. */
export const COST_NAV: PathTabSpec[] = [
  { key: 'overview', label: 'Overview', permission: 'ai.finops.view', icon: <LayoutDashboard size={16} /> },
  { key: 'credits', label: 'Credits', permission: 'ai.analytics.read', icon: <CreditCard size={16} /> },
  { key: 'finops', label: 'FinOps', permission: 'ai.finops.view', icon: <DollarSign size={16} /> },
  { key: 'roi', label: 'ROI', permission: 'ai.roi.read', icon: <TrendingUp size={16} /> },
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

  // Re-render when the feature registry changes so an extension that fills the
  // success-based-billing slot after mount is picked up.
  const [, setRegistryVersion] = useState(() => featureRegistry.getVersion());
  React.useEffect(
    () => featureRegistry.subscribe(() => setRegistryVersion(featureRegistry.getVersion())),
    [],
  );

  // The success-based-billing leaf is provided by an extension via a registry
  // slot; include its rail item and route only when present. Slot props are
  // host-defined, so we cast to the shape this slot accepts.
  const BillingLeaf = featureRegistry.getComponentSlot(BILLING_LEAF_SLOT) as
    | React.ComponentType<{ basePath?: string }>
    | undefined;
  const navItems = BillingLeaf ? [...COST_NAV, BILLING_LEAF_NAV] : COST_NAV;

  // Derive the active leaf (+ optional sub-tab) from the URL for breadcrumbs,
  // so every rail/tab selection updates the trail as well as the path.
  const segments = location.pathname.slice(COST_BASE.length).split('/').filter(Boolean);
  const leaf = navItems.find((n) => n.key === segments[0]);
  const trail: BreadcrumbItem[] = [{ label: 'Cost', href: COST_BASE }];
  if (leaf) {
    trail.push({ label: leaf.label, href: `${COST_BASE}/${leaf.key}` });
    if (segments[1]) trail.push({ label: humanize(segments[1]) });
  }
  const breadcrumbs = aiCrumbs(...trail);

  const fallback =
    firstAccessibleTabPath(navItems, COST_BASE, hasPermission) ?? `${COST_BASE}/overview`;

  return (
    <PageContainer
      title="Cost"
      description="AI cost management — credits, FinOps, ROI, and outcome billing"
      breadcrumbs={breadcrumbs}
    >
      <SubNavRail
        items={navItems}
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
          {BillingLeaf && (
            <Route
              path="outcome-billing/*"
              element={<BillingLeaf basePath={`${COST_BASE}/outcome-billing`} />}
            />
          )}
          <Route path="*" element={<Navigate to={fallback} replace />} />
        </Routes>
      </SubNavRail>
    </PageContainer>
  );
};

export default CostPage;
