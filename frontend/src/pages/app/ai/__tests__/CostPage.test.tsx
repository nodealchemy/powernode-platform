import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';

// PageContainer → passthrough that surfaces the computed breadcrumb trail as text,
// so we can assert the "tabs update breadcrumbs" behaviour without the breadcrumb
// context/provider.
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({
    breadcrumbs = [],
    children,
  }: {
    breadcrumbs?: Array<{ label: string }>;
    children: React.ReactNode;
  }) => (
    <div>
      <div data-testid="breadcrumbs">{breadcrumbs.map((b) => b.label).join(' / ')}</div>
      {children}
    </div>
  ),
}));

// Allow every leaf so the rail renders all items.
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: () => true }),
}));

// Stub the data-fetching leaves so the hub test stays deterministic.
jest.mock('@/pages/app/ai/CreditsPage', () => ({
  CreditsContent: () => <div data-testid="credits-leaf" />,
}));
jest.mock('@/pages/app/ai/OutcomeBillingPage', () => ({
  OutcomeBillingContent: () => <div data-testid="outcome-leaf" />,
}));
jest.mock('@/features/ai/finops', () => ({
  FinOpsContent: () => <div data-testid="finops-leaf" />,
}));
jest.mock('@/features/ai/roi/components/RoiDashboard', () => ({
  RoiDashboardContent: () => <div data-testid="roi-leaf" />,
}));
jest.mock('@/features/ai/finops/components/CostOverviewPanel', () => ({
  CostOverviewPanel: () => <div data-testid="overview-panel" />,
}));
jest.mock('@/features/ai/finops/components/CostTrendChart', () => ({
  CostTrendChart: () => <div data-testid="overview-trend" />,
}));

import { CostPage } from '../CostPage';

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/app/ai/cost/*" element={<CostPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('CostPage hub', () => {
  it('renders the sub-rail with every cost leaf', () => {
    renderAt('/app/ai/cost/credits');
    ['overview', 'credits', 'finops', 'roi', 'outcome-billing'].forEach((key) => {
      expect(screen.getByTestId(`sub-nav-${key}`)).toBeInTheDocument();
    });
  });

  it('routes to the active leaf and marks its rail item current', () => {
    renderAt('/app/ai/cost/credits');
    expect(screen.getByTestId('credits-leaf')).toBeInTheDocument();
    expect(screen.getByTestId('sub-nav-credits')).toHaveAttribute('aria-current', 'page');
  });

  it('reflects the active leaf in the breadcrumb trail', () => {
    renderAt('/app/ai/cost/roi');
    expect(screen.getByTestId('roi-leaf')).toBeInTheDocument();
    const trail = screen.getByTestId('breadcrumbs').textContent ?? '';
    expect(trail).toContain('Cost');
    expect(trail).toContain('ROI');
  });

  it('extends the breadcrumb with the leaf sub-tab (URL + breadcrumb stay in sync)', () => {
    renderAt('/app/ai/cost/credits/transactions');
    const trail = screen.getByTestId('breadcrumbs').textContent ?? '';
    expect(trail).toContain('Cost');
    expect(trail).toContain('Credits');
    expect(trail).toContain('Transactions');
  });

  it('redirects the hub index to the first accessible leaf (overview)', () => {
    renderAt('/app/ai/cost');
    expect(screen.getByTestId('overview-panel')).toBeInTheDocument();
  });
});
