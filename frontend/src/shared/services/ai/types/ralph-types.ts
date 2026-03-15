/**
 * Ralph Loops Types
 *
 * Types for autonomous AI agent loop execution
 */

// Status types
export type RalphLoopStatus = 'pending' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';

export type RalphTaskStatus = 'pending' | 'in_progress' | 'passed' | 'failed' | 'blocked' | 'skipped';

export type RalphIterationStatus = 'pending' | 'running' | 'completed' | 'failed' | 'skipped';

// Scheduling mode types
export type RalphSchedulingMode = 'manual' | 'scheduled' | 'continuous' | 'event_triggered' | 'autonomous';

// Execution types for tasks
export type RalphExecutionType = 'agent' | 'workflow' | 'pipeline' | 'a2a_task' | 'container' | 'human' | 'community';

// Capability match strategies
export type RalphCapabilityMatchStrategy = 'all' | 'any' | 'weighted';

// PRD Task definition (for prd_json)
export interface PrdTask {
  key: string;
  description: string;
  priority?: number;
  dependencies?: string[];
  acceptance_criteria?: string;
}

// Schedule configuration
export interface RalphScheduleConfig {
  cron_expression?: string;
  timezone?: string;
  start_at?: string;
  end_at?: string;
  iteration_interval_seconds?: number;
  max_iterations_per_day?: number;
  pause_on_failure?: boolean;
  retry_on_failure?: boolean;
  retry_delay_seconds?: number;
  skip_if_running?: boolean;
}

// Delegation configuration for tasks
export interface RalphDelegationConfig {
  allowed_agents?: string[];
  max_delegation_depth?: number;
  allow_sub_delegation?: boolean;
  timeout_seconds?: number;
  retry_strategy?: 'none' | 'linear' | 'exponential';
  fallback_executor_type?: RalphExecutionType;
  fallback_executor_id?: string;
}

// Ralph Loop
export interface RalphLoop {
  id: string;
  account_id: string;
  name: string;
  description?: string;
  status: RalphLoopStatus;
  prd_json?: {
    tasks: PrdTask[];
    metadata?: Record<string, unknown>;
  };
  progress_text?: string;
  learnings: string[];
  repository_url?: string;
  branch?: string;
  current_iteration: number;
  max_iterations: number;
  default_agent_id: string | null;
  default_agent_name?: string;
  container_instance_id?: string;
  started_at?: string;
  completed_at?: string;
  configuration: {
    auto_commit?: boolean;
    run_checks?: boolean;
    check_commands?: string[];
    prompt_template?: string;
    context_limit?: number;
    mcp_server_ids?: string[];
    run_all_active?: boolean;
    parallel_session_id?: string;
  };
  metrics?: {
    total_iterations: number;
    successful_iterations: number;
    failed_iterations: number;
    total_tasks: number;
    completed_tasks: number;
    total_tokens: number;
    total_cost: number;
  };
  task_count?: number;
  completed_task_count?: number;
  iteration_count?: number;
  // Scheduling fields
  scheduling_mode: RalphSchedulingMode;
  schedule_config?: RalphScheduleConfig;
  schedule_paused?: boolean;
  schedule_paused_at?: string;
  schedule_paused_reason?: string;
  next_scheduled_at?: string;
  last_scheduled_at?: string;
  daily_iteration_count?: number;
  daily_iteration_reset_at?: string;
  webhook_token?: string;
  created_at: string;
  updated_at: string;
}

export interface RalphLoopSummary {
  id: string;
  name: string;
  description?: string;
  status: RalphLoopStatus;
  current_iteration: number;
  max_iterations: number;
  default_agent_id: string | null;
  default_agent_name?: string;
  mcp_server_ids?: string[];
  task_count: number;
  completed_task_count: number;
  progress_percentage: number;
  started_at?: string;
  completed_at?: string;
  // Scheduling fields
  scheduling_mode: RalphSchedulingMode;
  schedule_paused?: boolean;
  next_scheduled_at?: string;
  last_scheduled_at?: string;
  daily_iteration_count?: number;
}

// Ralph Task
export interface RalphTask {
  id: string;
  ralph_loop_id: string;
  task_key: string;
  description: string;
  status: RalphTaskStatus;
  priority: number;
  dependencies: string[];
  acceptance_criteria?: string;
  iteration_count: number;
  iteration_completed_at?: string;
  error_message?: string;
  // Executor fields
  execution_type: RalphExecutionType;
  executor_type?: string;
  executor_id?: string;
  required_capabilities?: string[];
  capability_match_strategy?: RalphCapabilityMatchStrategy;
  delegation_config?: RalphDelegationConfig;
  execution_attempts?: number;
  created_at: string;
  updated_at: string;
}

export interface RalphTaskSummary {
  id: string;
  task_key: string;
  description: string;
  status: RalphTaskStatus;
  priority: number;
  iteration_count: number;
  execution_type?: RalphExecutionType;
  executor_type?: string;
  executor_id?: string;
  execution_attempts?: number;
}

// Ralph Iteration
export interface RalphIteration {
  id: string;
  ralph_loop_id: string;
  ralph_task_id?: string;
  task_key?: string;
  iteration_number: number;
  status: RalphIterationStatus;
  ai_prompt?: string;
  ai_output?: string;
  git_commit_sha?: string;
  checks_passed?: boolean;
  check_results?: {
    command: string;
    success: boolean;
    output?: string;
    error?: string;
  }[];
  duration_ms?: number;
  input_tokens?: number;
  output_tokens?: number;
  cost?: number;
  error_message?: string;
  started_at?: string;
  completed_at?: string;
  created_at: string;
}

export interface RalphIterationSummary {
  id: string;
  iteration_number: number;
  task_key?: string;
  status: RalphIterationStatus;
  checks_passed?: boolean;
  duration_ms?: number;
  git_commit_sha?: string;
  completed_at?: string;
}

// Request/Response types
export interface CreateRalphLoopRequest {
  name: string;
  description?: string;
  repository_url?: string;
  branch?: string;
  default_agent_id: string;
  max_iterations?: number;
  prd_json?: {
    tasks: PrdTask[];
    metadata?: Record<string, unknown>;
  };
  configuration?: {
    auto_commit?: boolean;
    run_checks?: boolean;
    check_commands?: string[];
    prompt_template?: string;
    context_limit?: number;
    mcp_server_ids?: string[];
  };
  scheduling_mode?: RalphSchedulingMode;
  schedule_config?: RalphScheduleConfig;
}

export interface UpdateRalphLoopRequest {
  name?: string;
  description?: string;
  repository_url?: string;
  branch?: string;
  default_agent_id?: string;
  max_iterations?: number;
  configuration?: {
    auto_commit?: boolean;
    run_checks?: boolean;
    check_commands?: string[];
    prompt_template?: string;
    context_limit?: number;
    mcp_server_ids?: string[];
  };
  scheduling_mode?: RalphSchedulingMode;
  schedule_config?: RalphScheduleConfig;
}

// Task executor update request
export interface UpdateRalphTaskExecutorRequest {
  execution_type?: RalphExecutionType;
  executor_id?: string;
  required_capabilities?: string[];
  capability_match_strategy?: RalphCapabilityMatchStrategy;
  delegation_config?: RalphDelegationConfig;
}

export interface RalphLoopFilters {
  status?: RalphLoopStatus;
  default_agent_id?: string;
  query?: string;
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

export interface RalphTaskFilters {
  status?: RalphTaskStatus;
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

export interface RalphIterationFilters {
  status?: RalphIterationStatus;
  task_id?: string;
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

export interface ParsePrdRequest {
  prd_json: {
    tasks: PrdTask[];
    metadata?: Record<string, unknown>;
  };
  replace_existing?: boolean;
}

export interface RalphStatistics {
  total_loops: number;
  active_loops: number;
  completed_loops: number;
  total_iterations: number;
  total_tasks_completed: number;
  success_rate: number;
  avg_iterations_per_loop: number;
}

export interface RalphProgress {
  loop_status: {
    loop: Record<string, unknown>;
    tasks: Record<string, unknown>[];
    recent_iterations: Record<string, unknown>[];
    next_task: Record<string, unknown> | null;
  };
  progress_text: string;
  progress_percentage: number;
  learnings: string[];
  recent_commits: {
    sha: string;
    message: string;
    timestamp: string;
  }[];
}

// Schedule action responses
export interface PauseScheduleResponse {
  ralph_loop: RalphLoop;
  message: string;
}

export interface ResumeScheduleResponse {
  ralph_loop: RalphLoop;
  message: string;
  next_scheduled_at?: string;
}

export interface RegenerateWebhookTokenResponse {
  webhook_token: string;
  webhook_url: string;
  message: string;
}
