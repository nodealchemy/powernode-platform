import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { FirstRunWizard } from './FirstRunWizard';

const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  default: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

const renderWizard = () =>
  render(
    <MemoryRouter initialEntries={['/app/onboarding']}>
      <Routes>
        <Route path="/app/onboarding" element={<FirstRunWizard />} />
        <Route
          path="/app/system/provision"
          element={<div data-testid="new-route">provision chat</div>}
        />
      </Routes>
    </MemoryRouter>
  );

const statusResponse = (overrides: Partial<{ ai: boolean; cloud: boolean; git: boolean }> = {}) => ({
  data: {
    data: {
      completed: false,
      has_credentials: false,
      completed_at: null,
      categories: {
        ai: { has_credentials: !!overrides.ai, count: overrides.ai ? 1 : 0, available: true },
        cloud: { has_credentials: !!overrides.cloud, count: overrides.cloud ? 1 : 0, available: true },
        git: { has_credentials: !!overrides.git, count: overrides.git ? 1 : 0, available: true },
      },
    },
  },
});

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
  // Default: no pre-existing credentials in any category — full cascade.
  mockGet.mockImplementation((url: string) => {
    if (url === '/onboarding/status') {
      return Promise.resolve(statusResponse());
    }
    return Promise.reject(new Error(`Unexpected GET ${url}`));
  });
});

describe('FirstRunWizard', () => {
  it('starts on welcome with Back disabled and Next enabled', () => {
    renderWizard();
    expect(screen.getByTestId('first-run-step-welcome')).toBeInTheDocument();
    expect(screen.getByTestId('first-run-back-btn')).toBeDisabled();
    expect(screen.getByTestId('first-run-next-btn')).not.toBeDisabled();
  });

  it('navigates Welcome → AI provider on Next', async () => {
    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-ai_provider')).toBeInTheDocument()
    );
  });

  it('Skip button advances past the current category step', async () => {
    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn')); // → ai_provider
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-ai_provider')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-skip-btn')); // → cloud_provider
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-cloud_provider')).toBeInTheDocument()
    );
  });

  it('Back returns to the previous step', async () => {
    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn')); // → ai_provider
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-ai_provider')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-back-btn'));
    expect(screen.getByTestId('first-run-step-welcome')).toBeInTheDocument();
  });

  it('auto-skips AI when account already has AI credentials', async () => {
    mockGet.mockImplementation((url: string) => {
      if (url === '/onboarding/status') {
        return Promise.resolve(statusResponse({ ai: true }));
      }
      return Promise.reject(new Error(`Unexpected GET ${url}`));
    });

    renderWizard();
    // Wait for the status fetch to land + smart-skip to apply
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-progress')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    // AI step is pre-existing → wizard auto-advances to cloud
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-cloud_provider')).toBeInTheDocument()
    );
  });

  it('saves a LocalQemu cloud credential without requiring a test (single POST)', async () => {
    mockPost.mockImplementation((url: string) => {
      if (url === '/system/provider_credentials') {
        return Promise.resolve({ data: { data: { id: 'cred-local' } } });
      }
      return Promise.reject(new Error(`Unexpected POST ${url}`));
    });

    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn')); // → ai
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-ai_provider')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-skip-btn')); // ai → cloud
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-cloud_provider')).toBeInTheDocument()
    );

    fireEvent.click(screen.getByTestId('first-run-provider-local_qemu'));
    const saveBtn = screen.getByTestId('first-run-save-btn');
    expect(saveBtn).not.toBeDisabled();
    fireEvent.click(saveBtn);
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-success')).toBeInTheDocument()
    );

    expect(mockPost).toHaveBeenCalledWith(
      '/system/provider_credentials',
      expect.objectContaining({
        provider_id: 'local_qemu',
        provider_type: 'local_qemu',
      })
    );
  });

  it('walks the full happy path: skip AI → save cloud (Hetzner) → skip git → seed → redirect', async () => {
    mockPost.mockImplementation((url: string) => {
      if (url === '/system/provider_credentials/test') {
        return Promise.resolve({ data: { data: { valid: true } } });
      }
      if (url === '/system/provider_credentials') {
        return Promise.resolve({ data: { data: { id: 'cred-cloud' } } });
      }
      if (url === '/onboarding/complete') {
        return Promise.resolve({
          data: { data: { onboarding_completed_at: '2026-05-08T00:00:00Z' } },
        });
      }
      return Promise.reject(new Error(`Unexpected POST ${url}`));
    });

    renderWizard();

    // welcome → ai
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-ai_provider')).toBeInTheDocument()
    );
    // ai → skip → cloud
    fireEvent.click(screen.getByTestId('first-run-skip-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-cloud_provider')).toBeInTheDocument()
    );
    // pick Hetzner, enter token, test, save
    fireEvent.click(screen.getByTestId('first-run-provider-hetzner'));
    fireEvent.change(screen.getByTestId('provider-cred-field-api_token'), {
      target: { value: 'tok-good' },
    });
    fireEvent.click(screen.getByTestId('provider-cred-test-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('provider-cred-test-success')).toBeInTheDocument()
    );
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-btn')).not.toBeDisabled()
    );
    fireEvent.click(screen.getByTestId('first-run-save-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-success')).toBeInTheDocument()
    );
    // cloud → next → git
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-git_provider')).toBeInTheDocument()
    );
    // git → skip → complete
    fireEvent.click(screen.getByTestId('first-run-skip-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-complete')).toBeInTheDocument()
    );
    // seed → redirect
    fireEvent.click(screen.getByTestId('first-run-seed-btn'));
    await waitFor(() => {
      expect(screen.getByTestId('new-route')).toBeInTheDocument();
    });

    expect(mockPost).toHaveBeenCalledWith(
      '/system/provider_credentials',
      expect.objectContaining({
        provider_id: 'hetzner',
        provider_type: 'hetzner',
        credentials: { api_token: 'tok-good' },
      })
    );
    expect(mockPost).toHaveBeenCalledWith(
      '/onboarding/complete',
      expect.objectContaining({
        provider_credential_id: 'cred-cloud',
        provider_type: 'hetzner',
      })
    );
  });

  it('persists an AI credential via chained POSTs (provider, then credential)', async () => {
    mockPost.mockImplementation((url: string) => {
      if (url === '/ai/providers') {
        return Promise.resolve({ data: { data: { provider: { id: 'prov-ai-1' } } } });
      }
      if (url === '/ai/providers/prov-ai-1/credentials') {
        return Promise.resolve({ data: { data: { credential: { id: 'cred-ai-1' } } } });
      }
      return Promise.reject(new Error(`Unexpected POST ${url}`));
    });

    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-ai_provider')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-provider-anthropic'));
    fireEvent.change(screen.getByTestId('provider-cred-field-api_key'), {
      target: { value: 'sk-ant-abc' },
    });

    fireEvent.click(screen.getByTestId('first-run-save-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-success')).toBeInTheDocument()
    );

    expect(mockPost).toHaveBeenCalledWith(
      '/ai/providers',
      expect.objectContaining({
        provider: expect.objectContaining({ provider_type: 'anthropic' }),
      })
    );
    expect(mockPost).toHaveBeenCalledWith(
      '/ai/providers/prov-ai-1/credentials',
      expect.objectContaining({
        credential: expect.objectContaining({
          credentials: expect.objectContaining({ api_key: 'sk-ant-abc' }),
        }),
      })
    );
  });

  it('renders an error when the seed-templates POST fails', async () => {
    mockPost.mockImplementation((url: string) => {
      if (url === '/system/provider_credentials') {
        return Promise.resolve({ data: { data: { id: 'cred-x' } } });
      }
      if (url === '/onboarding/complete') {
        return Promise.reject(new Error('seed boom'));
      }
      return Promise.reject(new Error(`Unexpected POST ${url}`));
    });

    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-ai_provider')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-skip-btn')); // ai
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-cloud_provider')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-provider-local_qemu'));
    fireEvent.click(screen.getByTestId('first-run-save-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-success')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-git_provider')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-skip-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-step-complete')).toBeInTheDocument()
    );

    fireEvent.click(screen.getByTestId('first-run-seed-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-seed-error')).toHaveTextContent('seed boom')
    );
    expect(screen.queryByTestId('new-route')).toBeNull();
  });
});
