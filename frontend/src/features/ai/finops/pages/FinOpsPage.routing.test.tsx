import React from 'react';
import { cleanup, render, screen } from '@testing-library/react';
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';

// FinOps has one view (the cost explorer), so it renders at its base path,
// /app/ai/cost/finops, with no sub-route. Its old sub-paths — including the
// deleted /finops/budget — are unknown paths like any other: they get the Cost
// hub's generic unknown-path handling, never a FinOps redirect that quietly
// turns a dead budget link into the cost explorer.

jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: () => true }),
}));
jest.mock('@/pages/app/ai/CreditsPage', () => ({ CreditsContent: () => <div data-testid="credits-leaf" /> }));
jest.mock('@/features/ai/roi/components/RoiDashboard', () => ({
  RoiDashboardContent: () => <div data-testid="roi-leaf" />,
}));
jest.mock('@/features/ai/finops/components/CostOverviewPanel', () => ({
  CostOverviewPanel: () => <div data-testid="overview-panel" />,
}));
jest.mock('@/features/ai/finops/components/CostTrendChart', () => ({
  CostTrendChart: () => <div data-testid="cost-trend" />,
}));
jest.mock('@/features/ai/finops/components/OptimizationRecommendations', () => ({
  OptimizationRecommendations: () => <div data-testid="finops-recommendations" />,
}));

import { CostPage } from '@/pages/app/ai/CostPage';

let currentPath = '';
const LocationProbe = () => {
  currentPath = useLocation().pathname;
  return null;
};

function renderAt(path: string) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/app/ai/cost/*" element={<><CostPage /><LocationProbe /></>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('FinOps routing', () => {
  it('renders the cost explorer at the FinOps base path, without redirecting', () => {
    renderAt('/app/ai/cost/finops');

    expect(screen.getByTestId('finops-recommendations')).toBeInTheDocument();
    expect(currentPath).toBe('/app/ai/cost/finops');
  });

  it.each(['/app/ai/cost/finops/budget', '/app/ai/cost/finops/cost-explorer'])(
    'treats %s as an unknown Cost path, not as FinOps',
    (path) => {
      renderAt(path);
      const unknownHandling = currentPath;

      expect(screen.queryByTestId('finops-recommendations')).not.toBeInTheDocument();
      expect(unknownHandling).not.toMatch(/\/finops/);

      // The same handling any unknown Cost path gets.
      cleanup();
      renderAt('/app/ai/cost/no-such-leaf');
      expect(currentPath).toBe(unknownHandling);
    },
  );
});
