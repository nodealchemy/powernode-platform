// Git Provider Management Types

export interface GitProvider {
  id: string;
  name: string;
  slug: string;
  provider_type: 'github' | 'gitlab' | 'gitea';
  description?: string;
  api_base_url?: string;
  web_base_url?: string;
  is_active: boolean;
  supports_oauth: boolean;
  supports_pat: boolean;
  supports_webhooks: boolean;
  supports_ci_cd: boolean;
  capabilities: string[];
  priority_order: number;
  created_at: string;
}

export interface GitProviderDetail extends GitProvider {
  oauth_config?: Record<string, unknown>;
  webhook_config?: Record<string, unknown>;
  ci_cd_config?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  credentials_count: number;
}

export interface GitCredential {
  id: string;
  name: string;
  auth_type: 'oauth' | 'personal_access_token';
  provider_type: string;
  external_username?: string;
  external_avatar_url?: string;
  is_active: boolean;
  is_default: boolean;
  scopes: string[];
  last_used_at?: string;
  last_test_status?: string;
  last_sync_at?: string;
  expires_at?: string;
  created_at: string;
  repository_count?: number;
  stats: {
    success_count: number;
    failure_count: number;
    consecutive_failures: number;
    repositories_count: number;
  };
}

export interface GitCredentialDetail extends GitCredential {
  last_error?: string;
  last_test_at?: string;
  healthy: boolean;
  can_be_used: boolean;
  git_provider: GitProvider;
}

export interface GitRepository {
  id: string;
  name: string;
  full_name: string;
  owner: string;
  description?: string;
  default_branch: string;
  web_url?: string;
  is_private: boolean;
  is_fork: boolean;
  is_archived: boolean;
  webhook_configured: boolean;
  stars_count: number;
  forks_count: number;
  open_issues_count: number;
  open_prs_count: number;
  primary_language?: string;
  topics: string[];
  last_synced_at?: string;
  last_commit_at?: string;
  created_at: string;
  provider_type: string;
  credential_id: string;
}

export interface GitRepositoryDetail extends GitRepository {
  clone_url?: string;
  ssh_url?: string;
  languages?: Record<string, number>;
  sync_settings?: Record<string, unknown>;
  webhook_id?: string;
  provider_created_at?: string;
  provider_updated_at?: string;
  pipeline_stats?: PipelineStats;
  credential: {
    id: string;
    name: string;
    provider_name: string;
  };
}

export interface GitPipeline {
  id: string;
  external_id: string;
  name: string;
  status: 'pending' | 'running' | 'completed' | 'cancelled';
  conclusion?: 'success' | 'failure' | 'cancelled' | 'skipped' | 'timed_out';
  trigger_event?: string;
  ref?: string;
  branch_name?: string;
  sha?: string;
  short_sha?: string;
  actor_username?: string;
  web_url?: string;
  run_number?: number;
  run_attempt?: number;
  total_jobs: number;
  completed_jobs: number;
  failed_jobs: number;
  progress_percentage: number;
  duration_seconds?: number;
  duration_formatted?: string;
  started_at?: string;
  completed_at?: string;
  created_at: string;
}

export interface GitPipelineDetail extends GitPipeline {
  jobs: GitPipelineJob[];
  workflow_config?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export interface GitPipelineJob {
  id: string;
  external_id: string;
  name: string;
  status: 'pending' | 'running' | 'completed' | 'cancelled';
  conclusion?: string;
  step_number?: number;
  runner_name?: string;
  runner_os?: string;
  duration_seconds?: number;
  duration_formatted?: string;
  logs_available: boolean;
  completed_steps?: number;
  total_steps?: number;
  started_at?: string;
  completed_at?: string;
  created_at: string;
}

export interface GitPipelineJobDetail extends GitPipelineJob {
  logs_url?: string;
  steps?: PipelineStep[];
  outputs?: Record<string, unknown>;
  runner_info?: Record<string, unknown>;
  act_runner?: boolean;
}

export interface PipelineStep {
  name: string;
  status: string;
  conclusion?: string;
  number: number;
}

export interface GitWebhookEvent {
  id: string;
  event_type: string;
  action?: string;
  status: 'pending' | 'processing' | 'processed' | 'failed';
  delivery_id?: string;
  sender_username?: string;
  ref?: string;
  branch_name?: string;
  sha?: string;
  short_sha?: string;
  summary?: string;
  retry_count: number;
  retryable: boolean;
  processed_at?: string;
  created_at: string;
  repository?: {
    id: string;
    name: string;
    full_name: string;
  };
  provider: {
    id: string;
    name: string;
    type: string;
  };
}

export interface GitWebhookEventDetail extends GitWebhookEvent {
  payload: Record<string, unknown>;
  headers: Record<string, string>;
  error_message?: string;
  processing_result?: Record<string, unknown>;
  sender_info?: Record<string, unknown>;
}

export interface PipelineStats {
  total_runs: number;
  success_count: number;
  failed_count: number;
  cancelled_count: number;
  success_rate: number;
  avg_duration_seconds: number;
  runs_today: number;
  runs_this_week: number;
  active_runs: number;
}

export interface WebhookEventStats {
  total_events: number;
  pending: number;
  processed: number;
  failed: number;
  today_count: number;
  today_processed: number;
  today_failed: number;
}

export interface AvailableProvider {
  id: string;
  name: string;
  slug: string;
  provider_type: string;
  description?: string;
  supports_oauth: boolean;
  supports_pat: boolean;
  supports_ci_cd: boolean;
  capabilities: string[];
  configured: boolean;
}

export interface CreateCredentialData {
  name: string;
  auth_type: 'oauth' | 'personal_access_token';
  credentials: {
    access_token?: string;
    refresh_token?: string;
    expires_at?: string;
    api_base_url?: string; // For self-hosted providers like Gitea
    web_base_url?: string;
  };
  is_active?: boolean;
  is_default?: boolean;
  expires_at?: string;
}

export interface PaginationInfo {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

export interface GitProvidersResponse {
  providers: GitProvider[];
  count: number;
}

export interface GitRepositoriesResponse {
  repositories: GitRepository[];
  pagination: PaginationInfo;
}

export interface GitPipelinesResponse {
  pipelines: GitPipeline[];
  pagination: PaginationInfo;
  stats: PipelineStats;
}

export interface GitWebhookEventsResponse {
  events: GitWebhookEvent[];
  pagination: PaginationInfo;
  stats: WebhookEventStats;
}

export interface ConnectionTestResult {
  success: boolean;
  message?: string;
  error?: string;
  rate_limit?: {
    remaining: number;
    limit: number;
    reset_at?: string;
  };
  user_info?: {
    username: string;
    name?: string;
    avatar_url?: string;
  };
  scopes?: string[];
  capabilities?: string[];
}

export interface SyncRepositoriesResult {
  synced_count: number;
  error_count: number;
  repositories: Array<{
    id: string;
    name: string;
    full_name: string;
    is_private: boolean;
    webhook_configured: boolean;
  }>;
}

export interface CreateProviderData {
  name: string;
  provider_type: 'github' | 'gitlab' | 'gitea';
  description?: string;
  api_base_url?: string;
  web_base_url?: string;
  is_active?: boolean;
  supports_oauth?: boolean;
  supports_pat?: boolean;
  supports_webhooks?: boolean;
  supports_ci_cd?: boolean;
}

export interface UpdateProviderData {
  name?: string;
  description?: string;
  api_base_url?: string;
  web_base_url?: string;
  is_active?: boolean;
}
