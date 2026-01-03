// Re-export types from git-providers for CI/CD feature
export type {
  GitPipeline,
  GitPipelineDetail,
  GitPipelineJob,
  GitPipelineJobDetail,
  PipelineStep,
  PipelineStats,
  GitWebhookEvent,
  GitWebhookEventDetail,
  WebhookEventStats,
  GitRepository,
  GitRepositoryDetail,
  PaginationInfo,
} from '@/features/git-providers/types';

// Extended GitRepository with additional CI/CD fields for display
// These map to the API response fields
export interface GitRepositoryWithStatus {
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
  // Additional UI-computed fields
  last_pipeline_status?: 'success' | 'failure' | 'cancelled' | 'running' | 'pending';
  last_pipeline_at?: string;
  pipeline_stats?: {
    total_runs: number;
    success_count: number;
    failed_count: number;
    cancelled_count: number;
    success_rate: number;
    avg_duration_seconds: number;
    runs_today: number;
    runs_this_week: number;
    active_runs: number;
  };
}

// CI/CD specific types
export interface CICDDashboardStats {
  totalRuns: number;
  successCount: number;
  failedCount: number;
  cancelledCount: number;
  successRate: number;
  avgDurationSeconds: number;
  runsToday: number;
  runsThisWeek: number;
  activeRuns: number;
}

export interface WebhookEventFilters {
  eventType?: string;
  status?: 'all' | 'pending' | 'processing' | 'processed' | 'failed';
  repositoryId?: string;
  since?: string;
  until?: string;
}

export interface PipelineFilters {
  status?: 'all' | 'pending' | 'running' | 'completed' | 'cancelled';
  conclusion?: 'all' | 'success' | 'failure' | 'cancelled' | 'skipped';
  branch?: string;
}
