/**
 * Agent Marketplace API Service
 * Phase 4: Pre-Built Vertical AI Agent Templates
 *
 * Revenue Model: Commission (15-30%) + listing fees
 * - Free tier: 3 community agents
 * - Pro: Unlimited community + 5 premium ($149/mo)
 * - Business: Private marketplace + custom agents ($999+/mo)
 * - Publisher revenue share: 70-85% to creators
 */

import { BaseApiService, PaginatedResponse, QueryFilters } from '@/shared/services/ai/BaseApiService';

// Types
export interface AgentTemplate {
  id: string;
  name: string;
  slug: string;
  description: string;
  category: string;
  vertical: string;
  pricing_type: 'free' | 'one_time' | 'subscription' | 'usage_based' | 'freemium';
  price_usd: number | null;
  monthly_price_usd: number | null;
  version: string;
  installation_count: number;
  average_rating: number | null;
  review_count: number;
  is_featured: boolean;
  is_verified: boolean;
  publisher: {
    id: string;
    name: string;
    slug: string;
    verified: boolean;
  };
  published_at: string | null;
  // Detailed fields (when detailed: true)
  long_description?: string;
  agent_config?: Record<string, unknown>;
  required_credentials?: string[];
  required_tools?: string[];
  sample_prompts?: string[];
  screenshots?: string[];
  tags?: string[];
  features?: string[];
  limitations?: string[];
  setup_instructions?: string;
  changelog?: string;
}

export interface AgentInstallation {
  id: string;
  status: 'active' | 'paused' | 'expired' | 'cancelled' | 'pending_update';
  installed_version: string;
  license_type: 'standard' | 'business' | 'trial';
  executions_count: number;
  total_cost_usd: number;
  last_used_at: string | null;
  created_at: string;
  template: {
    id: string;
    name: string;
    slug: string;
  };
}

export interface AgentReview {
  id: string;
  rating: number;
  title: string | null;
  content: string | null;
  pros: string[];
  cons: string[];
  is_verified_purchase: boolean;
  helpful_count: number;
  created_at: string;
}

export interface MarketplaceCategory {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  icon: string | null;
  template_count: number;
  children: MarketplaceCategory[];
}

export interface Publisher {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  website_url: string | null;
  status: 'pending' | 'active' | 'suspended' | 'terminated';
  verification_status: 'unverified' | 'pending' | 'verified' | 'rejected';
  total_templates: number;
  total_installations: number;
  average_rating: number | null;
  lifetime_earnings_usd: number;
  pending_payout_usd: number;
}

export interface PublisherAnalytics {
  total_revenue: number;
  total_earnings: number;
  transaction_count: number;
  installations: number;
  active_installations: number;
  average_rating: number | null;
  templates_count: number;
}

export interface TemplateFilters extends QueryFilters {
  query?: string;
  category?: string;
  vertical?: string;
  pricing_type?: string;
}

class AgentMarketplaceApiService extends BaseApiService {
  private basePath = '/ai/agent_marketplace';

  // Templates
  async getTemplates(filters: TemplateFilters = {}): Promise<PaginatedResponse<AgentTemplate>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<AgentTemplate>>(`${this.basePath}/templates${queryString}`);
  }

  async getFeaturedTemplates(limit = 10): Promise<{ templates: AgentTemplate[] }> {
    return this.get(`${this.basePath}/templates/featured?limit=${limit}`);
  }

  async getTemplate(id: string): Promise<{ template: AgentTemplate }> {
    return this.get(`${this.basePath}/templates/${id}`);
  }

  // Categories
  async getCategories(): Promise<{ categories: MarketplaceCategory[] }> {
    return this.get(`${this.basePath}/categories`);
  }

  // Installations
  async getInstallations(page = 1, perPage = 20): Promise<PaginatedResponse<AgentInstallation>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<AgentInstallation>>(`${this.basePath}/installations${queryString}`);
  }

  async installTemplate(
    templateId: string,
    customConfig: Record<string, unknown> = {}
  ): Promise<{ installation: AgentInstallation }> {
    return this.post(`${this.basePath}/templates/${templateId}/install`, { custom_config: customConfig });
  }

  async uninstallTemplate(installationId: string): Promise<{ message: string }> {
    return this.delete(`${this.basePath}/installations/${installationId}`);
  }

  // Reviews
  async getReviews(
    templateId: string,
    page = 1,
    perPage = 20
  ): Promise<PaginatedResponse<AgentReview>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<AgentReview>>(`${this.basePath}/templates/${templateId}/reviews${queryString}`);
  }

  async createReview(
    templateId: string,
    data: {
      rating: number;
      title?: string;
      content?: string;
      pros?: string[];
      cons?: string[];
    }
  ): Promise<{ review: AgentReview }> {
    return this.post(`${this.basePath}/templates/${templateId}/reviews`, data);
  }

  // Publisher
  async getPublisher(): Promise<{ publisher: Publisher }> {
    return this.get(`${this.basePath}/publisher`);
  }

  async createPublisher(data: {
    name: string;
    description?: string;
    website_url?: string;
    support_email?: string;
  }): Promise<{ publisher: Publisher }> {
    return this.post(`${this.basePath}/publisher`, data);
  }

  async getPublisherAnalytics(
    startDate?: string,
    endDate?: string
  ): Promise<{ analytics: PublisherAnalytics }> {
    const params: Record<string, string> = {};
    if (startDate) params.start_date = startDate;
    if (endDate) params.end_date = endDate;
    const queryString = this.buildQueryString(params);
    return this.get(`${this.basePath}/publisher/analytics${queryString}`);
  }
}

export const agentMarketplaceApi = new AgentMarketplaceApiService();
