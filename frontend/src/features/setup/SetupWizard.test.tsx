import { fireEvent, screen, waitFor } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import { SetupWizard } from './SetupWizard';

jest.mock('./services/setupApi', () => ({
  __esModule: true,
  setupApi: {
    getStatus: jest.fn(),
    getSteps: jest.fn(),
    submitStep: jest.fn(),
    createAdmin: jest.fn(),
    getExtensions: jest.fn(),
    setExtension: jest.fn(),
  },
}));

// The post-admin session restore reuses these thunks; stub them so dispatch(...)
// .unwrap() resolves without hitting the network.
jest.mock('@/shared/services/slices/authSlice', () => {
  const thunk = () => () => ({ unwrap: () => Promise.resolve() });
  return { __esModule: true, refreshAccessToken: thunk, getCurrentUser: thunk };
});

import { setupApi } from './services/setupApi';

const mockGetStatus = setupApi.getStatus as jest.Mock;
const mockGetSteps = setupApi.getSteps as jest.Mock;
const mockCreateAdmin = setupApi.createAdmin as jest.Mock;
const mockGetExtensions = setupApi.getExtensions as jest.Mock;

const setUrl = (path: string) => window.history.replaceState({}, '', path);

const fillAdmin = () => {
  fireEvent.change(screen.getByTestId('setup-admin-field-email'), { target: { value: 'ada@b.co' } });
  fireEvent.change(screen.getByTestId('setup-admin-field-password'), { target: { value: 'Sup3r$ecretX!' } });
};

describe('SetupWizard', () => {
  beforeEach(() => {
    mockGetStatus.mockReset();
    mockGetSteps.mockReset();
    mockCreateAdmin.mockReset();
    mockGetExtensions.mockReset();
  });

  it('shows the admin step and gates the create button on email + password', async () => {
    setUrl('/setup?token=tok-123');
    mockGetStatus.mockResolvedValue({ bootstrap_complete: false, pending: [] });

    renderWithProviders(<SetupWizard />);

    await waitFor(() => expect(screen.getByTestId('setup-step-admin')).toBeInTheDocument());
    expect(screen.getByTestId('setup-admin-create-btn')).toBeDisabled();

    fillAdmin();
    await waitFor(() => expect(screen.getByTestId('setup-admin-create-btn')).not.toBeDisabled());
  });

  it('blocks the admin step when no setup token is present in the URL', async () => {
    setUrl('/setup');
    mockGetStatus.mockResolvedValue({ bootstrap_complete: false, pending: [] });

    renderWithProviders(<SetupWizard />);

    await waitFor(() => expect(screen.getByTestId('setup-token-missing')).toBeInTheDocument());
    fillAdmin();
    expect(screen.getByTestId('setup-admin-create-btn')).toBeDisabled();
  });

  it('shows an already-complete notice for an anonymous visitor once bootstrap is done', async () => {
    setUrl('/setup');
    mockGetStatus.mockResolvedValue({ bootstrap_complete: true, pending: [] });

    renderWithProviders(<SetupWizard />);

    await waitFor(() => expect(screen.getByTestId('setup-wizard-notice')).toBeInTheDocument());
    expect(screen.getByText(/already complete/i)).toBeInTheDocument();
  });

  it('posts the URL token and entered fields to createAdmin', async () => {
    setUrl('/setup?token=tok-xyz');
    mockGetStatus.mockResolvedValue({ bootstrap_complete: false, pending: [] });
    mockCreateAdmin.mockResolvedValue({
      user: { id: 'u1', email: 'ada@b.co', name: null },
      account: { id: 'a1', name: null },
      access_token: 'jwt',
    });

    renderWithProviders(<SetupWizard />);

    await waitFor(() => expect(screen.getByTestId('setup-step-admin')).toBeInTheDocument());
    fillAdmin();
    await waitFor(() => expect(screen.getByTestId('setup-admin-create-btn')).not.toBeDisabled());
    fireEvent.click(screen.getByTestId('setup-admin-create-btn'));

    await waitFor(() =>
      expect(mockCreateAdmin).toHaveBeenCalledWith(
        expect.objectContaining({ token: 'tok-xyz', email: 'ada@b.co', password: 'Sup3r$ecretX!' })
      )
    );
  });

  it('renders the extension-selection component step for an authenticated admin', async () => {
    setUrl('/setup');
    mockGetSteps.mockResolvedValue([
      {
        key: 'extension_selection',
        title: 'Extensions',
        description: 'Toggle extensions.',
        order: 40,
        owner: 'core',
        required: false,
        component: 'core/extension_selection',
        completed: false,
        completed_at: null,
      },
    ]);
    mockGetExtensions.mockResolvedValue([{ slug: 'system', version: '1.0', enabled: true }]);

    renderWithProviders(<SetupWizard />, {
      preloadedState: { auth: { isAuthenticated: true, user: { id: '1' }, isLoading: false } },
    });

    await waitFor(() => expect(screen.getByTestId('setup-extension-list')).toBeInTheDocument());
    expect(screen.getByTestId('setup-ext-toggle-system')).toHaveTextContent('Enabled');
  });
});
