// DevOps Pipeline Management Types

// Pipeline types

export interface DevopsPipelineTriggers {
  pull_request?: string[];
  push?: { branches?: string[] };
  issues?: string[];
  issue_comment?: string[] | { mention_required?: boolean };
  release?: string[];
  schedule?: string[];
  workflow_dispatch?: Record<string, unknown>;
  manual?: boolean;
}

export interface DevopsPipeline {
  id: string;
  name: string;
  slug: string;
  pipeline_type: string;
  description: string | null;
  triggers: DevopsPipelineTriggers;
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
  steps?: DevopsPipelineStep[];
  recent_runs?: DevopsPipelineRun[];
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

export interface DevopsPipelineFormData {
  name: string;
  description?: string;
  pipeline_type?: string;
  ai_provider_id?: string;
  is_active: boolean;
  triggers?: DevopsPipelineTriggers;
  environment?: Record<string, unknown>;
  timeout_minutes?: number;
  allow_concurrent?: boolean;
  features?: Record<string, unknown>;
  steps?: DevopsPipelineStepFormData[];
  notification_recipients?: NotificationRecipient[];
  notification_settings?: NotificationSettingsConfig;
}

// Pipeline Step types
export type DevopsStepType =
  | 'checkout'
  | 'claude_execute'
  | 'ai_workflow'
  | 'post_comment'
  | 'create_pr'
  | 'create_branch'
  | 'deploy'
  | 'run_tests'
  | 'upload_artifact'
  | 'download_artifact'
  | 'notify'
  | 'custom';

export interface DevopsPipelineStepOutput {
  name: string;
  type?: string;
}

export interface DevopsPipelineStep {
  id: string;
  name: string;
  step_type: DevopsStepType | string;
  position: number;
  configuration: Record<string, unknown>;
  inputs: Record<string, unknown>;
  outputs: DevopsPipelineStepOutput[] | Record<string, unknown>;
  condition: string | null;
  continue_on_error: boolean;
  is_active: boolean;
  output_definitions: Record<string, unknown>;
  requires_prompt: boolean;
  requires_approval?: boolean;
  approval_settings?: StepApprovalSettings;
  shared_prompt_template_id: string | null;
  shared_prompt_template_name: string | null;
  created_at: string;
  updated_at: string;
}

export interface DevopsPipelineStepFormData {
  id?: string;
  name: string;
  step_type: DevopsStepType;
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
export type DevopsPipelineRunStatus = 'pending' | 'queued' | 'running' | 'success' | 'failure' | 'cancelled';
export type DevopsTriggerType = 'manual' | 'webhook' | 'schedule' | 'retry';

export interface DevopsPipelineRun {
  id: string;
  run_number: number;
  status: DevopsPipelineRunStatus;
  trigger_type: DevopsTriggerType;
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
  step_executions?: DevopsStepExecution[];
  created_at: string;
  updated_at: string;
}

// Step Execution types
export type DevopsStepExecutionStatus = 'pending' | 'running' | 'waiting_approval' | 'success' | 'failure' | 'cancelled' | 'skipped';

export interface DevopsStepExecution {
  id: string;
  status: DevopsStepExecutionStatus;
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

// API Response types
export interface DevopsPipelinesResponse {
  pipelines: DevopsPipeline[];
  meta: {
    total: number;
    active_count: number;
    total_runs: number;
  };
}

export interface DevopsPipelineRunsResponse {
  pipeline_runs: DevopsPipelineRun[];
  meta: {
    total: number;
    page: number;
    per_page: number;
    total_pages: number;
    status_counts: Record<string, number>;
  };
}

// Export YAML response
export interface DevopsPipelineExportResponse {
  pipeline_id: string;
  pipeline_name: string;
  yaml: string;
  generated_at: string;
}
