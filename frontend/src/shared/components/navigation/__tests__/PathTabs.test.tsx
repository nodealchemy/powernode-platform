import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { KeyRound, ShieldCheck } from 'lucide-react';
import {
  PathTabs,
  firstAccessibleTabPath,
  activeTabKeyFromPath,
  type PathTabSpec,
} from '../PathTabs';

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

  // ---------------------------------------------------------------------------
  // Active-key derivation (IMP-d725a6bad253)
  // ---------------------------------------------------------------------------

  it('keeps a tab active on a path nested under it', () => {
    // Hubs whose tabs own sub-routes ("/app/demo/beta/detail/7") must stay on
    // that tab; the trailing segment belongs to the tab's own inner router.
    renderTabs(() => true, `${BASE}/beta/detail/7`);

    expect(screen.getByRole('link', { name: 'Beta' }).className).toContain(
      'border-theme-info-border',
    );
    expect(screen.getByRole('link', { name: 'Alpha' }).className).toContain(
      'border-transparent',
    );
  });

  it('falls back to the first accessible tab when the path names no tab', () => {
    // The bare hub path, which the caller's index route is about to redirect.
    renderTabs(() => true, BASE);

    expect(screen.getByRole('link', { name: 'Alpha' }).className).toContain(
      'border-theme-info-border',
    );
  });

  it('highlights no tab when the path names a tab the operator cannot see', () => {
    // Beta's body may still render (its route need not be permission-gated);
    // accenting Alpha instead would mislabel what is on screen.
    renderTabs((p) => p === 'feature.alpha', `${BASE}/beta`);

    expect(screen.getByRole('link', { name: 'Alpha' }).className).toContain(
      'border-transparent',
    );
    expect(screen.getByRole('link', { name: 'Alpha' }).className).not.toContain(
      'border-theme-info-border',
    );
  });

  it('ignores a path outside the basePath even when a segment matches a tab key', () => {
    renderTabs(() => true, '/somewhere/else/beta');

    // No tab is named under BASE, so the first accessible tab is accented.
    expect(screen.getByRole('link', { name: 'Alpha' }).className).toContain(
      'border-theme-info-border',
    );
    expect(screen.getByRole('link', { name: 'Beta' }).className).toContain(
      'border-transparent',
    );
  });
});

describe('activeTabKeyFromPath', () => {
  it('matches a tab on its own path', () => {
    expect(activeTabKeyFromPath(TABS, BASE, `${BASE}/beta`)).toBe('beta');
  });

  it('matches a tab on a path nested under it', () => {
    expect(activeTabKeyFromPath(TABS, BASE, `${BASE}/beta/detail/7`)).toBe('beta');
  });

  it('returns undefined for the bare basePath', () => {
    expect(activeTabKeyFromPath(TABS, BASE, BASE)).toBeUndefined();
  });

  it('returns undefined for a path outside the basePath', () => {
    expect(activeTabKeyFromPath(TABS, BASE, '/somewhere/else/beta')).toBeUndefined();
  });

  it('does not match a tab key that is only a prefix of the segment', () => {
    expect(activeTabKeyFromPath(TABS, BASE, `${BASE}/betamax`)).toBeUndefined();
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
