import { gitProvidersApi, credentialsApi, repositoriesApi } from '../services/git';
import { apiClient } from '@/shared/services/apiClient';
import { AxiosHeaders } from 'axios';

// Mock the apiClient module
jest.mock('@/shared/services/apiClient');

const mockApiClient = jest.mocked(apiClient);

// Helper to create proper AxiosResponse mock
const mockAxiosResponse = <T>(data: T) => ({
  data,
  status: 200,
  statusText: 'OK',
  headers: {},
  config: { headers: new AxiosHeaders() },
});

// fc-24: was gitProvidersApi.test.ts, testing the unified spread-barrel of
// the same name. The barrel was a shim (a pure `{...gitProvidersApi,
// ...credentialsApi, ...}` merge with no behaviour of its own) and is
// deleted; these assertions carry the same HTTP-contract coverage forward
// against each domain API directly — nothing here is new or lost.
describe('git domain APIs (providers/credentials/repositories/pipelines/webhooks)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // =============================================================================
  // PROVIDERS
  // =============================================================================

  describe('getProviders', () => {
    it('fetches list of providers', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            providers: [
              { id: 'provider-1', name: 'GitHub', provider_type: 'github' },
              { id: 'provider-2', name: 'GitLab', provider_type: 'gitlab' },
            ],
            count: 2,
          },
        })
      );

      const result = await gitProvidersApi.getProviders();

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/providers');
      expect(result).toHaveLength(2);
      expect(result[0].name).toBe('GitHub');
    });

    it('returns empty array when no providers', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({ success: true, data: { providers: null, count: 0 } })
      );

      const result = await gitProvidersApi.getProviders();

      expect(result).toEqual([]);
    });
  });

  describe('getProvider', () => {
    it('fetches single provider details', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            provider: {
              id: 'provider-1',
              name: 'GitHub',
              provider_type: 'github',
              capabilities: ['repos', 'branches', 'webhooks'],
            },
          },
        })
      );

      const result = await gitProvidersApi.getProvider('provider-1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/providers/provider-1');
      expect(result.name).toBe('GitHub');
      expect(result.capabilities).toContain('repos');
    });
  });

  describe('getAvailableProviders', () => {
    it('fetches available providers for connection', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            providers: [
              { id: 'github', name: 'GitHub', provider_type: 'github', supports_oauth: true },
              { id: 'gitlab', name: 'GitLab', provider_type: 'gitlab', supports_oauth: true },
              { id: 'gitea', name: 'Gitea', provider_type: 'gitea', supports_pat: true },
            ],
          },
        })
      );

      const result = await gitProvidersApi.getAvailableProviders();

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/providers/available');
      expect(result).toHaveLength(3);
    });
  });

  // =============================================================================
  // CREDENTIALS
  // =============================================================================

  describe('getCredentials', () => {
    it('fetches credentials for a provider', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            credentials: [
              { id: 'cred-1', name: 'My GitHub Token', is_default: true },
              { id: 'cred-2', name: 'Work Token', is_default: false },
            ],
            count: 2,
          },
        })
      );

      const result = await credentialsApi.getCredentials('provider-1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/providers/provider-1/credentials');
      expect(result).toHaveLength(2);
    });
  });

  describe('createCredential', () => {
    it('creates a new credential', async () => {
      mockApiClient.post.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            credential: {
              id: 'cred-new',
              name: 'New Token',
              is_default: true,
            },
          },
        })
      );

      const result = await credentialsApi.createCredential('provider-1', {
        name: 'New Token',
        auth_type: 'personal_access_token',
        credentials: { access_token: 'ghp_test123' },
      });

      expect(mockApiClient.post).toHaveBeenCalledWith('/git/providers/provider-1/credentials', {
        credential: {
          name: 'New Token',
          auth_type: 'personal_access_token',
          credentials: { access_token: 'ghp_test123' },
        },
      });
      expect(result.name).toBe('New Token');
    });
  });

  describe('testCredential', () => {
    it('tests a credential connection', async () => {
      mockApiClient.post.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            success: true,
            response_time_ms: 150.5,
            user: { login: 'testuser' },
          },
        })
      );

      const result = await credentialsApi.testCredential('provider-1', 'cred-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/git/providers/provider-1/credentials/cred-1/test'
      );
      expect(result.success).toBe(true);
    });
  });

  describe('makeDefaultCredential', () => {
    it('makes a credential the default', async () => {
      mockApiClient.post.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            credential: { id: 'cred-1', is_default: true },
          },
        })
      );

      const result = await credentialsApi.makeDefaultCredential('provider-1', 'cred-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/git/providers/provider-1/credentials/cred-1/make_default'
      );
      expect(result.is_default).toBe(true);
    });
  });

  describe('deleteCredential', () => {
    it('deletes a credential', async () => {
      mockApiClient.delete.mockResolvedValue(mockAxiosResponse({ success: true, data: {} }));

      await credentialsApi.deleteCredential('provider-1', 'cred-1');

      expect(mockApiClient.delete).toHaveBeenCalledWith(
        '/git/providers/provider-1/credentials/cred-1'
      );
    });
  });

  // =============================================================================
  // REPOSITORIES
  // =============================================================================

  describe('getRepositories', () => {
    it('fetches list of repositories', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            repositories: [
              { id: 'repo-1', name: 'project-a', full_name: 'org/project-a' },
              { id: 'repo-2', name: 'project-b', full_name: 'org/project-b' },
            ],
            pagination: { current_page: 1, total_pages: 1, total_count: 2 },
          },
        })
      );

      const result = await repositoriesApi.getRepositories();

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/repositories', { params: undefined });
      expect(result.repositories).toHaveLength(2);
    });

    it('filters by credential_id', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            repositories: [{ id: 'repo-1', name: 'project-a' }],
            pagination: { current_page: 1, total_pages: 1, total_count: 1 },
          },
        })
      );

      await repositoriesApi.getRepositories({ credential_id: 'cred-1' });

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/repositories', {
        params: { credential_id: 'cred-1' },
      });
    });
  });

  describe('configureWebhook', () => {
    it('configures webhook for repository', async () => {
      mockApiClient.post.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            repository: { id: 'repo-1', webhook_configured: true },
            message: 'Webhook configured successfully',
          },
        })
      );

      const result = await repositoriesApi.configureWebhook('repo-1');

      expect(mockApiClient.post).toHaveBeenCalledWith('/git/repositories/repo-1/configure_webhook', undefined);
      expect(result.repository.webhook_configured).toBe(true);
    });
  });

  describe('removeWebhook', () => {
    it('removes webhook from repository', async () => {
      mockApiClient.delete.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            repository: { id: 'repo-1', webhook_configured: false },
            message: 'Webhook removed successfully',
          },
        })
      );

      const result = await repositoriesApi.removeWebhook('repo-1');

      expect(mockApiClient.delete).toHaveBeenCalledWith('/git/repositories/repo-1/remove_webhook');
      expect(result.repository.webhook_configured).toBe(false);
    });
  });

  describe('repository import (IMP-93dffbd1868c)', () => {
    it('offers only the available + import flow, not the deleted syncRepositories', () => {
      expect('syncRepositories' in credentialsApi).toBe(false);
      expect(typeof credentialsApi.getAvailableRepositories).toBe('function');
      expect(typeof credentialsApi.importRepositories).toBe('function');
    });
  });
});
