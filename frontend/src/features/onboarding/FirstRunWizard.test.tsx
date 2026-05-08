import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { FirstRunWizard } from './FirstRunWizard';

const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  default: {
    get: jest.fn(),
    post: (...args: unknown[]) => mockPost(...args),
  },
  apiClient: {
    get: jest.fn(),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

const renderWizard = () =>
  render(
    <MemoryRouter initialEntries={['/onboarding']}>
      <Routes>
        <Route path="/onboarding" element={<FirstRunWizard />} />
        <Route
          path="/new"
          element={<div data-testid="new-route">new chat</div>}
        />
      </Routes>
    </MemoryRouter>
  );

beforeEach(() => {
  mockPost.mockReset();
});

describe('FirstRunWizard', () => {
  it('starts on the welcome step with Back disabled and Next enabled', () => {
    renderWizard();
    expect(screen.getByTestId('first-run-step-welcome')).toBeInTheDocument();
    expect(screen.getByTestId('first-run-back-btn')).toBeDisabled();
    expect(screen.getByTestId('first-run-next-btn')).not.toBeDisabled();
  });

  it('navigates Welcome → Provider on Next', () => {
    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    expect(screen.getByTestId('first-run-step-provider')).toBeInTheDocument();
  });

  it('blocks Next on the provider step until a provider is chosen', () => {
    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    const next = screen.getByTestId('first-run-next-btn');
    expect(next).toBeDisabled();
    fireEvent.click(screen.getByTestId('first-run-provider-hetzner'));
    expect(next).not.toBeDisabled();
  });

  it('Back returns to the previous step', () => {
    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn')); // → provider
    fireEvent.click(screen.getByTestId('first-run-back-btn')); // → welcome
    expect(screen.getByTestId('first-run-step-welcome')).toBeInTheDocument();
  });

  it('walks through the full happy path and redirects to /new', async () => {
    // Save credentials → Complete onboarding (two POSTs in order)
    mockPost.mockImplementation((url: string) => {
      if (url === '/system/provider_credentials/test') {
        return Promise.resolve({ data: { data: { valid: true } } });
      }
      if (url === '/system/provider_credentials') {
        return Promise.resolve({ data: { data: { id: 'cred-1' } } });
      }
      if (url === '/onboarding/complete') {
        return Promise.resolve({
          data: { data: { onboarding_completed_at: '2026-05-07T00:00:00Z' } },
        });
      }
      return Promise.reject(new Error(`Unexpected POST ${url}`));
    });

    renderWizard();

    // Step 1 → 2
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    // Step 2: choose Hetzner
    fireEvent.click(screen.getByTestId('first-run-provider-hetzner'));
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    // Step 3: enter token, test, save
    fireEvent.change(screen.getByTestId('provider-cred-field-api_token'), {
      target: { value: 'tok-good' },
    });
    fireEvent.click(screen.getByTestId('provider-cred-test-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('provider-cred-test-success')).toBeInTheDocument()
    );
    // Wait for the parent reducer to receive the 'valid' test status so the
    // Save button becomes enabled.
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-btn')).not.toBeDisabled()
    );
    fireEvent.click(screen.getByTestId('first-run-save-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-success')).toBeInTheDocument()
    );
    // Advance to step 4
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    expect(screen.getByTestId('first-run-step-complete')).toBeInTheDocument();
    // Click seed, redirect happens automatically on success
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
        provider_credential_id: 'cred-1',
        provider_type: 'hetzner',
      })
    );
  });

  it('LocalQemu does not require a credential test before saving', async () => {
    mockPost.mockImplementation((url: string) => {
      if (url === '/system/provider_credentials') {
        return Promise.resolve({ data: { data: { id: 'cred-local' } } });
      }
      return Promise.reject(new Error(`Unexpected POST ${url}`));
    });

    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn')); // welcome → provider
    fireEvent.click(screen.getByTestId('first-run-provider-localqemu'));
    fireEvent.click(screen.getByTestId('first-run-next-btn')); // provider → credentials

    // libvirt_uri is prefilled and not required, so save should be enabled immediately.
    const saveBtn = screen.getByTestId('first-run-save-btn');
    expect(saveBtn).not.toBeDisabled();
    fireEvent.click(saveBtn);
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-success')).toBeInTheDocument()
    );
  });

  it('renders an error when the seed-templates POST fails', async () => {
    mockPost.mockImplementation((url: string) => {
      if (url === '/system/provider_credentials/test') {
        return Promise.resolve({ data: { data: { valid: true } } });
      }
      if (url === '/system/provider_credentials') {
        return Promise.resolve({ data: { data: { id: 'cred-2' } } });
      }
      if (url === '/onboarding/complete') {
        return Promise.reject(new Error('seed boom'));
      }
      return Promise.reject(new Error(`Unexpected POST ${url}`));
    });

    renderWizard();
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    fireEvent.click(screen.getByTestId('first-run-provider-vultr'));
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    fireEvent.change(screen.getByTestId('provider-cred-field-api_key'), {
      target: { value: 'k' },
    });
    fireEvent.click(screen.getByTestId('provider-cred-test-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('provider-cred-test-success')).toBeInTheDocument()
    );
    // Wait for the parent reducer to receive the 'valid' test status so the
    // Save button becomes enabled.
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-btn')).not.toBeDisabled()
    );
    fireEvent.click(screen.getByTestId('first-run-save-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-save-success')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByTestId('first-run-next-btn'));
    fireEvent.click(screen.getByTestId('first-run-seed-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('first-run-seed-error')).toHaveTextContent('seed boom')
    );
    // Should not have navigated away
    expect(screen.queryByTestId('new-route')).toBeNull();
  });
});
