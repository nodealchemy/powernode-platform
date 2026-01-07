// CI/CD Pipeline Management Types

// Provider types
export type CiCdProviderType = 'gitea' | 'github' | 'gitlab' | 'jenkins';

export interface CiCdProvider {
  id: string;
  name: string;
  provider_type: CiCdProviderType;
  base_url: string;
  is_active: boolean;
  last_sync_at: string | null;
  settings: Record<string, unknown>;
  repository_count: number;
  created_at: string;
  updated_at: string;
}

export interface CiCdProviderFormData {
  name: string;
  provider_type: CiCdProviderType;
  base_url: string;
  api_token: string;
  webhook_secret?: string;
  is_active: boolean;
  settings?: Record<string, unknown>;
}

// Prompt Template types (now uses Shared::PromptTemplate with domain='cicd')
export type CiCdPromptCategory = 'review' | 'implement' | 'security' | 'deploy' | 'docs' | 'custom' | 'general' | 'agent' | 'workflow';
export type CiCdPromptDomain = 'cicd' | 'ai_workflow' | 'general';

export interface CiCdPromptTemplate {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  category: CiCdPromptCategory;
  domain: CiCdPromptDomain;
  content: string;
  variables: Record<string, string>;
  is_active: boolean;
  is_system: boolean;
  version: number;
  usage_count: number;
  variable_names: string[];
  created_by_name: string | null;
  parent_template_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface CiCdPromptTemplateFormData {
  name: string;
  description?: string;
  category: CiCdPromptCategory;
  content: string;
  is_active: boolean;
  variables?: Record<string, string>;
  parent_template_id?: string;
}

// Pipeline types
export type CiCdTriggerEvent = 'pull_request' | 'push' | 'issues' | 'issue_comment' | 'release' | 'schedule' | 'manual';

export interface CiCdPipelineTriggers {
  pull_request?: string[];
  push?: { branches?: string[] };
  issues?: string[];
  issue_comment?: string[] | { mention_required?: boolean };
  release?: string[];
  schedule?: string[];
  workflow_dispatch?: Record<string, unknown>;
  manual?: boolean;
}

export interface CiCdPipeline {
  id: string;
  name: string;
  slug: string;
  pipeline_type: string;
  description: string | null;
  triggers: CiCdPipelineTriggers;
  environment: Record<string, unknown>;
  secret_refs: string[];
  runner_labels: string[];
  timeout_minutes: number;
  allow_concurrent: boolean;
  features: Record<string, unknown>;
  is_active: boolean;
  is_system: boolean;
  version: number;
  step_count: number;
  run_count: number;
  last_run: {
    id: string;
    run_number: number;
    status: string;
    started_at: string | null;
    completed_at: string | null;
    error_message?: string | null;
  } | null;
  success_rate: number | null;
  ai_provider_id: string | null;
  ai_provider_name: string | null;
  created_by_name: string | null;
  created_at: string;
  updated_at: string;
  steps?: CiCdPipelineStep[];
  recent_runs?: CiCdPipelineRun[];
}

// Notification types for pipelines
export interface NotificationRecipient {
  type: 'email' | 'user_id';
  value: string;
  display_name?: string;
}

export interface NotificationSettingsConfig {
  on_approval_required: boolean;
  on_completion: boolean;
  on_failure: boolean;
}

// Step approval settings
export interface StepApprovalSettings {
  timeout_hours: number;
  require_comment: boolean;
  notification_recipients: NotificationRecipient[];
}

export interface CiCdPipelineFormData {
  name: string;
  description?: string;
  pipeline_type?: string;
  ai_provider_id?: string;
  is_active: boolean;
  triggers?: CiCdPipelineTriggers;
  environment?: Record<string, unknown>;
  timeout_minutes?: number;
  allow_concurrent?: boolean;
  features?: Record<string, unknown>;
  steps?: CiCdPipelineStepFormData[];
  notification_recipients?: NotificationRecipient[];
  notification_settings?: NotificationSettingsConfig;
}

// Pipeline Step types
export type CiCdStepType =
  | 'checkout'
  | 'claude_execute'
  | 'post_comment'
  | 'create_pr'
  | 'create_branch'
  | 'deploy'
  | 'run_tests'
  | 'upload_artifact'
  | 'download_artifact'
  | 'notify'
  | 'custom';

export interface CiCdPipelineStepOutput {
  name: string;
  type?: string;
}

export interface CiCdPipelineStep {
  id: string;
  name: string;
  step_type: CiCdStepType | string;
  position: number;
  configuration: Record<string, unknown>;
  inputs: Record<string, unknown>;
  outputs: CiCdPipelineStepOutput[] | Record<string, unknown>;
  condition: string | null;
  continue_on_error: boolean;
  is_active: boolean;
  output_definitions: Record<string, unknown>;
  requires_prompt: boolean;
  shared_prompt_template_id: string | null;
  shared_prompt_template_name: string | null;
  created_at: string;
  updated_at: string;
}

export interface CiCdPipelineStepFormData {
  name: string;
  step_type: CiCdStepType;
  position?: number;
  configuration?: Record<string, unknown>;
  inputs?: Record<string, unknown>;
  outputs?: Record<string, unknown>;
  condition?: string;
  continue_on_error?: boolean;
  is_active?: boolean;
  shared_prompt_template_id?: string;
  requires_approval?: boolean;
  approval_settings?: StepApprovalSettings;
}

// Pipeline Run types
export type CiCdPipelineRunStatus = 'pending' | 'queued' | 'running' | 'success' | 'failure' | 'cancelled';
export type CiCdTriggerType = 'manual' | 'webhook' | 'schedule' | 'retry';

export interface CiCdPipelineRun {
  id: string;
  run_number: number;
  status: CiCdPipelineRunStatus;
  trigger_type: CiCdTriggerType;
  trigger_context: Record<string, unknown>;
  started_at: string | null;
  completed_at: string | null;
  duration_seconds: number | null;
  outputs: Record<string, unknown> | null;
  artifacts: Record<string, unknown> | null;
  error_message: string | null;
  external_run_id: string | null;
  external_run_url: string | null;
  progress_percentage: number;
  pr_number: number | null;
  commit_sha: string | null;
  branch: string | null;
  step_execution_count: number;
  current_step: {
    id: string;
    name: string;
    step_type: string;
    status: string;
  } | null;
  pipeline_name?: string;
  pipeline_slug?: string;
  step_executions?: CiCdStepExecution[];
  created_at: string;
  updated_at: string;
}

// Step Execution types
export type CiCdStepExecutionStatus = 'pending' | 'running' | 'waiting_approval' | 'success' | 'failure' | 'cancelled' | 'skipped';

export interface CiCdStepExecution {
  id: string;
  status: CiCdStepExecutionStatus;
  started_at: string | null;
  completed_at: string | null;
  duration_seconds: number | null;
  outputs: Record<string, unknown> | null;
  logs: string | null;
  error_message: string | null;
  step_name: string;
  step_type: string;
  position: number;
  created_at: string;
  updated_at: string;
}

// Schedule types
export interface CiCdSchedule {
  id: string;
  name: string;
  cron_expression: string;
  timezone: string;
  inputs: Record<string, unknown>;
  next_run_at: string | null;
  last_run_at: string | null;
  is_active: boolean;
  cron_description: string;
  is_due: boolean;
  pipeline_name: string;
  pipeline_slug: string;
  created_at: string;
  updated_at: string;
}

export interface CiCdScheduleFormData {
  name: string;
  cron_expression: string;
  timezone?: string;
  is_active: boolean;
  pipeline_id: string;
  inputs?: Record<string, unknown>;
}

// Repository types
export interface CiCdRepository {
  id: string;
  name: string;
  full_name: string;
  default_branch: string;
  external_id: string;
  settings: Record<string, unknown>;
  is_active: boolean;
  last_synced_at: string | null;
  clone_url: string;
  web_url: string;
  owner: string;
  repo_name: string;
  provider_type: CiCdProviderType;
  pipeline_count: number;
  pipelines?: Array<{
    id: string;
    name: string;
    slug: string;
    overrides: Record<string, unknown>;
    attached_at: string;
  }>;
  created_at: string;
  updated_at: string;
}

export interface CiCdRepositoryFormData {
  name: string;
  full_name: string;
  default_branch?: string;
  external_id: string;
  is_active: boolean;
  provider_id: string;
  settings?: Record<string, unknown>;
}

// API Response types
export interface CiCdProvidersResponse {
  providers: CiCdProvider[];
  meta: {
    total: number;
    by_type: Record<string, number>;
  };
}

export interface CiCdPromptTemplatesResponse {
  prompt_templates: CiCdPromptTemplate[];
  meta: {
    total: number;
    by_category: Record<string, number>;
  };
}

export interface CiCdPipelinesResponse {
  pipelines: CiCdPipeline[];
  meta: {
    total: number;
    active_count: number;
    total_runs: number;
  };
}

export interface CiCdPipelineRunsResponse {
  pipeline_runs: CiCdPipelineRun[];
  meta: {
    total: number;
    page: number;
    per_page: number;
    total_pages: number;
    status_counts: Record<string, number>;
  };
}

export interface CiCdSchedulesResponse {
  schedules: CiCdSchedule[];
  meta: {
    total: number;
    active_count: number;
    next_due: string | null;
  };
}

export interface CiCdRepositoriesResponse {
  repositories: CiCdRepository[];
  meta: {
    total: number;
    active_count: number;
    by_provider: Record<string, number>;
  };
}

// Preview response
export interface CiCdPromptPreviewResponse {
  prompt_template_id: string;
  rendered_content: string;
  variables_used: string[];
  rendered_at: string;
}

// Export YAML response
export interface CiCdPipelineExportResponse {
  pipeline_id: string;
  pipeline_name: string;
  yaml: string;
  generated_at: string;
}

// Connection test response
export interface CiCdConnectionTestResponse {
  provider_id: string;
  connected: boolean;
  message: string;
  details?: Record<string, unknown>;
  tested_at: string;
}
