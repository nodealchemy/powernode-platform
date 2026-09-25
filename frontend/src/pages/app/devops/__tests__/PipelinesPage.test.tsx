import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';

// fc-44: the Pipelines tab carries the deleted CI/CD Overview's run summary,
// and says plainly that these are the platform's own pipelines.

jest.mock('@/features/devops/pipelines/hooks/usePipelines', () => ({
  usePipelines: () => ({
    pipelines: [],
    meta: { total: 0, active_count: 0, total_runs: 0 },
    loading: false,
    refresh: jest.fn(),
    triggerPipeline: jest.fn(),
    duplicatePipeline: jest.fn(),
    deletePipeline: jest.fn(),
    exportPipelineYaml: jest.fn(),
  }),
}));
jest.mock('@/shared/hooks/useAuth', () => ({ useAuth: () => ({ currentUser: { permissions: [] } }) }));
jest.mock('@/shared/hooks/useNotifications', () => ({ useNotifications: () => ({ showNotification: jest.fn() }) }));
jest.mock('@/features/devops/pipelines/components/PipelineList', () => ({
  PipelineList: () => <div data-testid="pipeline-list" />,
}));
jest.mock('@/features/devops/pipelines/components/PipelineRunsSummary', () => ({
  PipelineRunsSummary: () => <div data-testid="pipeline-runs-summary" />,
}));

import { PipelinesPage } from '../PipelinesPage';

describe('PipelinesPage', () => {
  const renderPage = () =>
    render(
      <MemoryRouter>
        <PipelinesPage />
      </MemoryRouter>,
    );

  it('shows the recent-runs and success-rate summary above the list', () => {
    renderPage();

    expect(screen.getByTestId('pipeline-runs-summary')).toBeInTheDocument();
    expect(screen.getByTestId('pipeline-list')).toBeInTheDocument();
  });

  it('marks these as platform-native pipelines', () => {
    renderPage();

    expect(screen.getByText(/platform-native pipelines/i)).toBeInTheDocument();
  });
});
