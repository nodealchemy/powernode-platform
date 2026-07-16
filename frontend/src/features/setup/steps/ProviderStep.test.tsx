import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ProviderStep } from './ProviderStep';
import type { SetupStep } from '../services/setupApi';

jest.mock('@/features/onboarding/services/onboardingApi', () => ({
  __esModule: true,
  onboardingApi: {
    testCredentials: jest.fn(),
    createCloudCredential: jest.fn(),
    createAiProvider: jest.fn(),
    createAiCredential: jest.fn(),
    createGitProvider: jest.fn(),
    createGitCredential: jest.fn(),
  },
}));

import { onboardingApi } from '@/features/onboarding/services/onboardingApi';

const mockCreateCloud = onboardingApi.createCloudCredential as jest.Mock;
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
    mockCreateCloud.mockReset();
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

  it('saves a local_qemu cloud credential via onboardingApi (single POST)', async () => {
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
});
