import { render, screen } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import { KeyRound, ShieldCheck } from 'lucide-react';
import { SubNavRail } from '../SubNavRail';
import type { PathTabSpec } from '../PathTabs';

const ITEMS: PathTabSpec[] = [
  { key: 'alpha', label: 'Alpha', permission: 'feature.alpha', icon: <KeyRound /> },
  { key: 'beta', label: 'Beta', permission: 'feature.beta', icon: <ShieldCheck /> },
];

const BASE = '/app/demo';

function renderRail(
  hasPermission: (p: string) => boolean,
  initialPath: string,
  emptyState?: React.ReactNode,
) {
  return render(
    <MemoryRouter initialEntries={[initialPath]}>
      <SubNavRail items={ITEMS} basePath={BASE} hasPermission={hasPermission} emptyState={emptyState}>
        <div data-testid="leaf-content">content</div>
      </SubNavRail>
    </MemoryRouter>,
  );
}

describe('SubNavRail', () => {
  it('renders only permission-accessible items and the leaf content', () => {
    renderRail((p) => p === 'feature.alpha', `${BASE}/alpha`);

    expect(screen.getByRole('link', { name: 'Alpha' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Beta' })).not.toBeInTheDocument();
    expect(screen.getByTestId('leaf-content')).toBeInTheDocument();
    expect(screen.getByTestId('sub-nav-rail')).toBeInTheDocument();
  });

  it('links each item to basePath/key with a stable test id', () => {
    renderRail(() => true, `${BASE}/alpha`);

    expect(screen.getByTestId('sub-nav-alpha')).toHaveAttribute('href', `${BASE}/alpha`);
    expect(screen.getByTestId('sub-nav-beta')).toHaveAttribute('href', `${BASE}/beta`);
  });

  it('marks the active item via the segment after basePath, even on a deep leaf sub-path', () => {
    // A deep URL like /app/demo/beta/details must still highlight the "beta" rail item.
    renderRail(() => true, `${BASE}/beta/details`);

    expect(screen.getByTestId('sub-nav-beta')).toHaveAttribute('aria-current', 'page');
    expect(screen.getByTestId('sub-nav-alpha')).not.toHaveAttribute('aria-current');
    expect(screen.getByTestId('sub-nav-beta').className).toContain('bg-theme-surface-selected');
  });

  it('renders the empty state when no item is accessible', () => {
    renderRail(() => false, `${BASE}/alpha`, <div data-testid="empty">no access</div>);

    expect(screen.getByTestId('empty')).toBeInTheDocument();
    expect(screen.queryByTestId('leaf-content')).not.toBeInTheDocument();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });

  it('renders nothing when no item is accessible and no empty state is supplied', () => {
    renderRail(() => false, `${BASE}/alpha`);

    expect(screen.queryByTestId('leaf-content')).not.toBeInTheDocument();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });

  it('renders the active leaf content when mounted under a parent splat route', () => {
    // Mirrors how CostPage is mounted: DashboardPage routes `/ai/cost/*` → hub →
    // SubNavRail → the hub's own nested <Routes>. The parent splat establishes
    // the base so the inner relative routes resolve.
    render(
      <MemoryRouter initialEntries={[`${BASE}/beta`]}>
        <Routes>
          <Route
            path="/app/demo/*"
            element={
              <SubNavRail items={ITEMS} basePath={BASE} hasPermission={() => true}>
                <Routes>
                  <Route path="alpha" element={<div data-testid="alpha-leaf" />} />
                  <Route path="beta" element={<div data-testid="beta-leaf" />} />
                </Routes>
              </SubNavRail>
            }
          />
        </Routes>
      </MemoryRouter>,
    );

    expect(screen.getByTestId('beta-leaf')).toBeInTheDocument();
    expect(screen.queryByTestId('alpha-leaf')).not.toBeInTheDocument();
  });
});
