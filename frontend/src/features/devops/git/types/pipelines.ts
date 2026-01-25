// Git Pipeline Types

import type { PaginationInfo } from './repositories';

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

export interface PipelineStep {
  name: string;
  status: string;
  conclusion?: string;
  number: number;
}

export interface GitPipelineDetail extends GitPipeline {
  jobs: GitPipelineJob[];
  workflow_config?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export interface GitPipelineJobDetail extends GitPipelineJob {
  logs_url?: string;
  steps?: PipelineStep[];
  outputs?: Record<string, unknown>;
  runner_info?: Record<string, unknown>;
  act_runner?: boolean;
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

export interface GitPipelinesResponse {
  pipelines: GitPipeline[];
  pagination: PaginationInfo;
  stats: PipelineStats;
}
