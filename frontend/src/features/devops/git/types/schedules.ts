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

export interface GitPipelineSchedulesResponse {
  schedules: GitPipelineSchedule[];
  pagination: PaginationInfo;
}

