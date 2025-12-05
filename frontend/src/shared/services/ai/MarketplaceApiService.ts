import { BaseApiService, QueryFilters, PaginatedResponse } from './BaseApiService';
import type { WorkflowTemplate } from '../../types/workflow';

/**
 * MarketplaceApiService - Marketplace Controller API Client
 *
 * Provides access to the consolidated Marketplace Controller endpoints.
 * Replaces the following old controllers:
 * - workflow_marketplace_controller
 * - ai_workflow_templates_controller
 *
 * New endpoint structure:
 * - GET    /api/v1/ai/marketplace/templates
 * - POST   /api/v1/ai/marketplace/templates
 * - GET    /api/v1/ai/marketplace/templates/:id
 * - PATCH  /api/v1/ai/marketplace/templates/:id
 * - DELETE /api/v1/ai/marketplace/templates/:id
 * - POST   /api/v1/ai/marketplace/templates/:id/install
 * - POST   /api/v1/ai/marketplace/templates/:id/publish
 * - GET    /api/v1/ai/marketplace/templates/:id/validate
 * - POST   /api/v1/ai/marketplace/templates/:id/rate
 * - GET    /api/v1/ai/marketplace/templates/:id/analytics
 * - POST   /api/v1/ai/marketplace/templates/from_workflow
 * - POST   /api/v1/ai/marketplace/templates/publish_workflow
 * - GET    /api/v1/ai/marketplace/templates/featured
 * - GET    /api/v1/ai/marketplace/templates/popular
 * - GET    /api/v1/ai/marketplace/templates/categories
 * - GET    /api/v1/ai/marketplace/templates/tags
 * - GET    /api/v1/ai/marketplace/templates/statistics
 * - GET    /api/v1/ai/marketplace/discover
 * - POST   /api/v1/ai/marketplace/search
 * - GET    /api/v1/ai/marketplace/recommendations
 * - POST   /api/v1/ai/marketplace/compare
 * - GET    /api/v1/ai/marketplace/installations
 * - GET    /api/v1/ai/marketplace/installations/:id
 * - DELETE /api/v1/ai/marketplace/installations/:id
 * - GET    /api/v1/ai/marketplace/updates
 * - POST   /api/v1/ai/marketplace/updates/apply
 */

export interface TemplateFilters extends QueryFilters {
  category?: string;
  tags?: string[];
  author_id?: string;
  visibility?: 'public' | 'account' | 'private';
  min_rating?: number;
  verified_only?: boolean;
}

export interface SearchFilters {
  query: string;
  category?: string;
  tags?: string[];
  min_rating?: number;
  page?: number;
  per_page?: number;
}

export interface Template extends WorkflowTemplate {
  install_count: number;
  rating_average: number;
  rating_count: number;
  author: {
    id: string;
    name: string;
    avatar_url?: string;
  };
  verified: boolean;
  featured: boolean;
}

export interface Installation {
  id: string;
  template_id: string;
  template_name: string;
  template_version: string;
  workflow_id?: string;
  workflow_name?: string;
  installed_at: string;
  customizations?: Record<string, any>;
  status: 'active' | 'inactive';
}

export interface TemplateAnalytics {
  install_count: number;
  active_installations: number;
  rating_average: number;
  rating_distribution: Record<string, number>;
  usage_trends: Array<{
    date: string;
    installs: number;
    active_users: number;
  }>;
  geographic_distribution: Record<string, number>;
}

export interface Rating {
  rating: number; // 1-5
  review?: string;
  user_id?: string;
}

export interface Category {
  id: string;
  name: string;
  description: string;
  template_count: number;
  icon?: string;
}

export interface TemplateStatistics {
  total_templates: number;
  public_templates: number;
  total_installations: number;
  avg_rating: number;
  templates_by_category: Record<string, number>;
  trending_templates: Template[];
}

export interface CreateTemplateRequest {
  name: string;
  description: string;
  category: string;
  tags?: string[];
  workflow_definition: Record<string, any>;
  configuration_schema?: Record<string, any>;
  visibility?: 'public' | 'account' | 'private';
  metadata?: Record<string, any>;
}

export interface InstallTemplateRequest {
  workflow_name?: string;
  customizations?: Record<string, any>;
  auto_activate?: boolean;
}

export interface PublishWorkflowRequest {
  workflow_id: string;
  name: string;
  description: string;
  category: string;
  tags?: string[];
  visibility?: 'public' | 'account';
}

export interface CompareRequest {
  template_ids: string[];
  attributes?: string[];
}

export interface UpdateCheck {
  installation_id: string;
  current_version: string;
  latest_version: string;
  has_update: boolean;
  changelog?: string;
}

class MarketplaceApiService extends BaseApiService {
  private basePath = '/ai/marketplace';

  // ===================================================================
  // Template CRUD Operations
  // ===================================================================

  /**
   * Get list of templates
   * GET /api/v1/ai/marketplace/templates
   */
  async getTemplates(filters?: TemplateFilters): Promise<PaginatedResponse<Template>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<Template>>(`${this.basePath}/templates${queryString}`);
  }

  /**
   * Get single template
   * GET /api/v1/ai/marketplace/templates/:id
   */
  async getTemplate(id: string): Promise<Template> {
    return this.get<Template>(`${this.basePath}/templates/${id}`);
  }

  /**
   * Create new template
   * POST /api/v1/ai/marketplace/templates
   */
  async createTemplate(request: CreateTemplateRequest): Promise<Template> {
    return this.post<Template>(`${this.basePath}/templates`, { template: request });
  }

  /**
   * Update template
   * PATCH /api/v1/ai/marketplace/templates/:id
   */
  async updateTemplate(id: string, data: Partial<CreateTemplateRequest>): Promise<Template> {
    return this.patch<Template>(`${this.basePath}/templates/${id}`, { template: data });
  }

  /**
   * Delete template
   * DELETE /api/v1/ai/marketplace/templates/:id
   */
  async deleteTemplate(id: string): Promise<void> {
    return this.delete<void>(`${this.basePath}/templates/${id}`);
  }

  // ===================================================================
  // Template Actions
  // ===================================================================

  /**
   * Install template
   * POST /api/v1/ai/marketplace/templates/:id/install
   */
  async installTemplate(id: string, request?: InstallTemplateRequest): Promise<Installation> {
    return this.post<Installation>(`${this.basePath}/templates/${id}/install`, request);
  }

  /**
   * Publish template
   * POST /api/v1/ai/marketplace/templates/:id/publish
   */
  async publishTemplate(id: string): Promise<Template> {
    return this.post<Template>(`${this.basePath}/templates/${id}/publish`);
  }

  /**
   * Validate template
   * GET /api/v1/ai/marketplace/templates/:id/validate
   */
  async validateTemplate(id: string): Promise<any> {
    return this.get<any>(`${this.basePath}/templates/${id}/validate`);
  }

  /**
   * Rate template
   * POST /api/v1/ai/marketplace/templates/:id/rate
   */
  async rateTemplate(id: string, rating: Rating): Promise<{ success: boolean; new_average: number }> {
    return this.post<{ success: boolean; new_average: number }>(
      `${this.basePath}/templates/${id}/rate`,
      rating
    );
  }

  /**
   * Get template analytics
   * GET /api/v1/ai/marketplace/templates/:id/analytics
   */
  async getTemplateAnalytics(id: string): Promise<TemplateAnalytics> {
    return this.get<TemplateAnalytics>(`${this.basePath}/templates/${id}/analytics`);
  }

  // ===================================================================
  // Template Creation from Workflow
  // ===================================================================

  /**
   * Create template from existing workflow
   * POST /api/v1/ai/marketplace/templates/from_workflow
   */
  async createFromWorkflow(workflowId: string, templateData: Partial<CreateTemplateRequest>): Promise<Template> {
    return this.post<Template>(`${this.basePath}/templates/from_workflow`, {
      workflow_id: workflowId,
      template: templateData,
    });
  }

  /**
   * Publish workflow as template
   * POST /api/v1/ai/marketplace/templates/publish_workflow
   */
  async publishWorkflow(request: PublishWorkflowRequest): Promise<Template> {
    return this.post<Template>(`${this.basePath}/templates/publish_workflow`, request);
  }

  // ===================================================================
  // Template Collections
  // ===================================================================

  /**
   * Get featured templates
   * GET /api/v1/ai/marketplace/templates/featured
   */
  async getFeaturedTemplates(): Promise<Template[]> {
    return this.get<Template[]>(`${this.basePath}/templates/featured`);
  }

  /**
   * Get popular templates
   * GET /api/v1/ai/marketplace/templates/popular
   */
  async getPopularTemplates(): Promise<Template[]> {
    return this.get<Template[]>(`${this.basePath}/templates/popular`);
  }

  /**
   * Get template categories
   * GET /api/v1/ai/marketplace/templates/categories
   */
  async getCategories(): Promise<Category[]> {
    return this.get<Category[]>(`${this.basePath}/templates/categories`);
  }

  /**
   * Get available tags
   * GET /api/v1/ai/marketplace/templates/tags
   */
  async getTags(): Promise<string[]> {
    return this.get<string[]>(`${this.basePath}/templates/tags`);
  }

  /**
   * Get marketplace statistics
   * GET /api/v1/ai/marketplace/templates/statistics
   */
  async getStatistics(): Promise<TemplateStatistics> {
    return this.get<TemplateStatistics>(`${this.basePath}/templates/statistics`);
  }

  // ===================================================================
  // Discovery & Search
  // ===================================================================

  /**
   * Discover templates (curated list)
   * GET /api/v1/ai/marketplace/discover
   */
  async discoverTemplates(filters?: TemplateFilters): Promise<{
    featured: Template[];
    popular: Template[];
    new: Template[];
    recommended: Template[];
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get<{
      featured: Template[];
      popular: Template[];
      new: Template[];
      recommended: Template[];
    }>(`${this.basePath}/discover${queryString}`);
  }

  /**
   * Search templates
   * POST /api/v1/ai/marketplace/search
   */
  async searchTemplates(filters: SearchFilters): Promise<PaginatedResponse<Template>> {
    return this.post<PaginatedResponse<Template>>(`${this.basePath}/search`, filters);
  }

  /**
   * Get personalized recommendations
   * GET /api/v1/ai/marketplace/recommendations
   */
  async getRecommendations(): Promise<Template[]> {
    return this.get<Template[]>(`${this.basePath}/recommendations`);
  }

  /**
   * Compare templates
   * POST /api/v1/ai/marketplace/compare
   */
  async compareTemplates(request: CompareRequest): Promise<any> {
    return this.post<any>(`${this.basePath}/compare`, request);
  }

  // ===================================================================
  // Installations Management
  // ===================================================================

  /**
   * Get user's installations
   * GET /api/v1/ai/marketplace/installations
   */
  async getInstallations(filters?: QueryFilters): Promise<PaginatedResponse<Installation>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<Installation>>(`${this.basePath}/installations${queryString}`);
  }

  /**
   * Get single installation
   * GET /api/v1/ai/marketplace/installations/:id
   */
  async getInstallation(id: string): Promise<Installation> {
    return this.get<Installation>(`${this.basePath}/installations/${id}`);
  }

  /**
   * Delete installation
   * DELETE /api/v1/ai/marketplace/installations/:id
   */
  async deleteInstallation(id: string): Promise<void> {
    return this.delete<void>(`${this.basePath}/installations/${id}`);
  }

  // ===================================================================
  // Updates Management
  // ===================================================================

  /**
   * Check for updates
   * GET /api/v1/ai/marketplace/updates
   */
  async checkUpdates(): Promise<UpdateCheck[]> {
    return this.get<UpdateCheck[]>(`${this.basePath}/updates`);
  }

  /**
   * Apply updates
   * POST /api/v1/ai/marketplace/updates/apply
   */
  async applyUpdates(installationIds: string[]): Promise<{
    success: boolean;
    updated_count: number;
    failed_updates: Array<{ installation_id: string; error: string }>;
  }> {
    return this.post<{
      success: boolean;
      updated_count: number;
      failed_updates: Array<{ installation_id: string; error: string }>;
    }>(`${this.basePath}/updates/apply`, { installation_ids: installationIds });
  }
}

// Export singleton instance
export const marketplaceApi = new MarketplaceApiService();
export default marketplaceApi;
