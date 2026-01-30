// Git Repository Types

import type { PipelineStats } from './pipelines';

export interface PaginationInfo {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

export type BranchFilterType = 'none' | 'exact' | 'wildcard' | 'regex';

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
  branch_filter?: string;
  branch_filter_type?: BranchFilterType;
  branch_filter_enabled?: boolean;
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

// Available repository from provider (not yet imported)
export interface AvailableRepository {
  external_id: string;
  name: string;
  full_name: string;
  owner: string;
  description?: string;
  default_branch: string;
  web_url?: string;
  is_private: boolean;
  is_fork: boolean;
  is_archived: boolean;
  stars_count: number;
  primary_language?: string;
  already_imported: boolean;
}

export interface RepositoryUsage {
  current: number;
  limit: number;
  available: number;
}

export interface AvailableRepositoriesResponse {
  repositories: AvailableRepository[];
  pagination: {
    current_page: number;
    per_page: number;
    total_count: number;
  };
  usage: RepositoryUsage;
}

export interface ImportRepositoriesResult {
  imported_count: number;
  error_count: number;
  repositories: GitRepository[];
  errors: Array<{
    external_id: string;
    error: string;
  }>;
  usage: {
    current: number;
    limit: number;
  };
  message: string;
}

export interface GitRepositoriesResponse {
  repositories: GitRepository[];
  pagination: PaginationInfo;
}

export interface WebhookConfigFormData {
  branch_filter?: string;
  branch_filter_type?: BranchFilterType;
}
