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
});
