import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ProviderStep } from './ProviderStep';
import type { SetupStep } from '../services/setupApi';

jest.mock('@/features/onboarding/services/onboardingApi', () => ({
  __esModule: true,
  onboardingApi: {
    createAiProvider: jest.fn(),
    createAiCredential: jest.fn(),
    createGitProvider: jest.fn(),
    createGitCredential: jest.fn(),
    getAiProviderCatalog: jest.fn(),
    setAiDefaultProvider: jest.fn(),
    deleteAiCredential: jest.fn(),
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

const mockSetAiDefault = onboardingApi.setAiDefaultProvider as jest.Mock;
const mockDeleteAiCredential = onboardingApi.deleteAiCredential as jest.Mock;
const mockGetAiCatalog = onboardingApi.getAiProviderCatalog as jest.Mock;

const AI_CATALOG = [
  {
    name: 'Claude AI (Anthropic)',
    slug: 'claude-ai-anthropic',
    provider_type: 'anthropic',
    api_base_url: 'https://api.example-anthropic.test/v1',
    capabilities: ['text_generation'],
    default_model: 'model-x',
    default_embedding_model: null,
    models: ['model-x', 'model-y'],
    requires_auth: true,
    credential_fields: [{ key: 'api_key', label: 'API Key', type: 'password', required: true }],
  },
];

const synced = (id: string, count: number, extra: Record<string, unknown> = {}) => ({
  id,
  modelSync: { success: true, model_count: count, error: null, ...extra },
});

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
    mockSetAiDefault.mockReset();
    mockDeleteAiCredential.mockReset();
    mockGetAiCatalog.mockReset();
    mockGetAiCatalog.mockResolvedValue({ items: AI_CATALOG, known_capabilities: ['text_generation'] });
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
    mockCreateAiCredential.mockResolvedValue(synced('cred-ai-1', 12));
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

  it('auto-fills the AI provider details from the catalog and keeps them editable', async () => {
    mockCreateAiProvider.mockResolvedValue('prov-ai-1');
    mockCreateAiCredential.mockResolvedValue(synced('cred-ai-1', 12));
    render(<ProviderStep step={stepFor('core/ai_provider', 'ai')} />);
    await waitFor(() => expect(mockGetAiCatalog).toHaveBeenCalled());
    await act(async () => {});

    fireEvent.click(screen.getByTestId('setup-provider-anthropic'));

    await waitFor(() =>
      expect(screen.getByTestId('setup-provider-name')).toHaveValue('Claude AI (Anthropic)')
    );
    expect(screen.getByTestId('setup-provider-base-url')).toHaveValue(
      'https://api.example-anthropic.test/v1'
    );
    expect(screen.getByTestId('provider-cred-field-default_model')).toHaveValue('model-x');
    // Only the models valid for the type are offered.
    const offered = Array.from(
      screen.getByTestId('provider-cred-options-default_model').querySelectorAll('option')
    ).map((o) => o.getAttribute('value'));
    expect(offered).toEqual(['model-x', 'model-y']);

    fireEvent.change(screen.getByTestId('setup-provider-name'), { target: { value: 'My Claude' } });
    fireEvent.change(screen.getByTestId('provider-cred-field-api_key'), {
      target: { value: 'fake-key-1' },
    });
    fireEvent.click(screen.getByTestId('setup-save-btn'));

    await waitFor(() => expect(screen.getByTestId('setup-save-success')).toBeInTheDocument());
    expect(mockCreateAiProvider).toHaveBeenCalledWith(
      expect.objectContaining({
        providerType: 'anthropic',
        name: 'My Claude',
        apiBaseUrl: 'https://api.example-anthropic.test/v1',
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

  describe('multiple AI providers', () => {
    const OPENAI_ENTRY = {
      ...AI_CATALOG[0],
      name: 'OpenAI',
      slug: 'openai',
      provider_type: 'openai',
      api_base_url: 'https://api.example-openai.test/v1',
      default_model: 'model-o',
      models: ['model-o'],
    };

    const addProvider = async (type: string, key: string) => {
      fireEvent.click(screen.getByTestId(`setup-provider-${type}`));
      fireEvent.change(screen.getByTestId('provider-cred-field-api_key'), { target: { value: key } });
      fireEvent.click(screen.getByTestId('setup-save-btn'));
      await waitFor(() => expect(screen.getByTestId('setup-save-success')).toBeInTheDocument());
    };

    beforeEach(() => {
      mockGetAiCatalog.mockResolvedValue({
        items: [...AI_CATALOG, OPENAI_ENTRY],
        known_capabilities: ['text_generation'],
      });
      mockCreateAiProvider.mockResolvedValueOnce('prov-a').mockResolvedValueOnce('prov-b');
    });

    it('persists and syncs two providers, listing each with its own result', async () => {
      mockCreateAiCredential
        .mockResolvedValueOnce(synced('cred-a', 12, { default: true }))
        .mockResolvedValueOnce(synced('cred-b', 61));
      render(<ProviderStep step={stepFor('core/ai_provider', 'ai')} />);
      await waitFor(() => expect(mockGetAiCatalog).toHaveBeenCalled());
      await act(async () => {});

      await addProvider('anthropic', 'fake-key-a');
      fireEvent.click(screen.getByTestId('setup-add-another'));
      await addProvider('openai', 'fake-key-b');

      expect(mockCreateAiCredential).toHaveBeenCalledTimes(2);
      expect(mockCreateAiProvider.mock.calls.map((c) => c[0].providerType)).toEqual(['anthropic', 'openai']);
      expect(screen.getByTestId('setup-sync-result-0')).toHaveTextContent('12 models');
      expect(screen.getByTestId('setup-sync-result-1')).toHaveTextContent('61 models');
    });

    it('reports a failed sync as an error and keeps that provider out of the default choices', async () => {
      mockCreateAiCredential
        .mockResolvedValueOnce(synced('cred-a', 12, { default: true }))
        .mockResolvedValueOnce({
          id: 'cred-b',
          modelSync: { success: false, model_count: 0, error: 'upstream denied the key' },
        });
      render(<ProviderStep step={stepFor('core/ai_provider', 'ai')} />);
      await waitFor(() => expect(mockGetAiCatalog).toHaveBeenCalled());
      await act(async () => {});

      await addProvider('anthropic', 'fake-key-a');
      fireEvent.click(screen.getByTestId('setup-add-another'));
      await addProvider('openai', 'fake-key-b');

      expect(screen.getByTestId('setup-sync-result-1')).toHaveTextContent('upstream denied the key');
      expect(screen.getByTestId('setup-default-0')).toBeInTheDocument();
      expect(screen.queryByTestId('setup-default-1')).not.toBeInTheDocument();
    });

    it('marks a single working provider as the default without a choice', async () => {
      mockCreateAiCredential.mockResolvedValueOnce(synced('cred-a', 12, { default: true }));
      render(<ProviderStep step={stepFor('core/ai_provider', 'ai')} />);
      await waitFor(() => expect(mockGetAiCatalog).toHaveBeenCalled());
      await act(async () => {});

      await addProvider('anthropic', 'fake-key-a');

      expect(screen.getByTestId('setup-default-0')).toBeChecked();
      expect(mockSetAiDefault).not.toHaveBeenCalled();
    });

    it('lets the operator choose the default among working providers', async () => {
      mockSetAiDefault.mockResolvedValue(undefined);
      mockCreateAiCredential
        .mockResolvedValueOnce(synced('cred-a', 12, { default: true }))
        .mockResolvedValueOnce(synced('cred-b', 61));
      render(<ProviderStep step={stepFor('core/ai_provider', 'ai')} />);
      await waitFor(() => expect(mockGetAiCatalog).toHaveBeenCalled());
      await act(async () => {});
      await addProvider('anthropic', 'fake-key-a');
      fireEvent.click(screen.getByTestId('setup-add-another'));
      await addProvider('openai', 'fake-key-b');

      fireEvent.click(screen.getByTestId('setup-default-1'));

      await waitFor(() => expect(mockSetAiDefault).toHaveBeenCalledWith('prov-b'));
      await waitFor(() => expect(screen.getByTestId('setup-default-1')).toBeChecked());
      expect(screen.getByTestId('setup-default-0')).not.toBeChecked();
    });

    it('removes an entry before finishing and hands the default to the remaining one', async () => {
      mockSetAiDefault.mockResolvedValue(undefined);
      mockDeleteAiCredential.mockResolvedValue(undefined);
      mockCreateAiCredential
        .mockResolvedValueOnce(synced('cred-a', 12, { default: true }))
        .mockResolvedValueOnce(synced('cred-b', 61));
      render(<ProviderStep step={stepFor('core/ai_provider', 'ai')} />);
      await waitFor(() => expect(mockGetAiCatalog).toHaveBeenCalled());
      await act(async () => {});
      await addProvider('anthropic', 'fake-key-a');
      fireEvent.click(screen.getByTestId('setup-add-another'));
      await addProvider('openai', 'fake-key-b');

      fireEvent.click(screen.getByTestId('setup-provider-remove-0'));

      await waitFor(() =>
        expect(mockDeleteAiCredential).toHaveBeenCalledWith({ providerId: 'prov-a', credentialId: 'cred-a' })
      );
      await waitFor(() => expect(mockSetAiDefault).toHaveBeenCalledWith('prov-b'));
      expect(screen.getAllByTestId(/^setup-provider-entry-/)).toHaveLength(1);
    });
  });
});
