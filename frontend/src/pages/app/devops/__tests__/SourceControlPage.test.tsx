import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';

// fc-44: DevOpsOverviewPage was deleted; Source Control is Providers |
// Repositories, opening on Providers.

jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

jest.mock('@/shared/components/layout/TabContainer', () => {
  const actual = jest.requireActual('@/shared/components/layout/TabContainer');
  return {
    ...actual,
    TabContainer: ({
      children,
      tabs,
      activeTab,
    }: {
      children?: React.ReactNode;
      tabs: Array<{ id: string; label: string }>;
      activeTab: string;
    }) => (
      <div>
        {tabs.map((t) => (
          <button key={t.id} type="button" role="tab" aria-selected={t.id === activeTab}>
            {t.label}
          </button>
        ))}
        {children}
      </div>
    ),
  };
});

jest.mock('@/pages/app/devops/GitProvidersPage', () => ({
  GitProvidersPage: () => <div data-testid="providers-tab" />,
}));
jest.mock('@/pages/app/devops/RepositoriesPage', () => ({
  RepositoriesPage: () => <div data-testid="repositories-tab" />,
}));

import { SourceControlPage } from '../SourceControlPage';

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <SourceControlPage />
    </MemoryRouter>,
  );
}

describe('SourceControlPage', () => {
  it('has exactly the Providers and Repositories tabs', () => {
    renderAt('/app/devops/source-control');
    expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual(['Providers', 'Repositories']);
  });

  it('opens on Providers at the base URL', () => {
    renderAt('/app/devops/source-control');
    expect(screen.getByTestId('providers-tab')).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'Providers' })).toHaveAttribute('aria-selected', 'true');
  });

  it('shows Repositories at /repositories', () => {
    renderAt('/app/devops/source-control/repositories');
    expect(screen.getByTestId('repositories-tab')).toBeInTheDocument();
    expect(screen.queryByTestId('providers-tab')).not.toBeInTheDocument();
  });
});
