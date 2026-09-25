import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';

// fc-44: "Connections" became "Integrations & Webhooks" at
// /app/devops/integrations, with two tabs. API Keys left for its own nav item.

jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({
    title,
    breadcrumbs = [],
    children,
  }: {
    title: string;
    breadcrumbs?: Array<{ label: string }>;
    children: React.ReactNode;
  }) => (
    <div>
      <h1>{title}</h1>
      <div data-testid="breadcrumbs">{breadcrumbs.map((b) => b.label).join(' / ')}</div>
      {children}
    </div>
  ),
}));

jest.mock('@/shared/components/layout/TabContainer', () => {
  const actual = jest.requireActual('@/shared/components/layout/TabContainer');
  return {
    ...actual,
    TabContainer: ({
      children,
      tabs,
      activeTab,
      basePath,
    }: {
      children?: React.ReactNode;
      tabs: Array<{ id: string; label: string; path: string }>;
      activeTab: string;
      basePath: string;
    }) => (
      <div>
        {tabs.map((t) => (
          <a key={t.id} role="tab" aria-selected={t.id === activeTab} href={`${basePath}${t.path === '/' ? '' : t.path}`}>
            {t.label}
          </a>
        ))}
        {children}
      </div>
    ),
  };
});

jest.mock('@/pages/app/devops/integrations', () => ({
  IntegrationsPage: () => <div data-testid="integrations-tab" />,
}));
jest.mock('@/pages/app/devops/WebhooksPage', () => ({
  __esModule: true,
  default: () => <div data-testid="webhook-endpoints-tab" />,
}));

import { IntegrationsWebhooksPage } from '../IntegrationsWebhooksPage';

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <IntegrationsWebhooksPage />
    </MemoryRouter>,
  );
}

describe('IntegrationsWebhooksPage', () => {
  it('is titled Integrations & Webhooks', () => {
    renderAt('/app/devops/integrations');
    expect(screen.getByRole('heading', { name: 'Integrations & Webhooks' })).toBeInTheDocument();
  });

  it('has exactly the Integrations and Webhook endpoints tabs, at their URLs', () => {
    renderAt('/app/devops/integrations');

    const tabs = screen.getAllByRole('tab');
    expect(tabs.map((t) => t.textContent)).toEqual(['Integrations', 'Webhook endpoints']);
    expect(tabs.map((t) => t.getAttribute('href'))).toEqual([
      '/app/devops/integrations',
      '/app/devops/integrations/webhook-endpoints',
    ]);
  });

  it('shows integrations at the base URL', () => {
    renderAt('/app/devops/integrations');
    expect(screen.getByTestId('integrations-tab')).toBeInTheDocument();
    expect(screen.queryByTestId('webhook-endpoints-tab')).not.toBeInTheDocument();
  });

  it('shows webhook endpoints at /webhook-endpoints, with the tab in the breadcrumb', () => {
    renderAt('/app/devops/integrations/webhook-endpoints');
    expect(screen.getByTestId('webhook-endpoints-tab')).toBeInTheDocument();
    expect(screen.getByTestId('breadcrumbs')).toHaveTextContent(
      'Dashboard / DevOps / Integrations & Webhooks / Webhook endpoints',
    );
  });
});
