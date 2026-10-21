import { onboardingApi } from './onboardingApi';

const mockGet = jest.fn();
const mockPost = jest.fn();
const mockDelete = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    delete: (...args: unknown[]) => mockDelete(...args),
  },
}));

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
});

describe('onboardingApi.createAiProvider', () => {
  it('always POSTs a new provider row (name deduplicated server-side), never reusing one', async () => {
    mockPost.mockResolvedValueOnce({ data: { data: { provider: { id: 'prov-created' } } } });

    const id = await onboardingApi.createAiProvider({ providerType: 'openai', name: 'OpenAI' });

    expect(id).toEqual({ id: 'prov-created', claimed: false });
    expect(mockGet).not.toHaveBeenCalled();
    expect(mockPost).toHaveBeenCalledWith('/ai/providers', {
      dedupe_name: true,
      provider: { provider_type: 'openai', name: 'OpenAI' },
    });
  });

  it('reports a claimed seeded row', async () => {
    mockPost.mockResolvedValueOnce({ data: { data: { provider: { id: 'prov-seed' }, claimed: true } } });

    const created = await onboardingApi.createAiProvider({ providerType: 'openai', name: 'OpenAI' });

    expect(created).toEqual({ id: 'prov-seed', claimed: true });
  });

  it('releases a claimed row', async () => {
    await onboardingApi.releaseAiProvider('prov-seed');

    expect(mockPost).toHaveBeenCalledWith('/ai/providers/prov-seed/release');
  });

  it('removes an AI provider the wizard created', async () => {
    await onboardingApi.deleteAiProvider('prov-9');

    expect(mockDelete).toHaveBeenCalledWith('/ai/providers/prov-9');
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

// fc-39: App.tsx's OnboardingGate read /onboarding/status inline; it now asks
// onboardingApi.isComplete. Fixtures are the real { success, data } envelope.
describe('onboardingApi.isComplete', () => {
  it('is true when the account completed onboarding', async () => {
    mockGet.mockResolvedValueOnce({ data: { success: true, data: { completed: true, has_credentials: false } } });

    await expect(onboardingApi.isComplete()).resolves.toBe(true);
    expect(mockGet).toHaveBeenCalledWith('/onboarding/status');
  });

  it('is true when credentials exist even without the completion stamp', async () => {
    mockGet.mockResolvedValueOnce({ data: { success: true, data: { completed: false, has_credentials: true } } });

    await expect(onboardingApi.isComplete()).resolves.toBe(true);
  });

  it('is false when neither is set', async () => {
    mockGet.mockResolvedValueOnce({ data: { success: true, data: { completed: false, has_credentials: false } } });

    await expect(onboardingApi.isComplete()).resolves.toBe(false);
  });
});
