// Types for Parallel Execution with Git Worktrees

export type ParallelSessionStatus = 'pending' | 'provisioning' | 'active' | 'merging' | 'completed' | 'failed' | 'cancelled';
export type WorktreeStatus = 'pending' | 'creating' | 'ready' | 'in_use' | 'completed' | 'merged' | 'cleaned_up' | 'failed';
export type MergeOperationStatus = 'pending' | 'in_progress' | 'completed' | 'conflict' | 'failed' | 'rolled_back';
export type MergeStrategy = 'sequential' | 'integration_branch' | 'manual';

export interface ParallelSession {
  id: string;
  status: ParallelSessionStatus;
  repository_path: string;
  base_branch: string;
  integration_branch?: string;
  merge_strategy: MergeStrategy;
  max_parallel: number;
  total_worktrees: number;
  completed_worktrees: number;
  failed_worktrees: number;
  progress_percentage: number;
  source_type?: string;
  source_id?: string;
  started_at?: string;
  completed_at?: string;
  duration_ms?: number;
  error_message?: string;
  error_code?: string;
  configuration?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  created_at: string;
  execution_mode?: 'complementary' | 'competitive';
  max_duration_seconds?: number;
  conflict_matrix?: Record<string, ConflictPair>;
}

export interface ParallelSessionDetail extends ParallelSession {
  worktrees: ParallelWorktree[];
  merge_operations: MergeOperation[];
}

export interface ParallelWorktree {
  id: string;
  worktree_session_id: string;
  branch_name: string;
  worktree_path: string;
  status: WorktreeStatus;
  ai_agent_id?: string;
  agent_name?: string;
  base_commit_sha?: string;
  head_commit_sha?: string;
  commit_count: number;
  locked: boolean;
  healthy: boolean;
  files_changed: number;
  lines_added: number;
  lines_removed: number;
  container_instance_id?: string;
  container_template_id?: string;
  ready_at?: string;
  completed_at?: string;
  duration_ms?: number;
  error_message?: string;
  created_at: string;
  tokens_used?: number;
  estimated_cost_cents?: number;
  timeout_at?: string;
  test_status?: 'pending' | 'running' | 'passed' | 'failed' | 'skipped' | null;
}

export interface MergeOperation {
  id: string;
  worktree_id: string;
  source_branch: string;
  target_branch: string;
  strategy: string;
  status: MergeOperationStatus;
  merge_order: number;
  merge_commit_sha?: string;
  has_conflicts: boolean;
  conflict_files: string[];
  conflict_resolution?: string;
  pull_request_url?: string;
  rolled_back: boolean;
  started_at?: string;
  completed_at?: string;
  duration_ms?: number;
  error_message?: string;
}

export interface ParallelSessionConfig {
  repository_path: string;
  base_branch?: string;
  merge_strategy?: MergeStrategy;
  max_parallel?: number;
  auto_cleanup?: boolean;
  tasks: ParallelTaskConfig[];
  source_type?: string;
  source_id?: string;
  configuration?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  execution_mode?: 'complementary' | 'competitive';
  max_duration_seconds?: number;
}

export interface ParallelTaskConfig {
  branch_suffix: string;
  agent_id?: string;
  container_template_id?: string;
  metadata?: Record<string, unknown>;
}

export interface ParallelExecutionUpdate {
  event: string;
  resource_type: string;
  resource_id: string;
  payload: Record<string, unknown>;
  timestamp: string;
  is_initial_status?: boolean;
}

export interface ConflictPair {
  has_conflicts: boolean;
  conflict_files: string[];
  error?: string;
}

export interface ConflictResult {
  worktree_a_id: string;
  worktree_a_branch: string;
  worktree_b_id: string;
  worktree_b_branch: string;
  conflict_files: string[];
}

export interface FileLock {
  id: string;
  file_path: string;
  worktree_id: string;
  branch_name?: string;
  lock_type: 'exclusive' | 'shared';
  acquired_at?: string;
  expires_at?: string;
}

export interface CompetitionEvaluation {
  worktree_id: string;
  branch_name: string;
  files_changed: number;
  lines_added: number;
  lines_removed: number;
  commit_count: number;
  duration_ms?: number;
  tokens_used: number;
  healthy: boolean;
  dirty: boolean;
  test_status?: string;
}

export interface LogEntry {
  timestamp: string;
  level: 'info' | 'warn' | 'error' | 'debug';
  message: string;
  source?: string;
}
