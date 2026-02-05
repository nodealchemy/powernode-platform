/**
 * DevOps API Service
 * Phase 4: AI Pipeline Templates for DevOps
 *
 * Revenue Model: Template marketplace + enterprise customization
 * - Community templates: free
 * - Premium templates: $29-99 one-time
 * - Custom template development: $2,000-10,000
 * - Enterprise template library: $199/mo
 */

import { BaseApiService, PaginatedResponse, QueryFilters } from './BaseApiService';

// Types
export interface DevopsTemplate {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  category: string;
  template_type: string;
  status: 'draft' | 'pending_review' | 'published' | 'archived' | 'deprecated';
  visibility: 'private' | 'team' | 'public' | 'marketplace';
  version: string;
  installation_count: number;
  average_rating: number | null;
  is_system: boolean;
  is_featured: boolean;
  price_usd: number | null;
  published_at: string | null;
  is_owner: boolean;
  // Detailed fields
  workflow_definition?: Record<string, unknown>;
  trigger_config?: Record<string, unknown>;
  input_schema?: Record<string, unknown>;
  output_schema?: Record<string, unknown>;
  variables?: unknown[];
  secrets_required?: string[];
  integrations_required?: string[];
  tags?: string[];
  usage_guide?: string;
}

export interface DevopsInstallation {
  id: string;
  status: 'active' | 'paused' | 'disabled' | 'pending_update';
  installed_version: string;
  execution_count: number;
  success_count: number;
  failure_count: number;
  success_rate: number;
  last_executed_at: string | null;
  created_at: string;
  template: {
    id: string;
    name: string;
  };
}

export interface PipelineExecution {
  id: string;
  execution_id: string;
  pipeline_type: 'pr_review' | 'commit_analysis' | 'deployment' | 'release' | 'scheduled' | 'manual';
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled' | 'timeout';
  trigger_source: string | null;
  trigger_event: string | null;
  repository_id: string | null;
  branch: string | null;
  commit_sha: string | null;
  pull_request_number: string | null;
  duration_ms: number | null;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
  // Detailed fields
  input_data?: Record<string, unknown>;
  output_data?: Record<string, unknown>;
  ai_analysis?: Record<string, unknown>;
  metrics?: Record<string, unknown>;
}

export interface DeploymentRisk {
  id: string;
  assessment_id: string;
  deployment_type: string;
  target_environment: string;
  risk_level: 'low' | 'medium' | 'high' | 'critical';
  risk_score: number | null;
  status: 'pending' | 'assessed' | 'approved' | 'rejected' | 'overridden';
  decision: string | null;
  requires_approval: boolean;
  risk_factors: unknown[];
  change_analysis: Record<string, unknown>;
  impact_analysis: Record<string, unknown>;
  recommendations: string[];
  mitigations: unknown[];
  summary: string | null;
  decision_rationale: string | null;
  assessed_at: string | null;
  decision_at: string | null;
  created_at: string;
}

export interface CodeReview {
  id: string;
  review_id: string;
  status: 'pending' | 'analyzing' | 'completed' | 'failed' | 'partial';
  repository_id: string | null;
  pull_request_number: string | null;
  commit_sha: string | null;
  base_branch: string | null;
  head_branch: string | null;
  files_reviewed: number;
  lines_added: number;
  lines_removed: number;
  issues_found: number;
  critical_issues: number;
  suggestions_count: number;
  overall_rating: string | null;
  approval_recommendation: string;
  tokens_used: number;
  cost_usd: number;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
  // Detailed fields
  file_analyses?: unknown[];
  issues?: unknown[];
  suggestions?: unknown[];
  security_findings?: unknown[];
  quality_metrics?: Record<string, unknown>;
  summary?: string;
}

export interface DevopsAnalytics {
  total_executions: number;
  by_status: Record<string, number>;
  by_type: Record<string, number>;
  success_rate: number;
  average_duration_ms: number | null;
  deployments: {
    total: number;
    by_risk_level: Record<string, number>;
    by_decision: Record<string, number>;
  };
  code_reviews: {
    total: number;
    issues_found: number;
    critical_issues: number;
  };
}

export interface TemplateFilters extends QueryFilters {
  query?: string;
  category?: string;
  template_type?: string;
}

export interface ExecutionFilters extends QueryFilters {
  pipeline_type?: string;
  repository_id?: string;
}

export interface RiskFilters extends QueryFilters {
  environment?: string;
  risk_level?: string;
}

export interface ReviewFilters extends QueryFilters {
  repository_id?: string;
}

class DevopsApiService extends BaseApiService {
  private basePath = '/ai/devops';

  // Templates
  async getTemplates(filters: TemplateFilters = {}): Promise<PaginatedResponse<DevopsTemplate>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<DevopsTemplate>>(`${this.basePath}/templates${queryString}`);
  }

  async getTemplate(id: string): Promise<{ template: DevopsTemplate }> {
    return this.get(`${this.basePath}/templates/${id}`);
  }

  async createTemplate(data: Record<string, unknown>): Promise<{ template: DevopsTemplate }> {
    return this.post(`${this.basePath}/templates`, data);
  }

  async updateTemplate(id: string, data: Record<string, unknown>): Promise<{ template: DevopsTemplate }> {
    return this.patch(`${this.basePath}/templates/${id}`, data);
  }

  // Installations
  async getInstallations(page = 1, perPage = 20): Promise<PaginatedResponse<DevopsInstallation>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<DevopsInstallation>>(`${this.basePath}/installations${queryString}`);
  }

  async installTemplate(
    templateId: string,
    data: { variable_values?: Record<string, unknown>; custom_config?: Record<string, unknown> } = {}
  ): Promise<{ installation: DevopsInstallation }> {
    return this.post(`${this.basePath}/templates/${templateId}/install`, data);
  }

  async uninstallTemplate(installationId: string): Promise<void> {
    return this.delete(`${this.basePath}/installations/${installationId}`);
  }

  // Executions
  async getExecutions(filters: ExecutionFilters = {}): Promise<PaginatedResponse<PipelineExecution>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<PipelineExecution>>(`${this.basePath}/executions${queryString}`);
  }

  async createExecution(data: {
    pipeline_type: string;
    installation_id?: string;
    input_data?: Record<string, unknown>;
    trigger_source?: string;
    trigger_event?: string;
    repository_id?: string;
    branch?: string;
    commit_sha?: string;
    pull_request_number?: string;
  }): Promise<{ execution: PipelineExecution }> {
    return this.post(`${this.basePath}/executions`, data);
  }

  async getExecution(id: string): Promise<{ execution: PipelineExecution }> {
    return this.get(`${this.basePath}/executions/${id}`);
  }

  // Deployment Risks
  async getRisks(filters: RiskFilters = {}): Promise<PaginatedResponse<DeploymentRisk>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<DeploymentRisk>>(`${this.basePath}/risks${queryString}`);
  }

  async assessRisk(data: {
    deployment_type: string;
    target_environment: string;
    change_data?: Record<string, unknown>;
    execution_id?: string;
  }): Promise<{ assessment: DeploymentRisk }> {
    return this.post(`${this.basePath}/risks/assess`, data);
  }

  async approveRisk(id: string, rationale?: string): Promise<{ assessment: DeploymentRisk }> {
    return this.put(`${this.basePath}/risks/${id}/approve`, { rationale });
  }

  async rejectRisk(id: string, rationale?: string): Promise<{ assessment: DeploymentRisk }> {
    return this.put(`${this.basePath}/risks/${id}/reject`, { rationale });
  }

  // Code Reviews
  async getReviews(filters: ReviewFilters = {}): Promise<PaginatedResponse<CodeReview>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<CodeReview>>(`${this.basePath}/reviews${queryString}`);
  }

  async createReview(data: {
    execution_id?: string;
    repository_id?: string;
    pull_request_number?: string;
    commit_sha?: string;
    base_branch?: string;
    head_branch?: string;
  }): Promise<{ review: CodeReview }> {
    return this.post(`${this.basePath}/reviews`, data);
  }

  async getReview(id: string): Promise<{ review: CodeReview }> {
    return this.get(`${this.basePath}/reviews/${id}`);
  }

  // Analytics
  async getAnalytics(startDate?: string, endDate?: string): Promise<{ analytics: DevopsAnalytics }> {
    const params: Record<string, string> = {};
    if (startDate) params.start_date = startDate;
    if (endDate) params.end_date = endDate;
    const queryString = this.buildQueryString(params);
    return this.get(`${this.basePath}/analytics${queryString}`);
  }
}

export const devopsApi = new DevopsApiService();
