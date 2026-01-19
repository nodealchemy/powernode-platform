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
  GitRunner,
  GitRunnerDetail,
  RunnerStats,
  RunnerRegistrationToken,
  RunnerRemovalToken,
  SyncRunnersResult,
  GitPipelineSchedule,
  GitPipelineScheduleDetail,
  CreateScheduleData,
  GitPipelineApproval,
  GitPipelineApprovalDetail,
  ApprovalStats,
  AvailableProvider,
  CreateCredentialData,
  CreateProviderData,
  UpdateProviderData,
  ConnectionTestResult,
  SyncRepositoriesResult,
  PaginationInfo,
  PipelineStats,
  WebhookEventStats,
  GitWorkflowTrigger,
  GitWorkflowTriggerDetail,
  CreateGitWorkflowTriggerData,
  TestGitTriggerResult,
  // Commit and diff types
  GitCommitDetail,
  GitDiff,
  GitCommitComparison,
  GitFileContent,
  GitTree,
  GitTag,
  GitBranch,
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
   * Get tags for a repository
   */
  getTags: async (
    id: string,
    params?: { page?: number; per_page?: number }
  ): Promise<GitTag[]> => {
    const response = await apiClient.get<ApiResponse<{
      tags: GitTag[];
    }>>(`/git/repositories/${id}/tags`, { params });
    return response.data.data?.tags || [];
  },

  // ================================
  // COMMIT & DIFF VIEWING
  // ================================

  /**
   * Get a specific commit with full details
   */
  getCommit: async (repositoryId: string, sha: string): Promise<GitCommitDetail> => {
    const response = await apiClient.get<ApiResponse<{
      commit: GitCommitDetail;
    }>>(`/git/repositories/${repositoryId}/commits/${sha}`);
    return response.data.data.commit;
  },

  /**
   * Get diff for a specific commit
   */
  getCommitDiff: async (repositoryId: string, sha: string): Promise<GitDiff> => {
    const response = await apiClient.get<ApiResponse<{
      diff: GitDiff;
    }>>(`/git/repositories/${repositoryId}/commits/${sha}/diff`);
    return response.data.data.diff;
  },

  /**
   * Compare two commits (diff between base and head)
   */
  compareCommits: async (
    repositoryId: string,
    base: string,
    head: string
  ): Promise<GitCommitComparison> => {
    const response = await apiClient.get<ApiResponse<{
      comparison: GitCommitComparison;
    }>>(`/git/repositories/${repositoryId}/compare/${base}...${head}`);
    return response.data.data.comparison;
  },

  /**
   * Get file content at a specific ref
   */
  getFileContent: async (
    repositoryId: string,
    path: string,
    ref?: string
  ): Promise<GitFileContent> => {
    const params = ref ? { ref } : {};
    const response = await apiClient.get<ApiResponse<{
      content: GitFileContent;
    }>>(`/git/repositories/${repositoryId}/contents/${path}`, { params });
    return response.data.data.content;
  },

  /**
   * Get repository tree (directory listing) at a specific ref
   */
  getTree: async (
    repositoryId: string,
    sha?: string,
    recursive?: boolean
  ): Promise<GitTree> => {
    const params: { recursive?: string } = {};
    if (recursive) params.recursive = 'true';
    const endpoint = sha
      ? `/git/repositories/${repositoryId}/tree/${sha}`
      : `/git/repositories/${repositoryId}/tree`;
    const response = await apiClient.get<ApiResponse<{
      tree: GitTree;
      commit_sha: string;
      path: string;
    }>>(endpoint, { params });
    return response.data.data.tree;
  },

  /**
   * Get branches with typed response
   */
  getBranchesTyped: async (
    id: string,
    params?: { page?: number; per_page?: number }
  ): Promise<GitBranch[]> => {
    const response = await apiClient.get<ApiResponse<{
      branches: GitBranch[];
    }>>(`/git/repositories/${id}/branches`, { params });
    return response.data.data?.branches || [];
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

  // ================================
  // RUNNERS (CI/CD Self-Hosted)
  // ================================

  /**
   * Get all runners
   */
  getRunners: async (params?: {
    page?: number;
    per_page?: number;
    status?: string;
    scope?: string;
    credential_id?: string;
    repository_id?: string;
    search?: string;
    sort?: string;
    direction?: 'asc' | 'desc';
  }): Promise<{
    runners: GitRunner[];
    stats: RunnerStats;
    pagination: PaginationInfo;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      runners: GitRunner[];
      stats: RunnerStats;
      pagination: PaginationInfo;
    }>>('/git/runners', { params });
    return response.data.data;
  },

  /**
   * Get a specific runner
   */
  getRunner: async (id: string): Promise<GitRunnerDetail> => {
    const response = await apiClient.get<ApiResponse<{
      runner: GitRunnerDetail;
    }>>(`/git/runners/${id}`);
    return response.data.data.runner;
  },

  /**
   * Delete a runner
   */
  deleteRunner: async (id: string): Promise<{ message: string }> => {
    const response = await apiClient.delete<ApiResponse<{
      message: string;
    }>>(`/git/runners/${id}`);
    return response.data.data;
  },

  /**
   * Sync runners from providers
   */
  syncRunners: async (params?: {
    credential_id?: string;
    repository_id?: string;
  }): Promise<SyncRunnersResult> => {
    const response = await apiClient.post<ApiResponse<SyncRunnersResult>>(
      '/git/runners/sync',
      params
    );
    return response.data.data;
  },

  /**
   * Get registration token for a runner
   */
  getRunnerRegistrationToken: async (
    id: string
  ): Promise<RunnerRegistrationToken> => {
    const response = await apiClient.post<ApiResponse<RunnerRegistrationToken>>(
      `/git/runners/${id}/registration_token`
    );
    return response.data.data;
  },

  /**
   * Get removal token for a runner
   */
  getRunnerRemovalToken: async (id: string): Promise<RunnerRemovalToken> => {
    const response = await apiClient.post<ApiResponse<RunnerRemovalToken>>(
      `/git/runners/${id}/removal_token`
    );
    return response.data.data;
  },

  /**
   * Update runner labels
   */
  updateRunnerLabels: async (
    id: string,
    labels: string[]
  ): Promise<GitRunnerDetail> => {
    const response = await apiClient.put<ApiResponse<{
      runner: GitRunnerDetail;
    }>>(`/git/runners/${id}/labels`, { labels });
    return response.data.data.runner;
  },

  // ================================
  // PIPELINE SCHEDULES
  // ================================

  /**
   * Get schedules for a repository
   */
  getSchedules: async (
    repositoryId: string,
    params?: {
      page?: number;
      per_page?: number;
      active?: boolean;
      status?: string;
      sort?: string;
      direction?: 'asc' | 'desc';
    }
  ): Promise<{
    schedules: GitPipelineSchedule[];
    pagination: PaginationInfo;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      schedules: GitPipelineSchedule[];
      pagination: PaginationInfo;
    }>>(`/git/repositories/${repositoryId}/schedules`, { params });
    return response.data.data;
  },

  /**
   * Get a specific schedule
   */
  getSchedule: async (id: string): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.get<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/pipeline_schedules/${id}`);
    return response.data.data.schedule;
  },

  /**
   * Create a new schedule
   */
  createSchedule: async (
    repositoryId: string,
    data: CreateScheduleData
  ): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.post<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/repositories/${repositoryId}/schedules`, { schedule: data });
    return response.data.data.schedule;
  },

  /**
   * Update a schedule
   */
  updateSchedule: async (
    id: string,
    data: Partial<CreateScheduleData>
  ): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.put<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/pipeline_schedules/${id}`, { schedule: data });
    return response.data.data.schedule;
  },

  /**
   * Delete a schedule
   */
  deleteSchedule: async (id: string): Promise<{ message: string }> => {
    const response = await apiClient.delete<ApiResponse<{
      message: string;
    }>>(`/git/pipeline_schedules/${id}`);
    return response.data.data;
  },

  /**
   * Trigger a schedule manually
   */
  triggerSchedule: async (id: string): Promise<{ message: string; pipeline_id?: string }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      pipeline_id?: string;
    }>>(`/git/pipeline_schedules/${id}/trigger`);
    return response.data.data;
  },

  /**
   * Pause a schedule
   */
  pauseSchedule: async (id: string): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.post<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/pipeline_schedules/${id}/pause`);
    return response.data.data.schedule;
  },

  /**
   * Resume a schedule
   */
  resumeSchedule: async (id: string): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.post<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/pipeline_schedules/${id}/resume`);
    return response.data.data.schedule;
  },

  // ================================
  // PIPELINE APPROVALS
  // ================================

  /**
   * Get all approvals
   */
  getApprovals: async (params?: {
    page?: number;
    per_page?: number;
    status?: string;
    environment?: string;
    pipeline_id?: string;
    sort?: string;
    direction?: 'asc' | 'desc';
  }): Promise<{
    approvals: GitPipelineApproval[];
    stats: ApprovalStats;
    pagination: PaginationInfo;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      approvals: GitPipelineApproval[];
      stats: ApprovalStats;
      pagination: PaginationInfo;
    }>>('/git/pipeline_approvals', { params });
    return response.data.data;
  },

  /**
   * Get pending approvals
   */
  getPendingApprovals: async (): Promise<{
    approvals: GitPipelineApproval[];
    count: number;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      approvals: GitPipelineApproval[];
      count: number;
    }>>('/git/pipeline_approvals/pending');
    return response.data.data;
  },

  /**
   * Get a specific approval
   */
  getApproval: async (id: string): Promise<GitPipelineApprovalDetail> => {
    const response = await apiClient.get<ApiResponse<{
      approval: GitPipelineApprovalDetail;
    }>>(`/git/pipeline_approvals/${id}`);
    return response.data.data.approval;
  },

  /**
   * Approve a pipeline request
   */
  approveRequest: async (
    id: string,
    comment?: string
  ): Promise<{ approval: GitPipelineApprovalDetail; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      approval: GitPipelineApprovalDetail;
      message: string;
    }>>(`/git/pipeline_approvals/${id}/approve`, { comment });
    return response.data.data;
  },

  /**
   * Reject a pipeline request
   */
  rejectRequest: async (
    id: string,
    comment?: string
  ): Promise<{ approval: GitPipelineApprovalDetail; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      approval: GitPipelineApprovalDetail;
      message: string;
    }>>(`/git/pipeline_approvals/${id}/reject`, { comment });
    return response.data.data;
  },

  /**
   * Cancel an approval request
   */
  cancelApprovalRequest: async (
    id: string
  ): Promise<{ approval: GitPipelineApprovalDetail; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      approval: GitPipelineApprovalDetail;
      message: string;
    }>>(`/git/pipeline_approvals/${id}/cancel`);
    return response.data.data;
  },

  // ================================
  // GIT WORKFLOW TRIGGERS (AI Integration)
  // ================================

  /**
   * Get git triggers for a workflow trigger
   */
  getWorkflowGitTriggers: async (
    triggerId: string
  ): Promise<GitWorkflowTrigger[]> => {
    const response = await apiClient.get<ApiResponse<{
      git_triggers: GitWorkflowTrigger[];
      count: number;
    }>>(`/ai/triggers/${triggerId}/git_triggers`);
    return response.data.data?.git_triggers || [];
  },

  /**
   * Get all git triggers for a workflow
   */
  getWorkflowAllGitTriggers: async (
    workflowId: string
  ): Promise<GitWorkflowTrigger[]> => {
    const response = await apiClient.get<ApiResponse<{
      git_triggers: GitWorkflowTrigger[];
      count: number;
    }>>(`/ai/workflows/${workflowId}/git_triggers`);
    return response.data.data?.git_triggers || [];
  },

  /**
   * Get a specific git trigger
   */
  getGitTrigger: async (
    triggerId: string,
    gitTriggerId: string
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.get<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}`);
    return response.data.data.git_trigger;
  },

  /**
   * Create a git workflow trigger
   */
  createGitTrigger: async (
    triggerId: string,
    data: CreateGitWorkflowTriggerData
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.post<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers`, { git_trigger: data });
    return response.data.data.git_trigger;
  },

  /**
   * Update a git workflow trigger
   */
  updateGitTrigger: async (
    triggerId: string,
    gitTriggerId: string,
    data: Partial<CreateGitWorkflowTriggerData>
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.put<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}`, { git_trigger: data });
    return response.data.data.git_trigger;
  },

  /**
   * Delete a git workflow trigger
   */
  deleteGitTrigger: async (
    triggerId: string,
    gitTriggerId: string
  ): Promise<{ message: string }> => {
    const response = await apiClient.delete<ApiResponse<{
      message: string;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}`);
    return response.data.data;
  },

  /**
   * Test a git trigger with sample payload
   */
  testGitTrigger: async (
    triggerId: string,
    gitTriggerId: string,
    samplePayload: Record<string, unknown>
  ): Promise<TestGitTriggerResult> => {
    const response = await apiClient.post<ApiResponse<TestGitTriggerResult>>(
      `/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}/test`,
      { sample_payload: samplePayload }
    );
    return response.data.data;
  },

  /**
   * Activate a git trigger
   */
  activateGitTrigger: async (
    triggerId: string,
    gitTriggerId: string
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.post<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}/activate`);
    return response.data.data.git_trigger;
  },

  /**
   * Pause a git trigger
   */
  pauseGitTrigger: async (
    triggerId: string,
    gitTriggerId: string
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.post<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}/pause`);
    return response.data.data.git_trigger;
  },
};
