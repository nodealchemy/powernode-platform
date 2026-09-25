import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { DevOpsHubPage } from './DevOpsHubPage';
import { devopsOverviewApi } from '@/services/devopsOverviewApi';
import type { DevopsOverviewResponse } from '@/services/devopsOverviewApi';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';

jest.mock('@/services/devopsOverviewApi', () => ({
  devopsOverviewApi: { getOverview: jest.fn() },
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({ usePageWebSocket: () => undefined }));

const OVERVIEW: DevopsOverviewResponse = {
  source_control: {
    providers: { total: 0, active: 0, by_type: {} },
    repositories: { total: 0, active: 0, with_webhook: 0 },
    credentials: { total: 0, healthy: 0, unhealthy: 0, expires_soon: 0 },
  },
  ci_cd: {
    pipelines: { total: 0, active: 0 },
    pipeline_runs: { total: 0, successful: 0, failed: 0, running: 0, today: 0, success_rate: 0 },
    runners: { total: 0, online: 0, offline: 0, busy: 0 },
    schedules: { total: 0, active: 0 },
  },
  infrastructure: {
    containers: { total: 10, active: 3, paused: 2, completed: 4, failed: 1, finished: 5, success_rate: 80 },
    swarm: { clusters: 0, connected: 0 },
    docker: { hosts: 0, connected: 0 },
  },
  connections: {
    integrations: { total: 0, active: 0, healthy: 0, errored: 0 },
    webhooks: { total: 0, processed_today: 0, failed_today: 0 },
    api_keys: { total: 0 },
  },
  alerts: [],
};

describe('DevOpsHubPage sandboxes card', () => {
  it('shows the paused sandbox count alongside Active', async () => {
    (devopsOverviewApi.getOverview as jest.Mock).mockResolvedValue(OVERVIEW);

    render(
      <MemoryRouter>
        <BreadcrumbProvider>
          <DevOpsHubPage />
        </BreadcrumbProvider>
      </MemoryRouter>
    );

    // Each stat renders as a single "Label: value" text node (see
    // DevOpsHubPage's `{stat.label}: ` + `{stat.value}` spans) — match the
    // whole row's text rather than the bare label.
    await waitFor(() => expect(screen.getByText('Paused:')).toBeInTheDocument());
    const pausedLabel = screen.getByText('Paused:');
    const statRow = pausedLabel.closest('div');
    expect(statRow).toHaveTextContent('Paused: 2');
  });
});
