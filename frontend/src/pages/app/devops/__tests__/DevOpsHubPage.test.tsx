import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';

// fc-44: the Overview's section cards match the regrouped DevOps nav — one
// card per section other than Overview itself — plus fc-32's Sandboxes card,
// which links to Sandboxes' single home under AI › Execution.

jest.mock('@/shared/hooks/usePageWebSocket', () => ({ usePageWebSocket: jest.fn() }));
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

const mockOverview = {
  source_control: { providers: { active: 1, total: 1 }, repositories: { total: 2, with_webhook: 1 } },
  ci_cd: {
    pipelines: { active: 1, total: 1 },
    runners: { total: 1, online: 1, busy: 0, offline: 0 },
    pipeline_runs: { total: 0, successful: 0, failed: 0, running: 0, success_rate: 0 },
  },
  infrastructure: {
    containers: { active: 1, paused: 2, total: 1, completed: 1, failed: 0, finished: 1, success_rate: 100 },
    swarm: { clusters: 1, connected: 1 },
    docker: { hosts: 2, connected: 2 },
  },
  connections: {
    integrations: { total: 3, active: 3, errored: 0 },
    webhooks: { total: 4, processed_today: 0, failed_today: 0 },
    api_keys: { total: 5 },
  },
  alerts: [],
};

// `@/services/*` has no jest moduleNameMapper entry, so the mock is virtual.
jest.mock(
  '@/services/devopsOverviewApi',
  () => ({ devopsOverviewApi: { getOverview: () => Promise.resolve(mockOverview) } }),
  { virtual: true },
);

import { DevOpsHubPage } from '../DevOpsHubPage';

const Where: React.FC = () => <div data-testid="where">{useLocation().pathname}</div>;

function renderHub() {
  return render(
    <MemoryRouter initialEntries={['/app/devops']}>
      <Routes>
        <Route path="/app/devops" element={<DevOpsHubPage />} />
        <Route path="*" element={<Where />} />
      </Routes>
    </MemoryRouter>,
  );
}

const SECTIONS: Array<[string, string]> = [
  ['Source Control', '/app/devops/source-control'],
  ['CI/CD', '/app/devops/ci-cd'],
  ['Integrations & Webhooks', '/app/devops/integrations'],
  ['API Keys', '/app/devops/api-keys'],
  ['Containers', '/app/devops/containers'],
  ['Sandboxes', '/app/ai/execution/sandboxes'],
  ['Developer Portal', '/app/developer'],
];

describe('DevOpsHubPage section cards', () => {
  it('shows one card per regrouped DevOps section, in nav order, plus Sandboxes', async () => {
    renderHub();

    const cards = await screen.findAllByTestId(/^devops-section-/);
    expect(cards.map((c) => c.getAttribute('data-testid'))).toEqual([
      'devops-section-source-control',
      'devops-section-ci-cd',
      'devops-section-integrations',
      'devops-section-api-keys',
      'devops-section-containers',
      'devops-section-sandboxes',
      'devops-section-developer-portal',
    ]);
  });

  it('keeps the Sandboxes card\'s Paused stat', async () => {
    renderHub();

    const card = await screen.findByTestId('devops-section-sandboxes');
    expect(card).toHaveTextContent('Paused: 2');
  });

  it.each(SECTIONS)('the %s card opens %s', async (name, href) => {
    renderHub();

    const card = await screen.findByRole('heading', { name, level: 4 });
    fireEvent.click(card);

    expect(screen.getByTestId('where')).toHaveTextContent(href);
  });
});
