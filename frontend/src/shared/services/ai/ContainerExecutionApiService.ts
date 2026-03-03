import { BaseApiService, PaginatedResponse } from '@/shared/services/ai/BaseApiService';
import type {
  ContainerInstance,
  ContainerInstanceSummary,
  ExecuteContainerRequest,
  ContainerFilters,
  ContainerTemplate,
  ContainerTemplateSummary,
  ContainerImageBuild,
  CreateContainerTemplateRequest,
  UpdateContainerTemplateRequest,
  CreateImageRepoRequest,
  CreateImageRepoResponse,
  TemplateFilters,
  TemplateStats,
  QuotaResponse,
  UpdateQuotaRequest,
  UsageHistory,
  OverageInfo,
  ContainerStats,
} from '@/shared/services/ai/types/container-types';

/**
 * ContainerExecutionApiService - Container Orchestration API Client
 *
 * Provides access to container execution, templates, and quota management.
 *
 * Endpoint structure:
 * Containers:
 * - GET    /api/v1/devops/containers
 * - POST   /api/v1/devops/containers/execute
 * - GET    /api/v1/devops/containers/:id
 * - POST   /api/v1/devops/containers/:id/cancel
 * - GET    /api/v1/devops/containers/:id/logs
 * - GET    /api/v1/devops/containers/:id/artifacts
 * - GET    /api/v1/devops/containers/active
 * - GET    /api/v1/devops/containers/stats
 *
 * Templates:
 * - GET    /api/v1/devops/container_templates
 * - POST   /api/v1/devops/container_templates
 * - GET    /api/v1/devops/container_templates/:id
 * - PATCH  /api/v1/devops/container_templates/:id
 * - DELETE /api/v1/devops/container_templates/:id
 * - POST   /api/v1/devops/container_templates/:id/publish
 * - POST   /api/v1/devops/container_templates/:id/unpublish
 * - GET    /api/v1/devops/container_templates/:id/executions
 * - GET    /api/v1/devops/container_templates/:id/stats
 * - GET    /api/v1/devops/container_templates/categories
 * - GET    /api/v1/devops/container_templates/featured
 *
 * Quotas:
 * - GET    /api/v1/devops/container_quotas
 * - PATCH  /api/v1/devops/container_quotas
 * - POST   /api/v1/devops/container_quotas/reset_usage
 * - GET    /api/v1/devops/container_quotas/usage_history
 * - GET    /api/v1/devops/container_quotas/overage
 * - PATCH  /api/v1/devops/container_quotas/overage
 */

class ContainerExecutionApiService extends BaseApiService {
  private containersPath = '/devops/containers';
  private templatesPath = '/devops/container_templates';
  private quotasPath = '/devops/container_quotas';

  // ===================================================================
  // Container Operations
  // ===================================================================

  /**
   * Get list of container instances
   * GET /api/v1/devops/containers
   */
  async getContainers(filters?: ContainerFilters): Promise<PaginatedResponse<ContainerInstanceSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ContainerInstanceSummary>>(this.containersPath + queryString);
  }

  /**
   * Get single container instance
   * GET /api/v1/devops/containers/:id
   */
  async getContainer(containerId: string): Promise<{ instance: ContainerInstance }> {
    return this.get<{ instance: ContainerInstance }>(`${this.containersPath}/${containerId}`);
  }

  /**
   * Execute a container
   * POST /api/v1/devops/containers/execute
   */
  async executeContainer(request: ExecuteContainerRequest): Promise<{ instance: ContainerInstance }> {
    return this.post<{ instance: ContainerInstance }>(`${this.containersPath}/execute`, request);
  }

  /**
   * Cancel a container execution
   * POST /api/v1/devops/containers/:id/cancel
   */
  async cancelContainer(containerId: string, reason?: string): Promise<{ instance: ContainerInstance }> {
    return this.post<{ instance: ContainerInstance }>(`${this.containersPath}/${containerId}/cancel`, { reason });
  }

  /**
   * Get container logs
   * GET /api/v1/devops/containers/:id/logs
   */
  async getContainerLogs(containerId: string): Promise<{ execution_id: string; logs: string; status: string }> {
    return this.get<{ execution_id: string; logs: string; status: string }>(`${this.containersPath}/${containerId}/logs`);
  }

  /**
   * Get container artifacts
   * GET /api/v1/devops/containers/:id/artifacts
   */
  async getContainerArtifacts(containerId: string): Promise<{ execution_id: string; artifacts: string[]; status: string }> {
    return this.get<{ execution_id: string; artifacts: string[]; status: string }>(`${this.containersPath}/${containerId}/artifacts`);
  }

  /**
   * Get active containers
   * GET /api/v1/devops/containers/active
   */
  async getActiveContainers(): Promise<{ items: ContainerInstanceSummary[]; count: number }> {
    return this.get<{ items: ContainerInstanceSummary[]; count: number }>(`${this.containersPath}/active`);
  }

  /**
   * Get container statistics
   * GET /api/v1/devops/containers/stats
   */
  async getContainerStats(): Promise<{ stats: ContainerStats }> {
    return this.get<{ stats: ContainerStats }>(`${this.containersPath}/stats`);
  }

  // ===================================================================
  // Template Operations
  // ===================================================================

  /**
   * Get list of container templates
   * GET /api/v1/devops/container_templates
   */
  async getTemplates(filters?: TemplateFilters): Promise<PaginatedResponse<ContainerTemplateSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ContainerTemplateSummary>>(this.templatesPath + queryString);
  }

  /**
   * Get single template
   * GET /api/v1/devops/container_templates/:id
   */
  async getTemplate(templateId: string): Promise<{ template: ContainerTemplate }> {
    return this.get<{ template: ContainerTemplate }>(`${this.templatesPath}/${templateId}`);
  }

  /**
   * Create a new template
   * POST /api/v1/devops/container_templates
   */
  async createTemplate(request: CreateContainerTemplateRequest): Promise<{ template: ContainerTemplate }> {
    return this.post<{ template: ContainerTemplate }>(this.templatesPath, { template: request });
  }

  /**
   * Update a template
   * PATCH /api/v1/devops/container_templates/:id
   */
  async updateTemplate(templateId: string, request: UpdateContainerTemplateRequest): Promise<{ template: ContainerTemplate }> {
    return this.patch<{ template: ContainerTemplate }>(`${this.templatesPath}/${templateId}`, { template: request });
  }

  /**
   * Delete a template
   * DELETE /api/v1/devops/container_templates/:id
   */
  async deleteTemplate(templateId: string): Promise<{ message: string }> {
    return this.delete<{ message: string }>(`${this.templatesPath}/${templateId}`);
  }

  /**
   * Publish a template
   * POST /api/v1/devops/container_templates/:id/publish
   */
  async publishTemplate(templateId: string): Promise<{ template: ContainerTemplate }> {
    return this.post<{ template: ContainerTemplate }>(`${this.templatesPath}/${templateId}/publish`);
  }

  /**
   * Unpublish a template
   * POST /api/v1/devops/container_templates/:id/unpublish
   */
  async unpublishTemplate(templateId: string): Promise<{ template: ContainerTemplate }> {
    return this.post<{ template: ContainerTemplate }>(`${this.templatesPath}/${templateId}/unpublish`);
  }

  /**
   * Get template executions
   * GET /api/v1/devops/container_templates/:id/executions
   */
  async getTemplateExecutions(templateId: string, filters?: ContainerFilters): Promise<PaginatedResponse<ContainerInstanceSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ContainerInstanceSummary>>(`${this.templatesPath}/${templateId}/executions${queryString}`);
  }

  /**
   * Get template statistics
   * GET /api/v1/devops/container_templates/:id/stats
   */
  async getTemplateStats(templateId: string): Promise<{ stats: TemplateStats }> {
    return this.get<{ stats: TemplateStats }>(`${this.templatesPath}/${templateId}/stats`);
  }

  /**
   * Get template categories
   * GET /api/v1/devops/container_templates/categories
   */
  async getTemplateCategories(): Promise<{ categories: string[] }> {
    return this.get<{ categories: string[] }>(`${this.templatesPath}/categories`);
  }

  /**
   * Get featured templates
   * GET /api/v1/devops/container_templates/featured
   */
  async getFeaturedTemplates(limit?: number): Promise<{ items: ContainerTemplateSummary[] }> {
    const queryString = limit ? `?limit=${limit}` : '';
    return this.get<{ items: ContainerTemplateSummary[] }>(`${this.templatesPath}/featured${queryString}`);
  }

  // ===================================================================
  // Build Operations
  // ===================================================================

  /**
   * Trigger a manual build for a template
   * POST /api/v1/devops/container_templates/:id/trigger_build
   */
  async triggerBuild(templateId: string): Promise<{ build: ContainerImageBuild }> {
    return this.post<{ build: ContainerImageBuild }>(`${this.templatesPath}/${templateId}/trigger_build`);
  }

  /**
   * Get build history for a template
   * GET /api/v1/devops/container_templates/:id/builds
   */
  async getBuildHistory(templateId: string, filters?: { status?: string; page?: number; per_page?: number }): Promise<PaginatedResponse<ContainerImageBuild>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ContainerImageBuild>>(`${this.templatesPath}/${templateId}/builds${queryString}`);
  }

  /**
   * Create a new image repository with Gitea scaffolding
   * POST /api/v1/devops/container_templates/create_image_repo
   */
  async createImageRepo(request: CreateImageRepoRequest): Promise<CreateImageRepoResponse> {
    return this.post<CreateImageRepoResponse>(`${this.templatesPath}/create_image_repo`, { image_repo: request });
  }

  // ===================================================================
  // Quota Operations
  // ===================================================================

  /**
   * Get quota information
   * GET /api/v1/devops/container_quotas
   */
  async getQuota(): Promise<QuotaResponse> {
    return this.get<QuotaResponse>(this.quotasPath);
  }

  /**
   * Update quota settings
   * PATCH /api/v1/devops/container_quotas
   */
  async updateQuota(request: UpdateQuotaRequest): Promise<{ quota: QuotaResponse; message: string }> {
    return this.patch<{ quota: QuotaResponse; message: string }>(this.quotasPath, { quota: request });
  }

  /**
   * Reset usage counters
   * POST /api/v1/devops/container_quotas/reset_usage
   */
  async resetUsage(): Promise<{ quota: QuotaResponse; message: string }> {
    return this.post<{ quota: QuotaResponse; message: string }>(`${this.quotasPath}/reset_usage`);
  }

  /**
   * Get usage history
   * GET /api/v1/devops/container_quotas/usage_history
   */
  async getUsageHistory(): Promise<UsageHistory> {
    return this.get<UsageHistory>(`${this.quotasPath}/usage_history`);
  }

  /**
   * Get overage information
   * GET /api/v1/devops/container_quotas/overage
   */
  async getOverageInfo(): Promise<OverageInfo> {
    return this.get<OverageInfo>(`${this.quotasPath}/overage`);
  }

  /**
   * Update overage settings
   * PATCH /api/v1/devops/container_quotas/overage
   */
  async updateOverage(allowOverage: boolean, overageRate?: number): Promise<{ allow_overage: boolean; overage_rate?: number; message: string }> {
    return this.patch<{ allow_overage: boolean; overage_rate?: number; message: string }>(`${this.quotasPath}/overage`, {
      allow_overage: allowOverage,
      overage_rate: overageRate,
    });
  }
}

export const containerExecutionApi = new ContainerExecutionApiService();
