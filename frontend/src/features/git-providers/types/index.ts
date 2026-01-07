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

// Git Runner Types (CI/CD Self-Hosted Runners)

export type RunnerStatus = 'online' | 'offline' | 'busy';
export type RunnerScope = 'repository' | 'organization' | 'enterprise';

export interface GitRunner {
  id: string;
  external_id: string;
  name: string;
  status: RunnerStatus;
  busy: boolean;
  runner_scope: RunnerScope;
  labels: string[];
  os?: string;
  architecture?: string;
  version?: string;
  success_rate: number;
  total_jobs_run: number;
  last_seen_at?: string;
  provider_type: string;
  repository_id?: string;
  credential_id: string;
}

export interface GitRunnerDetail extends GitRunner {
  successful_jobs: number;
  failed_jobs: number;
  failure_rate: number;
  recently_active: boolean;
  repository?: {
    id: string;
    name: string;
    full_name: string;
  };
  created_at: string;
  updated_at: string;
}

export interface RunnerStats {
  total: number;
  online: number;
  offline: number;
  busy: number;
}

export interface GitRunnersResponse {
  runners: GitRunner[];
  stats: RunnerStats;
  pagination: PaginationInfo;
}

export interface RunnerRegistrationToken {
  token: string;
  expires_at?: string;
}

export interface RunnerRemovalToken {
  token: string;
  expires_at?: string;
}

export interface SyncRunnersResult {
  message: string;
  synced_count: number;
}

// Git Pipeline Schedule Types

export interface GitPipelineSchedule {
  id: string;
  name: string;
  cron_expression: string;
  timezone: string;
  ref: string;
  workflow_file?: string;
  is_active: boolean;
  next_run_at?: string;
  last_run_at?: string;
  last_run_status?: 'success' | 'failure' | 'skipped';
  run_count: number;
  success_rate: number;
  repository_id: string;
}

export interface GitPipelineScheduleDetail extends GitPipelineSchedule {
  description?: string;
  inputs: Record<string, string>;
  success_count: number;
  failure_count: number;
  consecutive_failures: number;
  human_schedule: string;
  next_runs: string[];
  overdue: boolean;
  last_pipeline_id?: string;
  created_by_id?: string;
  repository: {
    id: string;
    name: string;
    full_name: string;
  };
  created_at: string;
  updated_at: string;
}

export interface GitPipelineSchedulesResponse {
  schedules: GitPipelineSchedule[];
  pagination: PaginationInfo;
}

export interface CreateScheduleData {
  name: string;
  cron_expression: string;
  timezone: string;
  ref: string;
  description?: string;
  workflow_file?: string;
  inputs?: Record<string, string>;
  is_active?: boolean;
}

// Git Pipeline Approval Types

export type ApprovalStatus = 'pending' | 'approved' | 'rejected' | 'expired' | 'cancelled';

export interface GitPipelineApproval {
  id: string;
  gate_name: string;
  environment?: string;
  status: ApprovalStatus;
  expires_at?: string;
  responded_at?: string;
  can_respond: boolean;
  can_user_approve: boolean;
  pipeline: {
    id: string;
    name: string;
    status: string;
  };
  requested_by?: {
    id: string;
    name: string;
    email: string;
  };
  created_at: string;
}

export interface GitPipelineApprovalDetail extends GitPipelineApproval {
  description?: string;
  response_comment?: string;
  metadata: Record<string, unknown>;
  required_approvers: string[];
  time_until_expiry?: number;
  response_time?: number;
  responded_by?: {
    id: string;
    name: string;
    email: string;
  };
  repository?: {
    id: string;
    name: string;
    full_name: string;
  };
  updated_at: string;
}

export interface ApprovalStats {
  total: number;
  pending: number;
  approved: number;
  rejected: number;
  expired: number;
}

export interface GitPipelineApprovalsResponse {
  approvals: GitPipelineApproval[];
  stats: ApprovalStats;
  pagination: PaginationInfo;
}

// Git Workflow Trigger Types (AI Workflow Integration)

export type GitWorkflowTriggerStatus = 'active' | 'paused' | 'disabled' | 'error';

export type GitEventType =
  | 'push'
  | 'pull_request'
  | 'pull_request_review'
  | 'pull_request_comment'
  | 'issue'
  | 'issue_comment'
  | 'commit_comment'
  | 'create'
  | 'delete'
  | 'fork'
  | 'release'
  | 'tag'
  | 'workflow_run'
  | 'check_run'
  | 'check_suite'
  | 'deployment'
  | 'deployment_status'
  | 'status'
  | 'merge_group';

export interface GitWorkflowTrigger {
  id: string;
  event_type: GitEventType;
  branch_pattern: string;
  path_pattern?: string;
  is_active: boolean;
  status: GitWorkflowTriggerStatus;
  trigger_count: number;
  last_triggered_at?: string;
  ai_workflow_trigger_id: string;
  git_repository_id?: string;
  created_at: string;
}

export interface GitWorkflowTriggerDetail extends GitWorkflowTrigger {
  event_filters: Record<string, unknown>;
  payload_mapping: Record<string, string>;
  metadata: Record<string, unknown>;
  ai_workflow: {
    id: string;
    name: string;
    status: string;
  };
  ai_workflow_trigger: {
    id: string;
    name: string;
    trigger_type: string;
  };
  git_repository?: {
    id: string;
    name: string;
    full_name: string;
  };
  updated_at: string;
}

export interface CreateGitWorkflowTriggerData {
  event_type: GitEventType;
  branch_pattern: string;
  path_pattern?: string;
  event_filters?: Record<string, unknown>;
  payload_mapping?: Record<string, string>;
  git_repository_id?: string;
  is_active?: boolean;
}

export interface GitWorkflowTriggersResponse {
  git_triggers: GitWorkflowTrigger[];
  pagination?: PaginationInfo;
}

export interface TestGitTriggerResult {
  matched: boolean;
  extracted_variables: Record<string, unknown>;
  match_details: {
    event_type_match: boolean;
    branch_match: boolean;
    path_match: boolean;
    filters_match: boolean;
  };
}

// =============================================================================
// Git Commit and Diff Types (Comprehensive Git Viewing)
// =============================================================================

/**
 * Basic commit author/committer information
 */
export interface GitCommitAuthor {
  name: string;
  email: string;
  date: string;
  username?: string;
  avatar_url?: string;
}

/**
 * Statistics for a commit (additions, deletions, files changed)
 */
export interface GitCommitStats {
  additions: number;
  deletions: number;
  total: number;
  files_changed: number;
}

/**
 * Basic commit information (for lists)
 */
export interface GitCommit {
  sha: string;
  short_sha: string;
  message: string;
  title: string;  // First line of message
  body?: string;  // Rest of message after first line
  author: GitCommitAuthor;
  committer: GitCommitAuthor;
  authored_date: string;
  committed_date: string;
  web_url?: string;
  parent_shas: string[];
  is_merge: boolean;
  is_verified: boolean;
  verification?: {
    verified: boolean;
    reason: string;
    signature?: string;
    payload?: string;
  };
}

/**
 * File changed in a commit
 */
export interface GitCommitFile {
  sha?: string;
  filename: string;
  status: 'added' | 'removed' | 'modified' | 'renamed' | 'copied' | 'changed' | 'unchanged';
  additions: number;
  deletions: number;
  changes: number;
  patch?: string;
  previous_filename?: string;
  blob_url?: string;
  raw_url?: string;
  contents_url?: string;
}

/**
 * Detailed commit information including files and stats
 */
export interface GitCommitDetail extends GitCommit {
  stats: GitCommitStats;
  files: GitCommitFile[];
  tree_sha?: string;
  repository?: {
    id: string;
    name: string;
    full_name: string;
  };
}

/**
 * A single line in a diff hunk
 */
export interface GitDiffLine {
  type: 'context' | 'addition' | 'deletion' | 'header';
  content: string;
  old_line_number?: number;
  new_line_number?: number;
}

/**
 * A hunk (section) within a file diff
 */
export interface GitDiffHunk {
  header: string;
  old_start: number;
  old_lines: number;
  new_start: number;
  new_lines: number;
  lines: GitDiffLine[];
}

/**
 * Diff for a single file
 */
export interface GitFileDiff {
  filename: string;
  status: 'added' | 'removed' | 'modified' | 'renamed' | 'copied';
  additions: number;
  deletions: number;
  changes: number;
  previous_filename?: string;
  hunks: GitDiffHunk[];
  is_binary: boolean;
  is_large: boolean;
  truncated: boolean;
  raw_patch?: string;
}

/**
 * Complete diff between two commits or a commit and its parent
 */
export interface GitDiff {
  base_sha: string;
  head_sha: string;
  base_ref?: string;
  head_ref?: string;
  ahead_by?: number;
  behind_by?: number;
  total_commits?: number;
  files: GitFileDiff[];
  stats: GitCommitStats;
  status: 'identical' | 'ahead' | 'behind' | 'diverged';
  commits?: GitCommit[];
}

/**
 * Branch information with latest commit
 */
export interface GitBranch {
  name: string;
  sha: string;
  is_default: boolean;
  is_protected: boolean;
  protection_rules?: {
    required_reviews: number;
    dismiss_stale_reviews: boolean;
    require_code_owner_reviews: boolean;
    require_signed_commits: boolean;
    enforce_admins: boolean;
    required_status_checks: string[];
  };
  commit?: GitCommit;
  web_url?: string;
}

/**
 * Tag information
 */
export interface GitTag {
  name: string;
  sha: string;
  message?: string;
  tagger?: GitCommitAuthor;
  commit?: GitCommit;
  web_url?: string;
  is_release: boolean;
  release?: {
    id: string;
    name: string;
    body?: string;
    draft: boolean;
    prerelease: boolean;
    created_at: string;
    published_at?: string;
    assets_count: number;
  };
}

/**
 * Tree entry (file or directory in a repository tree)
 */
export interface GitTreeEntry {
  path: string;
  name: string;
  type: 'blob' | 'tree' | 'commit';
  mode: string;
  sha: string;
  size?: number;
  url?: string;
}

/**
 * Repository tree (directory listing)
 */
export interface GitTree {
  sha: string;
  url?: string;
  entries: GitTreeEntry[];
  truncated: boolean;
}

/**
 * File content from repository
 */
export interface GitFileContent {
  name: string;
  path: string;
  sha: string;
  size: number;
  type: 'file' | 'dir' | 'symlink' | 'submodule';
  content?: string;
  encoding?: 'base64' | 'utf-8' | 'none';
  target?: string;  // For symlinks
  submodule_url?: string;  // For submodules
  download_url?: string;
  web_url?: string;
  language?: string;
  is_binary: boolean;
  lines_count?: number;
}

/**
 * File blame information (who changed each line)
 */
export interface GitBlameRange {
  commit: GitCommit;
  start_line: number;
  end_line: number;
  lines: string[];
}

export interface GitFileBlame {
  path: string;
  sha: string;
  ranges: GitBlameRange[];
}

/**
 * Commit comparison between two refs
 */
export interface GitCommitComparison {
  url?: string;
  status: 'identical' | 'ahead' | 'behind' | 'diverged';
  ahead_by: number;
  behind_by: number;
  total_commits: number;
  base_commit: GitCommit;
  head_commit: GitCommit;
  merge_base_commit: GitCommit;
  commits: GitCommit[];
  files: GitCommitFile[];
  diff_stats: GitCommitStats;
}

// Response types for git viewing APIs

export interface GitCommitsResponse {
  commits: GitCommit[];
  pagination: PaginationInfo;
  repository?: {
    id: string;
    name: string;
    default_branch: string;
  };
}

export interface GitBranchesResponse {
  branches: GitBranch[];
  pagination: PaginationInfo;
  default_branch?: string;
}

export interface GitTagsResponse {
  tags: GitTag[];
  pagination: PaginationInfo;
}

export interface GitTreeResponse {
  tree: GitTree;
  commit_sha: string;
  path: string;
  repository?: {
    id: string;
    name: string;
  };
}
