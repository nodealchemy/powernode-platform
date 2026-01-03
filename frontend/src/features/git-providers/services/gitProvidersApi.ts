import { apiClient } from '@/shared/services/apiClient';
import {
  GitProvider,
  GitProviderDetail,
  GitCredential,
  GitCredentialDetail,
  GitRepository,
  GitRepositoryDetail,
  GitPipeline,
  GitPipelineDetail,
  GitPipelineJob,
  GitPipelineJobDetail,
  GitWebhookEvent,
  GitWebhookEventDetail,
  AvailableProvider,
  CreateCredentialData,
  CreateProviderData,
  UpdateProviderData,
  ConnectionTestResult,
  SyncRepositoriesResult,
  PaginationInfo,
  PipelineStats,
  WebhookEventStats,
} from '../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

// ================================
// PROVIDERS
// ================================

export const gitProvidersApi = {
  /**
   * Get all available Git providers
   */
  getProviders: async (): Promise<GitProvider[]> => {
    const response = await apiClient.get<ApiResponse<{
      providers: GitProvider[];
      count: number;
    }>>('/git/providers');
    return response.data.data?.providers || [];
  },

  /**
   * Get available providers with configuration status
   */
  getAvailableProviders: async (): Promise<AvailableProvider[]> => {
    const response = await apiClient.get<ApiResponse<{
      providers: AvailableProvider[];
    }>>('/git/providers/available');
    return response.data.data?.providers || [];
  },

  /**
   * Get a specific provider by ID
   */
  getProvider: async (id: string): Promise<GitProviderDetail> => {
    const response = await apiClient.get<ApiResponse<{
      provider: GitProviderDetail;
    }>>(`/git/providers/${id}`);
    return response.data.data.provider;
  },

  /**
   * Create a new Git provider
   */
  createProvider: async (data: CreateProviderData): Promise<GitProviderDetail> => {
    const response = await apiClient.post<ApiResponse<{
      provider: GitProviderDetail;
    }>>('/git/providers', { provider: data });
    return response.data.data.provider;
  },

  /**
   * Update an existing Git provider
   */
  updateProvider: async (
    id: string,
    data: UpdateProviderData
  ): Promise<GitProviderDetail> => {
    const response = await apiClient.patch<ApiResponse<{
      provider: GitProviderDetail;
    }>>(`/git/providers/${id}`, { provider: data });
    return response.data.data.provider;
  },

  /**
   * Delete a Git provider
   */
  deleteProvider: async (id: string): Promise<void> => {
    await apiClient.delete(`/git/providers/${id}`);
  },

  // ================================
  // CREDENTIALS
  // ================================

  /**
   * Get credentials for a provider
   */
  getCredentials: async (providerId: string): Promise<GitCredential[]> => {
    const response = await apiClient.get<ApiResponse<{
      credentials: GitCredential[];
      count: number;
    }>>(`/git/providers/${providerId}/credentials`);
    return response.data.data?.credentials || [];
  },

  /**
   * Get a specific credential
   */
  getCredential: async (
    providerId: string,
    credentialId: string
  ): Promise<GitCredentialDetail> => {
    const response = await apiClient.get<ApiResponse<{
      credential: GitCredentialDetail;
    }>>(`/git/providers/${providerId}/credentials/${credentialId}`);
    return response.data.data.credential;
  },

  /**
   * Create a new credential
   */
  createCredential: async (
    providerId: string,
    data: CreateCredentialData,
    autoSync = true
  ): Promise<GitCredentialDetail> => {
    const response = await apiClient.post<ApiResponse<{
      credential: GitCredentialDetail;
    }>>(`/git/providers/${providerId}/credentials`, {
      credential: data,
      auto_sync: autoSync,
    });
    return response.data.data.credential;
  },

  /**
   * Update a credential
   */
  updateCredential: async (
    providerId: string,
    credentialId: string,
    data: Partial<{
      name: string;
      is_active: boolean;
      is_default: boolean;
      credentials?: { access_token?: string };
    }>
  ): Promise<GitCredentialDetail> => {
    const response = await apiClient.patch<ApiResponse<{
      credential: GitCredentialDetail;
    }>>(`/git/providers/${providerId}/credentials/${credentialId}`, {
      credential: data,
    });
    return response.data.data.credential;
  },

  /**
   * Delete a credential
   */
  deleteCredential: async (
    providerId: string,
    credentialId: string
  ): Promise<void> => {
    await apiClient.delete(
      `/git/providers/${providerId}/credentials/${credentialId}`
    );
  },

  /**
   * Test a credential connection
   */
  testCredential: async (
    providerId: string,
    credentialId: string
  ): Promise<ConnectionTestResult> => {
    const response = await apiClient.post<ApiResponse<ConnectionTestResult>>(
      `/git/providers/${providerId}/credentials/${credentialId}/test`
    );
    return response.data.data;
  },

  /**
   * Make a credential the default
   */
  makeDefaultCredential: async (
    providerId: string,
    credentialId: string
  ): Promise<GitCredential> => {
    const response = await apiClient.post<ApiResponse<{
      credential: GitCredential;
    }>>(`/git/providers/${providerId}/credentials/${credentialId}/make_default`);
    return response.data.data.credential;
  },

  /**
   * Sync repositories for a credential
   */
  syncRepositories: async (
    providerId: string,
    credentialId: string,
    options?: { include_archived?: boolean; include_forks?: boolean }
  ): Promise<SyncRepositoriesResult> => {
    const response = await apiClient.post<ApiResponse<SyncRepositoriesResult>>(
      `/git/providers/${providerId}/credentials/${credentialId}/sync_repositories`,
      options
    );
    return response.data.data;
  },

  // ================================
  // REPOSITORIES
  // ================================

  /**
   * Get all repositories
   */
  getRepositories: async (params?: {
    page?: number;
    per_page?: number;
    search?: string;
    provider_id?: string;
    credential_id?: string;
    is_private?: boolean;
    webhook_configured?: boolean;
    language?: string;
    sort_by?: string;
    sort_order?: 'asc' | 'desc';
  }): Promise<{
    repositories: GitRepository[];
    pagination: PaginationInfo;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      repositories: GitRepository[];
      pagination: PaginationInfo;
    }>>('/git/repositories', { params });
    return response.data.data;
  },

  /**
   * Get a specific repository
   */
  getRepository: async (id: string): Promise<GitRepositoryDetail> => {
    const response = await apiClient.get<ApiResponse<{
      repository: GitRepositoryDetail;
    }>>(`/git/repositories/${id}`);
    return response.data.data.repository;
  },

  /**
   * Delete a repository
   */
  deleteRepository: async (id: string): Promise<void> => {
    await apiClient.delete(`/git/repositories/${id}`);
  },

  /**
   * Configure webhook for a repository
   */
  configureWebhook: async (
    id: string
  ): Promise<{ repository: GitRepository; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      repository: GitRepository;
      message: string;
    }>>(`/git/repositories/${id}/webhook/configure`);
    return response.data.data;
  },

  /**
   * Remove webhook from a repository
   */
  removeWebhook: async (
    id: string
  ): Promise<{ repository: GitRepository; message: string }> => {
    const response = await apiClient.delete<ApiResponse<{
      repository: GitRepository;
      message: string;
    }>>(`/git/repositories/${id}/webhook`);
    return response.data.data;
  },

  /**
   * Get branches for a repository
   */
  getBranches: async (
    id: string,
    params?: { page?: number; per_page?: number }
  ): Promise<unknown[]> => {
    const response = await apiClient.get<ApiResponse<{
      branches: unknown[];
    }>>(`/git/repositories/${id}/branches`, { params });
    return response.data.data?.branches || [];
  },

  /**
   * Get commits for a repository
   */
  getCommits: async (
    id: string,
    params?: {
      page?: number;
      per_page?: number;
      sha?: string;
      since?: string;
      until?: string;
    }
  ): Promise<unknown[]> => {
    const response = await apiClient.get<ApiResponse<{
      commits: unknown[];
    }>>(`/git/repositories/${id}/commits`, { params });
    return response.data.data?.commits || [];
  },

  /**
   * Get pull requests for a repository
   */
  getPullRequests: async (
    id: string,
    params?: { page?: number; per_page?: number; state?: string }
  ): Promise<unknown[]> => {
    const response = await apiClient.get<ApiResponse<{
      pull_requests: unknown[];
    }>>(`/git/repositories/${id}/pull_requests`, { params });
    return response.data.data?.pull_requests || [];
  },

  /**
   * Get issues for a repository
   */
  getIssues: async (
    id: string,
    params?: { page?: number; per_page?: number; state?: string }
  ): Promise<unknown[]> => {
    const response = await apiClient.get<ApiResponse<{
      issues: unknown[];
    }>>(`/git/repositories/${id}/issues`, { params });
    return response.data.data?.issues || [];
  },

  /**
   * Sync pipelines for a repository
   */
  syncPipelines: async (
    id: string
  ): Promise<{ synced_count: number; pipelines: GitPipeline[] }> => {
    const response = await apiClient.post<ApiResponse<{
      synced_count: number;
      pipelines: GitPipeline[];
    }>>(`/git/repositories/${id}/sync_pipelines`);
    return response.data.data;
  },

  // ================================
  // PIPELINES
  // ================================

  /**
   * Get pipelines for a repository
   */
  getPipelines: async (
    repositoryId: string,
    params?: {
      page?: number;
      per_page?: number;
      status?: string;
      conclusion?: string;
      ref?: string;
    }
  ): Promise<{
    pipelines: GitPipeline[];
    pagination: PaginationInfo;
    stats: PipelineStats;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      pipelines: GitPipeline[];
      pagination: PaginationInfo;
      stats: PipelineStats;
    }>>(`/git/repositories/${repositoryId}/pipelines`, { params });
    return response.data.data;
  },

  /**
   * Get a specific pipeline
   */
  getPipeline: async (
    repositoryId: string,
    pipelineId: string
  ): Promise<GitPipelineDetail> => {
    const response = await apiClient.get<ApiResponse<{
      pipeline: GitPipelineDetail;
    }>>(`/git/repositories/${repositoryId}/pipelines/${pipelineId}`);
    return response.data.data.pipeline;
  },

  /**
   * Trigger a pipeline
   */
  triggerPipeline: async (
    repositoryId: string,
    options?: {
      ref?: string;
      workflow_id?: string;
      inputs?: Record<string, string>;
    }
  ): Promise<{ message: string; pipeline_id?: string }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      pipeline_id?: string;
    }>>(`/git/repositories/${repositoryId}/pipelines/trigger`, options);
    return response.data.data;
  },

  /**
   * Cancel a pipeline
   */
  cancelPipeline: async (
    repositoryId: string,
    pipelineId: string
  ): Promise<{ message: string }> => {
    const response = await apiClient.post<ApiResponse<{ message: string }>>(
      `/git/repositories/${repositoryId}/pipelines/${pipelineId}/cancel`
    );
    return response.data.data;
  },

  /**
   * Retry a pipeline
   */
  retryPipeline: async (
    repositoryId: string,
    pipelineId: string
  ): Promise<{ message: string; new_pipeline_id?: string }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      new_pipeline_id?: string;
    }>>(`/git/repositories/${repositoryId}/pipelines/${pipelineId}/retry`);
    return response.data.data;
  },

  /**
   * Get jobs for a pipeline
   */
  getPipelineJobs: async (
    repositoryId: string,
    pipelineId: string
  ): Promise<GitPipelineJob[]> => {
    const response = await apiClient.get<ApiResponse<{
      jobs: GitPipelineJob[];
      count: number;
    }>>(`/git/repositories/${repositoryId}/pipelines/${pipelineId}/jobs`);
    return response.data.data?.jobs || [];
  },

  /**
   * Get a specific job
   */
  getJob: async (
    repositoryId: string,
    pipelineId: string,
    jobId: string
  ): Promise<GitPipelineJobDetail> => {
    const response = await apiClient.get<ApiResponse<{
      job: GitPipelineJobDetail;
    }>>(
      `/git/repositories/${repositoryId}/pipelines/${pipelineId}/jobs/${jobId}`
    );
    return response.data.data.job;
  },

  /**
   * Get job logs
   */
  getJobLogs: async (
    repositoryId: string,
    pipelineId: string,
    jobId: string
  ): Promise<{ job_id: string; logs: string; is_complete: boolean }> => {
    const response = await apiClient.get<ApiResponse<{
      job_id: string;
      logs: string;
      is_complete: boolean;
    }>>(
      `/git/repositories/${repositoryId}/pipelines/${pipelineId}/jobs/${jobId}/logs`
    );
    return response.data.data;
  },

  // ================================
  // WEBHOOK EVENTS
  // ================================

  /**
   * Get webhook events
   */
  getWebhookEvents: async (params?: {
    page?: number;
    per_page?: number;
    event_type?: string;
    status?: string;
    repository_id?: string;
    provider_id?: string;
    since?: string;
    until?: string;
  }): Promise<{
    events: GitWebhookEvent[];
    pagination: PaginationInfo;
    stats: WebhookEventStats;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      events: GitWebhookEvent[];
      pagination: PaginationInfo;
      stats: WebhookEventStats;
    }>>('/git/webhook_events', { params });
    return response.data.data;
  },

  /**
   * Get a specific webhook event
   */
  getWebhookEvent: async (id: string): Promise<GitWebhookEventDetail> => {
    const response = await apiClient.get<ApiResponse<{
      event: GitWebhookEventDetail;
    }>>(`/git/webhook_events/${id}`);
    return response.data.data.event;
  },

  /**
   * Retry a webhook event
   */
  retryWebhookEvent: async (
    id: string
  ): Promise<{ message: string; event: GitWebhookEvent }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      event: GitWebhookEvent;
    }>>(`/git/webhook_events/${id}/retry`);
    return response.data.data;
  },
};
