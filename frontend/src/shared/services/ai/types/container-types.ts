/**
 * Container Orchestration Types
 *
 * Types for MCP container execution, templates, and quotas
 */

// Status types
export type ContainerStatus = 'pending' | 'provisioning' | 'running' | 'completed' | 'failed' | 'cancelled' | 'timeout';

export type TemplateVisibility = 'private' | 'account' | 'public';

export type TemplateStatus = 'draft' | 'active' | 'deprecated';

// Container Instance types
export interface ContainerInstance {
  id: string;
  execution_id: string;
  account_id: string;
  template_id?: string;
  template_name?: string;
  a2a_task_id?: string;
  image_name: string;
  image_tag: string;
  status: ContainerStatus;
  exit_code?: string;
  input_parameters: Record<string, unknown>;
  output_data?: Record<string, unknown>;
  error_message?: string;
  logs?: string;
  artifacts: string[];
  timeout_seconds: number;
  sandbox_enabled: boolean;
  runner_name?: string;
  runner_labels: string[];
  gitea_workflow_run_id?: string;
  vault_token_id?: string;
  environment_variables: Record<string, string>;
  memory_used_mb?: number;
  cpu_used_millicores?: number;
  storage_used_bytes?: number;
  network_bytes_in?: number;
  network_bytes_out?: number;
  security_violations: SecurityViolation[];
  started_at?: string;
  completed_at?: string;
  duration_ms?: number;
  triggered_by?: string;
  created_at: string;
  updated_at: string;
}

export interface ContainerInstanceSummary {
  id: string;
  execution_id: string;
  status: ContainerStatus;
  image_name: string;
  exit_code?: string;
  duration_ms?: number;
  started_at?: string;
  completed_at?: string;
  runner_name?: string;
}

export interface SecurityViolation {
  type: string;
  description: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  details: Record<string, unknown>;
  detected_at: string;
}

export interface ExecuteContainerRequest {
  template_id: string;
  input_parameters?: Record<string, unknown>;
  timeout_seconds?: number;
  a2a_task_id?: string;
}

export interface ContainerFilters {
  status?: ContainerStatus;
  template_id?: string;
  active?: boolean;
  finished?: boolean;
  since?: string;
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

// Container Template types
export interface ContainerTemplate {
  id: string;
  account_id: string;
  name: string;
  description?: string;
  image_name: string;
  image_tag: string;
  category?: string;
  visibility: TemplateVisibility;
  status: TemplateStatus;
  featured: boolean;
  timeout_seconds: number;
  memory_mb: number;
  cpu_millicores: number;
  sandbox_mode: boolean;
  network_access: boolean;
  input_schema?: Record<string, unknown>;
  output_schema?: Record<string, unknown>;
  environment_variables: Record<string, string>;
  labels: Record<string, unknown>;
  allowed_egress_domains: string[];
  execution_count: number;
  success_count: number;
  failure_count: number;
  avg_duration_ms?: number;
  last_execution_at?: string;
  created_by?: string;
  created_at: string;
  updated_at: string;
}

export interface ContainerTemplateSummary {
  id: string;
  name: string;
  description?: string;
  category?: string;
  image_name: string;
  visibility: TemplateVisibility;
  status: TemplateStatus;
  execution_count: number;
  success_rate?: number;
}

export interface CreateContainerTemplateRequest {
  name: string;
  description?: string;
  image_name: string;
  image_tag?: string;
  category?: string;
  visibility?: TemplateVisibility;
  timeout_seconds?: number;
  memory_mb?: number;
  cpu_millicores?: number;
  sandbox_mode?: boolean;
  network_access?: boolean;
  input_schema?: Record<string, unknown>;
  output_schema?: Record<string, unknown>;
  environment_variables?: Record<string, string>;
  labels?: Record<string, unknown>;
  allowed_egress_domains?: string[];
}

export interface UpdateContainerTemplateRequest {
  name?: string;
  description?: string;
  image_name?: string;
  image_tag?: string;
  category?: string;
  visibility?: TemplateVisibility;
  timeout_seconds?: number;
  memory_mb?: number;
  cpu_millicores?: number;
  sandbox_mode?: boolean;
  network_access?: boolean;
  input_schema?: Record<string, unknown>;
  output_schema?: Record<string, unknown>;
  environment_variables?: Record<string, string>;
  labels?: Record<string, unknown>;
  allowed_egress_domains?: string[];
}

export interface TemplateFilters {
  category?: string;
  active?: boolean;
  public?: boolean;
  query?: string;
  sort?: 'popular' | 'recent' | 'name';
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

export interface TemplateStats {
  total_executions: number;
  successful: number;
  failed: number;
  avg_duration_ms?: number;
  success_rate?: number;
  last_execution_at?: string;
}

// Resource Quota types
export interface ResourceQuota {
  id: string;
  account_id: string;
  max_concurrent_containers: number;
  max_containers_per_hour: number;
  max_containers_per_day: number;
  max_memory_mb: number;
  max_cpu_millicores: number;
  max_storage_bytes: number;
  max_execution_time_seconds: number;
  allow_network_access: boolean;
  allowed_egress_domains: string[];
  allow_overage: boolean;
  overage_rate_per_container?: number;
  current_running_containers: number;
  containers_used_this_hour: number;
  containers_used_today: number;
  created_at: string;
  updated_at: string;
}

export interface QuotaStatus {
  concurrent: {
    used: number;
    limit: number;
    available: number;
    ok: boolean;
  };
  hourly: {
    used: number;
    limit: number;
    available: number;
    ok: boolean;
  };
  daily: {
    used: number;
    limit: number;
    available: number;
    ok: boolean;
  };
  can_execute: boolean;
  allow_overage: boolean;
}

export interface ResourceLimits {
  memory_mb: number;
  cpu_millicores: number;
  storage_bytes: number;
  execution_time_seconds: number;
}

export interface QuotaResponse {
  quota: ResourceQuota;
  quota_status: QuotaStatus;
  resource_limits: ResourceLimits;
  network_allowed: boolean;
  overage_cost: number;
}

export interface UpdateQuotaRequest {
  max_concurrent_containers?: number;
  max_containers_per_hour?: number;
  max_containers_per_day?: number;
  max_memory_mb?: number;
  max_cpu_millicores?: number;
  max_storage_bytes?: number;
  max_execution_time_seconds?: number;
  allow_network_access?: boolean;
  allowed_egress_domains?: string[];
  allow_overage?: boolean;
  overage_rate_per_container?: number;
}

export interface UsageHistory {
  daily_usage: Record<string, number>;
  hourly_usage: Record<string, number>;
}

export interface OverageInfo {
  allow_overage: boolean;
  overage_rate?: number;
  current_overage_cost: number;
  containers_over_limit: number;
}

// Container Stats
export interface ContainerStats {
  total: number;
  active: number;
  completed: number;
  failed: number;
  avg_duration_ms?: number;
  success_rate: number;
  by_status: Record<ContainerStatus, number>;
  by_template: Record<string, number>;
}
