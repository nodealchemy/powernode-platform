export type ResourceType =
  | 'artifact'
  | 'git_branch'
  | 'git_merge'
  | 'execution_output'
  | 'shared_memory'
  | 'trajectory'
  | 'review'
  | 'runner_job';

export interface ExecutionResource {
  id: string;
  resource_type: ResourceType;
  name: string;
  description: string;
  mime_type: string | null;
  status: string;
  source_type: string;
  source_id: string;
  source_label: string;
  execution_id: string | null;
  team_id: string | null;
  agent_id: string | null;
  agent_name: string | null;
  preview: string | null;
  url: string | null;
  branch_name: string | null;
  commit_sha: string | null;
  files_changed: number | null;
  lines_added: number | null;
  lines_removed: number | null;
  pull_request_url: string | null;
  quality_score: number | null;
  findings_count: number | null;
  created_at: string;
  metadata: Record<string, unknown>;
}

export interface TrajectoryChapter {
  chapter_number: number;
  title: string;
  chapter_type: string;
  content: string;
  reasoning?: string | null;
  key_decisions?: Record<string, unknown>[];
  artifacts?: Record<string, unknown>[];
  context_references?: Record<string, unknown>[];
  duration_ms?: number;
}

export interface ResourceDetail extends ExecutionResource {
  // Artifact (A2A Task)
  input?: Record<string, unknown>;
  output?: Record<string, unknown>;
  history?: Record<string, unknown>[];
  cost?: number;
  tokens_used?: number;
  duration_ms?: number;
  error_message?: string | null;
  error_code?: string | null;
  error_details?: Record<string, unknown>;
  started_at?: string | null;
  completed_at?: string | null;
  from_agent_name?: string | null;
  to_agent_name?: string | null;
  subtasks_count?: number;
  full_artifacts?: Record<string, unknown>[];
  retry_count?: number;
  max_retries?: number;
  sequence_number?: number;
  is_external?: boolean;

  // Git Branch (Worktree)
  base_commit_sha?: string | null;
  commit_count?: number;
  test_status?: string | null;
  disk_usage_bytes?: number;
  estimated_cost_cents?: number;
  healthy?: boolean;
  health_message?: string | null;
  locked?: boolean;
  lock_reason?: string | null;
  worktree_path?: string | null;
  ready_at?: string | null;
  timeout_at?: string | null;

  // Git Merge
  source_branch?: string;
  target_branch?: string;
  strategy?: string;
  has_conflicts?: boolean;
  conflict_files?: string[];
  conflict_details?: string | null;
  conflict_resolution?: string | null;
  merge_commit_sha?: string | null;
  rollback_commit_sha?: string | null;
  rolled_back?: boolean;
  rolled_back_at?: string | null;
  pull_request_status?: string | null;
  pull_request_id?: string | null;
  merge_order?: number;

  // Execution Output
  objective?: string | null;
  input_context?: Record<string, unknown>;
  output_result?: Record<string, unknown>;
  shared_memory?: Record<string, unknown>;
  performance_metrics?: Record<string, unknown>;
  total_cost_usd?: number;
  total_tokens_used?: number;
  messages_exchanged?: number;
  tasks_total?: number;
  tasks_completed?: number;
  tasks_failed?: number;
  control_signal?: string | null;
  termination_reason?: string | null;
  triggered_by_name?: string | null;
  team_name?: string | null;

  // Shared Memory
  full_data?: Record<string, unknown>;
  pool_type?: string;
  pool_id?: string;
  scope?: string;
  data_size_bytes?: number;
  persist_across_executions?: boolean;
  expires_at?: string | null;
  last_accessed_at?: string | null;
  access_control?: Record<string, unknown>;
  retention_policy?: Record<string, unknown>;
  version?: number;
  owner_agent_name?: string | null;

  // Trajectory
  summary?: string | null;
  trajectory_type?: string;
  trajectory_id?: string;
  access_count?: number;
  chapter_count?: number;
  outcome_summary?: Record<string, unknown>;
  tags?: string[];
  chapters?: TrajectoryChapter[];

  // Review
  review_mode?: string;
  findings?: Record<string, unknown>[];
  diff_analysis?: Record<string, unknown>;
  file_comments?: Record<string, unknown>;
  code_suggestions?: Record<string, unknown>;
  completeness_checks?: Record<string, unknown>;
  approval_notes?: string | null;
  rejection_reason?: string | null;
  commit_sha_review?: string | null;
  repository_url?: string | null;
  pull_request_number?: number | null;
  review_duration_ms?: number;
  revision_count?: number;
  reviewer_agent_name?: string | null;

  // Runner Job
  input_params?: Record<string, unknown>;
  output_result_runner?: Record<string, unknown>;
  logs?: string | null;
  runner_labels?: string[];
  workflow_run_id?: string;
  workflow_url?: string;
  dispatched_at?: string | null;
  runner_name?: string | null;
  repository_name?: string | null;
  worktree_branch?: string | null;
}

export interface ResourceCounts {
  total: number;
  artifact?: number;
  git_branch?: number;
  git_merge?: number;
  execution_output?: number;
  shared_memory?: number;
  trajectory?: number;
  review?: number;
  runner_job?: number;
}

export interface ResourceFilters {
  type?: ResourceType;
  execution_id?: string;
  team_id?: string;
  agent_id?: string;
  status?: string;
  search?: string;
  start_date?: string;
  end_date?: string;
  page?: number;
  per_page?: number;
}

export interface ResourceDetailProps {
  resource: ResourceDetail;
}
