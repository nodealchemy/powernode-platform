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

let mockPermissions: string[] = ['ai.routing.read'];
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: { permissions: mockPermissions } }),
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
  beforeEach(() => {
    mockPermissions = ['ai.routing.read'];
  });

  it('lands on Rules by default', async () => {
    renderAt('/app/ai/model-router');
    await waitFor(() => expect(screen.getByText('Rules')).toBeInTheDocument());
  });

  it('deep-links directly to the Decisions tab', async () => {
    renderAt('/app/ai/model-router/decisions');
    await waitFor(() => expect(screen.getByText('Decisions')).toBeInTheDocument());
    expect(screen.getByText('Decisions').closest('button')).toHaveClass('border-theme-interactive-primary');
  });

  it('deep-links directly to the Escalations tab (permission granted)', async () => {
    renderAt('/app/ai/model-router/escalations');
    await waitFor(() => expect(screen.getByText('Escalations')).toBeInTheDocument());
    expect(screen.getByText('Escalations').closest('button')).toHaveClass('border-theme-interactive-primary');
  });

  it('falls back to Rules on an escalations deep link without ai.routing.read, not a blank area', async () => {
    mockPermissions = [];
    renderAt('/app/ai/model-router/escalations');

    await waitFor(() => expect(screen.getByText('Rules')).toBeInTheDocument());
    expect(screen.getByText('Rules').closest('button')).toHaveClass('border-theme-interactive-primary');
    // The Escalations tab itself isn't even offered to this user.
    expect(screen.queryByText('Escalations')).not.toBeInTheDocument();
  });

  it('updates the URL when a tab is clicked', async () => {
    renderAt('/app/ai/model-router');
    await waitFor(() => expect(screen.getByText('Optimization')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Optimization'));

    await waitFor(() =>
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/model-router/optimization')
    );
  });
});
