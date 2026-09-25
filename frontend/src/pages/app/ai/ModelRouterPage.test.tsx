import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { ModelRouterContent } from './ModelRouterPage';

jest.mock('@/shared/services/ai/ModelRouterApiService', () => ({
  modelRouterApi: {
    getRules: jest.fn().mockResolvedValue({ rules: [] }),
    getDecisions: jest.fn().mockResolvedValue({ decisions: [] }),
    getStatistics: jest.fn().mockResolvedValue({}),
    getCostAnalysis: jest.fn().mockResolvedValue({}),
    getProviderRankings: jest.fn().mockResolvedValue({ rankings: [] }),
    getRecommendations: jest.fn().mockResolvedValue({ recommendations: [] }),
    getOptimizations: jest.fn().mockResolvedValue({ optimizations: [], stats: null }),
  },
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({
  usePageWebSocket: () => undefined,
}));

jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: { permissions: ['ai.routing.read'] } }),
}));

jest.mock('react-redux', () => ({
  ...jest.requireActual('react-redux'),
  useDispatch: () => jest.fn(),
}));

const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

const renderAt = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <ModelRouterContent />
      <LocationProbe />
    </MemoryRouter>
  );

describe('ModelRouterContent path tabs', () => {
  it('lands on Rules by default', async () => {
    renderAt('/app/ai/infrastructure/model-router');
    await waitFor(() => expect(screen.getByText('Rules')).toBeInTheDocument());
  });

  it('deep-links directly to the Decisions tab', async () => {
    renderAt('/app/ai/infrastructure/model-router/decisions');
    await waitFor(() => expect(screen.getByText('Decisions')).toBeInTheDocument());
    expect(screen.getByText('Decisions').closest('button')).toHaveClass('border-theme-interactive-primary');
  });

  it('deep-links directly to the Escalations tab (permission granted)', async () => {
    renderAt('/app/ai/infrastructure/model-router/escalations');
    await waitFor(() => expect(screen.getByText('Escalations')).toBeInTheDocument());
    expect(screen.getByText('Escalations').closest('button')).toHaveClass('border-theme-interactive-primary');
  });

  it('updates the URL when a tab is clicked', async () => {
    renderAt('/app/ai/infrastructure/model-router');
    await waitFor(() => expect(screen.getByText('Optimization')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Optimization'));

    await waitFor(() =>
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/infrastructure/model-router/optimization')
    );
  });
});
