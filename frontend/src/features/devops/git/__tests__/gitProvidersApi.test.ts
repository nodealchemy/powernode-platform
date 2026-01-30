import { gitProvidersApi } from '../services/gitProvidersApi';
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

describe('gitProvidersApi', () => {
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

      const result = await gitProvidersApi.getCredentials('provider-1');

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

      const result = await gitProvidersApi.createCredential('provider-1', {
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

      const result = await gitProvidersApi.testCredential('provider-1', 'cred-1');

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

      const result = await gitProvidersApi.makeDefaultCredential('provider-1', 'cred-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/git/providers/provider-1/credentials/cred-1/make_default'
      );
      expect(result.is_default).toBe(true);
    });
  });

  describe('deleteCredential', () => {
    it('deletes a credential', async () => {
      mockApiClient.delete.mockResolvedValue(mockAxiosResponse({ success: true, data: {} }));

      await gitProvidersApi.deleteCredential('provider-1', 'cred-1');

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

      const result = await gitProvidersApi.getRepositories();

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

      await gitProvidersApi.getRepositories({ credential_id: 'cred-1' });

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

      const result = await gitProvidersApi.configureWebhook('repo-1');

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

      const result = await gitProvidersApi.removeWebhook('repo-1');

      expect(mockApiClient.delete).toHaveBeenCalledWith('/git/repositories/repo-1/remove_webhook');
      expect(result.repository.webhook_configured).toBe(false);
    });
  });

  describe('syncRepositories', () => {
    it('triggers repository sync', async () => {
      mockApiClient.post.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            synced_count: 5,
            new_repositories: 2,
            updated_repositories: 3,
          },
        })
      );

      const result = await gitProvidersApi.syncRepositories('provider-1', 'cred-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/git/providers/provider-1/credentials/cred-1/sync_repositories',
        undefined
      );
      expect(result.synced_count).toBe(5);
    });
  });

  // =============================================================================
  // PIPELINES
  // =============================================================================

  describe('getPipelines', () => {
    it('fetches list of pipelines', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            pipelines: [
              { id: 'pipeline-1', name: 'CI', status: 'completed' },
              { id: 'pipeline-2', name: 'Deploy', status: 'running' },
            ],
            pagination: { current_page: 1, total_pages: 1, total_count: 2 },
            stats: { total: 2, completed: 1, running: 1 },
          },
        })
      );

      const result = await gitProvidersApi.getPipelines('repo-1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/repositories/repo-1/pipelines', {
        params: undefined,
      });
      expect(result.pipelines).toHaveLength(2);
    });

    it('filters by status', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            pipelines: [{ id: 'pipeline-1', status: 'running' }],
            pagination: { current_page: 1, total_pages: 1, total_count: 1 },
            stats: { total: 1, running: 1 },
          },
        })
      );

      await gitProvidersApi.getPipelines('repo-1', { status: 'running' });

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/repositories/repo-1/pipelines', {
        params: { status: 'running' },
      });
    });
  });

  describe('cancelPipeline', () => {
    it('cancels a running pipeline', async () => {
      mockApiClient.post.mockResolvedValue(
        mockAxiosResponse({ success: true, data: { message: 'Pipeline cancelled successfully' } })
      );

      const result = await gitProvidersApi.cancelPipeline('repo-1', 'pipeline-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/git/repositories/repo-1/pipelines/pipeline-1/cancel'
      );
      expect(result.message).toContain('cancelled');
    });
  });

  describe('retryPipeline', () => {
    it('retries a failed pipeline', async () => {
      mockApiClient.post.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: { message: 'Pipeline retry initiated', new_pipeline_id: 'pipeline-2' },
        })
      );

      const result = await gitProvidersApi.retryPipeline('repo-1', 'pipeline-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/git/repositories/repo-1/pipelines/pipeline-1/retry'
      );
      expect(result.new_pipeline_id).toBe('pipeline-2');
    });
  });

  describe('getPipelineJobs', () => {
    it('fetches jobs for a pipeline', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            jobs: [
              { id: 'job-1', name: 'build', status: 'completed' },
              { id: 'job-2', name: 'test', status: 'running' },
            ],
            count: 2,
          },
        })
      );

      const result = await gitProvidersApi.getPipelineJobs('repo-1', 'pipeline-1');

      expect(mockApiClient.get).toHaveBeenCalledWith(
        '/git/repositories/repo-1/pipelines/pipeline-1/jobs'
      );
      expect(result).toHaveLength(2);
    });
  });

  describe('getJobLogs', () => {
    it('fetches logs for a job', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            job_id: 'job-1',
            logs: 'Step 1: Installing dependencies...\nStep 2: Running tests...',
            is_complete: true,
          },
        })
      );

      const result = await gitProvidersApi.getJobLogs('repo-1', 'pipeline-1', 'job-1');

      expect(mockApiClient.get).toHaveBeenCalledWith(
        '/git/repositories/repo-1/pipelines/pipeline-1/jobs/job-1/logs'
      );
      expect(result.logs).toContain('Installing dependencies');
      expect(result.is_complete).toBe(true);
    });
  });

  // =============================================================================
  // WEBHOOK EVENTS
  // =============================================================================

  describe('getWebhookEvents', () => {
    it('fetches webhook events', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            events: [
              { id: 'event-1', event_type: 'push', status: 'processed' },
              { id: 'event-2', event_type: 'pull_request', status: 'pending' },
            ],
            pagination: { current_page: 1, total_pages: 1, total_count: 2 },
            stats: { total: 2, processed: 1, pending: 1 },
          },
        })
      );

      const result = await gitProvidersApi.getWebhookEvents();

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/webhook_events', { params: undefined });
      expect(result.events).toHaveLength(2);
    });

    it('filters by event_type and status', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            events: [{ id: 'event-1', event_type: 'push', status: 'processed' }],
            pagination: { current_page: 1, total_pages: 1, total_count: 1 },
            stats: { total: 1, processed: 1 },
          },
        })
      );

      await gitProvidersApi.getWebhookEvents({ event_type: 'push', status: 'processed' });

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/webhook_events', {
        params: { event_type: 'push', status: 'processed' },
      });
    });
  });

  describe('getWebhookEvent', () => {
    it('fetches single webhook event', async () => {
      mockApiClient.get.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            event: {
              id: 'event-1',
              event_type: 'push',
              status: 'processed',
              payload: { ref: 'refs/heads/main' },
            },
          },
        })
      );

      const result = await gitProvidersApi.getWebhookEvent('event-1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/git/webhook_events/event-1');
      expect(result.event_type).toBe('push');
    });
  });

  describe('retryWebhookEvent', () => {
    it('retries a webhook event', async () => {
      mockApiClient.post.mockResolvedValue(
        mockAxiosResponse({
          success: true,
          data: {
            message: 'Event retry initiated',
            event: { id: 'event-1', status: 'pending' },
          },
        })
      );

      const result = await gitProvidersApi.retryWebhookEvent('event-1');

      expect(mockApiClient.post).toHaveBeenCalledWith('/git/webhook_events/event-1/retry');
      expect(result.event.status).toBe('pending');
    });
  });
});
