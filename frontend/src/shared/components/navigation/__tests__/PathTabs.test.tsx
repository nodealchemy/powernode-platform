import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { KeyRound, ShieldCheck } from 'lucide-react';
import { PathTabs, firstAccessibleTabPath, type PathTabSpec } from '../PathTabs';

const TABS: PathTabSpec[] = [
  { key: 'alpha', label: 'Alpha', permission: 'feature.alpha', icon: <KeyRound /> },
  { key: 'beta', label: 'Beta', permission: 'feature.beta', icon: <ShieldCheck /> },
];

const BASE = '/app/demo';

function renderTabs(
  hasPermission: (p: string) => boolean,
  initialPath: string,
  emptyState?: React.ReactNode,
) {
  return render(
    <MemoryRouter initialEntries={[initialPath]}>
      <PathTabs tabs={TABS} basePath={BASE} hasPermission={hasPermission} emptyState={emptyState}>
        <div data-testid="tab-content">content</div>
      </PathTabs>
    </MemoryRouter>,
  );
}

describe('PathTabs', () => {
  it('renders only permission-accessible tabs', () => {
    renderTabs((p) => p === 'feature.alpha', `${BASE}/alpha`);

    expect(screen.getByRole('link', { name: 'Alpha' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Beta' })).not.toBeInTheDocument();
    expect(screen.getByTestId('tab-content')).toBeInTheDocument();
  });

  it('links each tab to basePath/key', () => {
    renderTabs(() => true, `${BASE}/alpha`);

    expect(screen.getByRole('link', { name: 'Alpha' })).toHaveAttribute('href', `${BASE}/alpha`);
    expect(screen.getByRole('link', { name: 'Beta' })).toHaveAttribute('href', `${BASE}/beta`);
  });

  it('marks the active tab (derived from the trailing path segment) as current', () => {
    renderTabs(() => true, `${BASE}/beta`);

    const active = screen.getByRole('link', { name: 'Beta' });
    const inactive = screen.getByRole('link', { name: 'Alpha' });
    expect(active.className).toContain('text-theme-primary');
    expect(active.className).toContain('font-medium');
    expect(inactive.className).toContain('text-theme-secondary');
  });

  it('renders the empty state when no tab is accessible', () => {
    renderTabs(
      () => false,
      `${BASE}/alpha`,
      <div data-testid="empty">no access</div>,
    );

    expect(screen.getByTestId('empty')).toBeInTheDocument();
    expect(screen.queryByTestId('tab-content')).not.toBeInTheDocument();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });

  it('renders nothing (no children) when no tab is accessible and no empty state is supplied', () => {
    renderTabs(() => false, `${BASE}/alpha`);

    expect(screen.queryByTestId('tab-content')).not.toBeInTheDocument();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });
});

describe('firstAccessibleTabPath', () => {
  it('returns the path of the first accessible tab in declaration order', () => {
    expect(firstAccessibleTabPath(TABS, BASE, () => true)).toBe(`${BASE}/alpha`);
    expect(firstAccessibleTabPath(TABS, BASE, (p) => p === 'feature.beta')).toBe(`${BASE}/beta`);
  });

  it('returns null when no tab is accessible', () => {
    expect(firstAccessibleTabPath(TABS, BASE, () => false)).toBeNull();
  });
});
