import { screen, fireEvent, waitFor, within } from '@testing-library/react';
import { render } from '@/test-utils';
import { IntegrationsPage } from './IntegrationsPage';

// secreview: the nav-link-reachability lint (C15) found BOTH "Browse
// Marketplace" actions navigating to /app/marketplace, which no route in
// core registers — a genuinely dead link, not a naming mismatch. The real
// browse-a-template experience lives at /app/devops/connections/integrations/new
// (NewIntegrationPage's TemplateSelectionStep); repoint both to there instead
// of inventing a /app/marketplace route the rest of the app never expected.
const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

jest.mock('@/features/devops/integrations/services/integrationsApi', () => ({
  integrationsApi: {
    getInstances: jest.fn(),
  },
}));

import { integrationsApi } from '@/features/devops/integrations/services/integrationsApi';

describe('IntegrationsPage — Browse Marketplace links', () => {
  beforeEach(() => {
    mockNavigate.mockClear();
  });

  it('the header action navigates to the real template browser, not dead /app/marketplace', async () => {
    (integrationsApi.getInstances as jest.Mock).mockResolvedValue({
      success: true,
      data: { instances: [] },
    });

    render(<IntegrationsPage />);
    await waitFor(() => expect(integrationsApi.getInstances).toHaveBeenCalled());

    fireEvent.click(screen.getByTestId('action-browse-marketplace'));

    expect(mockNavigate).toHaveBeenCalledWith('/app/devops/connections/integrations/new');
  });

  it('the empty-state button navigates to the real template browser, not dead /app/marketplace', async () => {
    (integrationsApi.getInstances as jest.Mock).mockResolvedValue({
      success: true,
      data: { instances: [] },
    });

    render(<IntegrationsPage />);
    const emptyState = (await screen.findByText('No integrations yet')).closest('div') as HTMLElement;
    const emptyStateButton = within(emptyState).getByRole('button', { name: 'Browse Marketplace' });

    fireEvent.click(emptyStateButton);

    expect(mockNavigate).toHaveBeenCalledWith('/app/devops/connections/integrations/new');
  });
});
