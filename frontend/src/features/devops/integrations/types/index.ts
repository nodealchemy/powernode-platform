// Integration Types

export type IntegrationType = 'github_action' | 'webhook' | 'mcp_server' | 'rest_api' | 'custom';
export type InstanceStatus = 'pending' | 'active' | 'paused' | 'error';
export type ExecutionStatus = 'queued' | 'running' | 'completed' | 'failed' | 'cancelled';
export type CredentialType = 'github_app' | 'oauth2' | 'api_key' | 'bearer_token' | 'basic';

// Integration Template (System-wide)
export interface IntegrationTemplate {
  id: string;
  name: string;
  slug: string;
  description?: string;
  integration_type: IntegrationType;
  category: string;
  version: string;
  is_public: boolean;
  is_featured: boolean;
  usage_count: number;
  configuration_schema: Record<string, unknown>;
  credential_requirements: Record<string, unknown>;
  capabilities: string[];
  input_schema: Record<string, unknown>;
  output_schema: Record<string, unknown>;
  default_configuration: Record<string, unknown>;
  icon_url?: string;
  documentation_url?: string;
  created_at: string;
  updated_at: string;
}

export interface IntegrationTemplateSummary {
  id: string;
  name: string;
  slug: string;
  description?: string;
  integration_type: IntegrationType;
  category: string;
  is_featured: boolean;
  usage_count: number;
  icon_url?: string;
}

// Integration Instance (Per-Account)
export interface IntegrationInstance {
  id: string;
  account_id: string;
  integration_template_id: string;
  integration_credential_id?: string;
  name: string;
  slug: string;
  status: InstanceStatus;
  configuration: Record<string, unknown>;
  runtime_state: Record<string, unknown>;
  health_metrics: HealthMetrics;
  execution_count: number;
  success_count: number;
  failure_count: number;
  last_executed_at?: string;
  activated_at?: string;
  deactivated_at?: string;
  created_at: string;
  updated_at: string;
  integration_template?: IntegrationTemplateSummary;
  integration_credential?: IntegrationCredentialSummary;
}

export interface IntegrationInstanceSummary {
  id: string;
  name: string;
  slug: string;
  status: InstanceStatus;
  integration_template?: IntegrationTemplateSummary;
  execution_count: number;
  success_count: number;
  failure_count: number;
  last_executed_at?: string;
}

export interface HealthMetrics {
  last_health_check?: string;
  health_status?: 'healthy' | 'degraded' | 'unhealthy' | 'unknown';
  last_error?: string;
  response_time_ms?: number;
  consecutive_failures?: number;
  last_failure_at?: string;
  last_execution_success?: boolean;
}

// Integration Credential
export interface IntegrationCredential {
  id: string;
  account_id: string;
  name: string;
  credential_type: CredentialType;
  scopes: string[];
  metadata: Record<string, unknown>;
  is_default: boolean;
  expires_at?: string;
  rotated_at?: string;
  created_at: string;
  updated_at: string;
}

export interface IntegrationCredentialSummary {
  id: string;
  name: string;
  credential_type: CredentialType;
  is_default: boolean;
  expires_at?: string;
}

// Integration Execution
export interface IntegrationExecution {
  id: string;
  integration_instance_id: string;
  account_id: string;
  status: ExecutionStatus;
  input_data: Record<string, unknown>;
  output_data?: Record<string, unknown>;
  error_message?: string;
  error_class?: string;
  triggered_by?: string;
  execution_time_ms?: number;
  response_code?: number;
  response_size_bytes?: number;
  retry_count: number;
  started_at?: string;
  completed_at?: string;
  created_at: string;
  integration_instance?: IntegrationInstanceSummary;
}

export interface IntegrationExecutionSummary {
  id: string;
  status: ExecutionStatus;
  triggered_by?: string;
  execution_time_ms?: number;
  created_at: string;
  completed_at?: string;
}

// API Response Types
export interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

export interface TemplatesResponse {
  success: boolean;
  data?: {
    templates: IntegrationTemplateSummary[];
    pagination: Pagination;
  };
  error?: string;
}

export interface TemplateResponse {
  success: boolean;
  data?: {
    template: IntegrationTemplate;
  };
  error?: string;
}

export interface InstancesResponse {
  success: boolean;
  data?: {
    instances: IntegrationInstanceSummary[];
    pagination: Pagination;
  };
  error?: string;
}

export interface InstanceResponse {
  success: boolean;
  data?: {
    instance: IntegrationInstance;
  };
  error?: string;
}

export interface CredentialsResponse {
  success: boolean;
  data?: {
    credentials: IntegrationCredential[];
    pagination: Pagination;
  };
  error?: string;
}

export interface CredentialResponse {
  success: boolean;
  data?: {
    credential: IntegrationCredential;
  };
  error?: string;
}

export interface ExecutionsResponse {
  success: boolean;
  data?: {
    executions: IntegrationExecutionSummary[];
    pagination: Pagination;
  };
  error?: string;
}

export interface ExecutionResponse {
  success: boolean;
  data?: {
    execution: IntegrationExecution;
  };
  error?: string;
}

export interface ExecutionStatsResponse {
  success: boolean;
  data?: {
    stats: {
      total: number;
      completed: number;
      failed: number;
      cancelled: number;
      running: number;
      queued: number;
      avg_execution_time_ms?: number;
      success_rate: number;
      by_day: Record<string, number>;
      by_status: Record<string, number>;
    };
  };
  error?: string;
}

export interface TestConnectionResponse {
  success: boolean;
  data?: {
    result: {
      success: boolean;
      message?: string;
      error?: string;
    };
    tested_at: string;
  };
  error?: string;
}

export interface ExecuteResponse {
  success: boolean;
  data?: {
    result: Record<string, unknown>;
    execution_id: string;
    execution_time_ms?: number;
  };
  error?: string;
}

// Form Data Types
export interface InstanceFormData {
  name: string;
  template_id: string;
  credential_id?: string;
  configuration?: Record<string, unknown>;
}

export interface CredentialFormData {
  name: string;
  credential_type: CredentialType;
  credentials: Record<string, string>;
  scopes?: string[];
  metadata?: Record<string, unknown>;
}

// Filter Types
export interface TemplateFilters {
  type?: IntegrationType;
  category?: string;
  featured?: boolean;
  q?: string;
}

export interface InstanceFilters {
  status?: InstanceStatus;
  type?: IntegrationType;
}

export interface ExecutionFilters {
  instance_id?: string;
  status?: ExecutionStatus;
  since?: string;
  until?: string;
}
