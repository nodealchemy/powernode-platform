import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ProviderStep } from './ProviderStep';
import type { SetupStep } from '../services/setupApi';

jest.mock('@/features/onboarding/services/onboardingApi', () => ({
  __esModule: true,
  onboardingApi: {
    createAiProvider: jest.fn(),
    createAiCredential: jest.fn(),
    createGitProvider: jest.fn(),
    createGitCredential: jest.fn(),
  },
}));

import { onboardingApi } from '@/features/onboarding/services/onboardingApi';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { logger } from '@/shared/utils/logger';

// Cloud credentials are not served by core: the category's create/test handlers
// come from whichever extension registered them.
const mockCreateCloud = jest.fn();
const mockTestCloud = jest.fn();
const mockCreateAiProvider = onboardingApi.createAiProvider as jest.Mock;
const mockCreateAiCredential = onboardingApi.createAiCredential as jest.Mock;
const mockCreateGitProvider = onboardingApi.createGitProvider as jest.Mock;
const mockCreateGitCredential = onboardingApi.createGitCredential as jest.Mock;

const stepFor = (component: string, category: string): SetupStep => ({
  key: category + '_provider',
  title: category + ' provider',
  order: 50,
  owner: 'core',
  required: false,
  component,
  category,
  completion: 'provider_credentials',
  completed: false,
  completed_at: null,
});

describe('ProviderStep', () => {
  beforeEach(() => {
    featureRegistry.clear();
    featureRegistry.registerProviderCategoryHandlers('cloud', {
      createCredential: mockCreateCloud,
      testCredential: mockTestCloud,
    });
    mockCreateCloud.mockReset();
    mockTestCloud.mockReset();
    mockCreateAiProvider.mockReset();
    mockCreateAiCredential.mockReset();
    mockCreateGitProvider.mockReset();
    mockCreateGitCredential.mockReset();
  });

  it('renders provider options under the setup test prefix', () => {
    render(<ProviderStep step={stepFor('core/cloud_provider', 'cloud')} />);
    expect(screen.getByTestId('setup-cloud-step')).toBeInTheDocument();
    expect(screen.getByTestId('setup-provider-local_qemu')).toBeInTheDocument();
  });

  afterEach(() => featureRegistry.clear());

  it('saves a local_qemu cloud credential through the registered cloud handler', async () => {
    mockCreateCloud.mockResolvedValue('cred-local');
    render(<ProviderStep step={stepFor('core/cloud_provider', 'cloud')} />);

    fireEvent.click(screen.getByTestId('setup-provider-local_qemu'));
    const saveBtn = screen.getByTestId('setup-save-btn');
    expect(saveBtn).not.toBeDisabled();
    fireEvent.click(saveBtn);

    await waitFor(() => expect(screen.getByTestId('setup-save-success')).toBeInTheDocument());
    expect(mockCreateCloud).toHaveBeenCalledWith(
      expect.objectContaining({ providerType: 'local_qemu' })
    );
  });

  it('tests cloud credentials through the registered cloud handler', async () => {
    mockTestCloud.mockResolvedValue({ valid: true });
    render(<ProviderStep step={stepFor('core/cloud_provider', 'cloud')} />);

    fireEvent.click(screen.getByTestId('setup-provider-hetzner'));
    fireEvent.change(screen.getByTestId('provider-cred-field-api_token'), {
      target: { value: 'token-abc' },
    });
    fireEvent.click(screen.getByTestId('provider-cred-test-btn'));

    await waitFor(() => expect(screen.getByTestId('provider-cred-test-success')).toBeInTheDocument());
    expect(mockTestCloud).toHaveBeenCalledWith(
      expect.objectContaining({ providerType: 'hetzner', credentials: { api_token: 'token-abc' } })
    );
  });

  it('persists an AI credential via chained provider + credential POSTs', async () => {
    mockCreateAiProvider.mockResolvedValue('prov-ai-1');
    mockCreateAiCredential.mockResolvedValue('cred-ai-1');
    render(<ProviderStep step={stepFor('core/ai_provider', 'ai')} />);

    fireEvent.click(screen.getByTestId('setup-provider-anthropic'));
    fireEvent.change(screen.getByTestId('provider-cred-field-api_key'), {
      target: { value: 'sk-ant-abc' },
    });
    fireEvent.click(screen.getByTestId('setup-save-btn'));

    await waitFor(() => expect(screen.getByTestId('setup-save-success')).toBeInTheDocument());
    expect(mockCreateAiProvider).toHaveBeenCalledWith(
      expect.objectContaining({ providerType: 'anthropic' })
    );
    expect(mockCreateAiCredential).toHaveBeenCalledWith(
      expect.objectContaining({
        providerId: 'prov-ai-1',
        credentials: expect.objectContaining({ api_key: 'sk-ant-abc' }),
      })
    );
  });

  it('persists a Gitea credential, splitting base_url into the provider payload', async () => {
    mockCreateGitProvider.mockResolvedValue('prov-git-1');
    mockCreateGitCredential.mockResolvedValue('cred-git-1');
    render(<ProviderStep step={stepFor('core/git_provider', 'git')} />);

    fireEvent.click(screen.getByTestId('setup-provider-gitea'));
    fireEvent.change(screen.getByTestId('provider-cred-field-base_url'), {
      target: { value: 'https://git.example.com' },
    });
    fireEvent.change(screen.getByTestId('provider-cred-field-access_token'), {
      target: { value: 'tok-abc' },
    });
    fireEvent.click(screen.getByTestId('setup-save-btn'));

    await waitFor(() => expect(screen.getByTestId('setup-save-success')).toBeInTheDocument());

    expect(mockCreateGitProvider).toHaveBeenCalledWith(
      expect.objectContaining({ providerType: 'gitea', apiBaseUrl: 'https://git.example.com' })
    );
    expect(mockCreateGitCredential).toHaveBeenCalledWith(
      expect.objectContaining({
        providerId: 'prov-git-1',
        credentials: expect.objectContaining({ access_token: 'tok-abc' }),
      })
    );
    // base_url must not leak into the credential payload — it's provider config.
    expect(mockCreateGitCredential.mock.calls[0][0].credentials).not.toHaveProperty('base_url');
  });

  it('logs a failed save without the credential values the request carried', async () => {
    const logSpy = jest.spyOn(logger, 'error').mockImplementation(() => undefined);
    mockCreateAiProvider.mockResolvedValue('prov-ai-1');
    mockCreateAiCredential.mockRejectedValue(
      Object.assign(new Error('Request failed with status code 422'), {
        config: { data: JSON.stringify({ credential: { credentials: { api_key: 'PLANTED-SECRET' } } }) },
        response: { status: 422, data: {} },
      })
    );
    render(<ProviderStep step={stepFor('core/ai_provider', 'ai')} />);
    fireEvent.click(screen.getByTestId('setup-provider-anthropic'));
    fireEvent.change(screen.getByTestId('provider-cred-field-api_key'), {
      target: { value: 'PLANTED-SECRET' },
    });
    fireEvent.click(screen.getByTestId('setup-save-btn'));

    await waitFor(() => expect(logSpy).toHaveBeenCalled());
    const logged = JSON.stringify(logSpy.mock.calls, (_k, v) =>
      v instanceof Error ? { ...v, message: v.message } : v
    );
    expect(logged).not.toContain('PLANTED-SECRET');
    expect(logSpy.mock.calls[0][2]).toEqual(expect.objectContaining({ status: 422, category: 'ai' }));
    logSpy.mockRestore();
  });
});
