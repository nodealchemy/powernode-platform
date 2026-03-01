// Git Pipeline Schedule Types

import type { PaginationInfo } from './repositories';

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
