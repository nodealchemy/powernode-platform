// Git Runner Types (CI/CD Self-Hosted Runners)

import type { PaginationInfo } from './repositories';

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
