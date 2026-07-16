import { onboardingApi } from './onboardingApi';

const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  default: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
});

describe('onboardingApi.createAiProvider', () => {
  it('reuses an existing provider id and skips the create POST', async () => {
    mockGet.mockResolvedValueOnce({
      data: { data: { items: [{ id: 'prov-existing', provider_type: 'anthropic' }] } },
    });

    const id = await onboardingApi.createAiProvider({ providerType: 'anthropic', name: 'Anthropic Claude' });

    expect(id).toBe('prov-existing');
    expect(mockGet).toHaveBeenCalledWith('/ai/providers', { params: { provider_type: 'anthropic' } });
    expect(mockPost).not.toHaveBeenCalled();
  });

  it('falls through to POST /ai/providers when the index returns no items', async () => {
    mockGet.mockResolvedValueOnce({ data: { data: { items: [] } } });
    mockPost.mockResolvedValueOnce({ data: { data: { provider: { id: 'prov-created' } } } });

    const id = await onboardingApi.createAiProvider({ providerType: 'openai', name: 'OpenAI' });

    expect(id).toBe('prov-created');
    expect(mockPost).toHaveBeenCalledWith('/ai/providers', {
      provider: { provider_type: 'openai', name: 'OpenAI' },
    });
  });
});

describe('onboardingApi.createGitProvider', () => {
  it('forwards apiBaseUrl as provider.api_base_url when present', async () => {
    mockPost.mockResolvedValueOnce({ data: { data: { provider: { id: 'prov-git-1' } } } });

    await onboardingApi.createGitProvider({
      providerType: 'gitea',
      name: 'Gitea',
      apiBaseUrl: 'https://git.example.com',
    });

    expect(mockPost).toHaveBeenCalledWith('/git/providers', {
      provider: {
        provider_type: 'gitea',
        name: 'Gitea',
        api_base_url: 'https://git.example.com',
      },
    });
  });

  it('omits api_base_url when apiBaseUrl is not given', async () => {
    mockPost.mockResolvedValueOnce({ data: { data: { provider: { id: 'prov-git-2' } } } });

    await onboardingApi.createGitProvider({ providerType: 'github', name: 'GitHub' });

    expect(mockPost).toHaveBeenCalledWith('/git/providers', {
      provider: { provider_type: 'github', name: 'GitHub' },
    });
  });
});

describe('onboardingApi.createGitCredential', () => {
  it('includes auth_type: personal_access_token in the credential payload', async () => {
    mockPost.mockResolvedValueOnce({ data: { data: { credential: { id: 'cred-git-1' } } } });

    await onboardingApi.createGitCredential({
      providerId: 'prov-git-1',
      credentials: { access_token: 'tok-abc' },
    });

    expect(mockPost).toHaveBeenCalledWith('/git/providers/prov-git-1/credentials', {
      credential: {
        name: 'Onboarding',
        auth_type: 'personal_access_token',
        credentials: { access_token: 'tok-abc' },
        is_active: true,
        is_default: true,
      },
    });
  });
});
