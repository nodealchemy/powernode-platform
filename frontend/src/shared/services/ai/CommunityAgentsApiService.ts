import { BaseApiService, PaginatedResponse } from '@/shared/services/ai/BaseApiService';
import type {
  CommunityAgent,
  CommunityAgentSummary,
  CreateCommunityAgentRequest,
  UpdateCommunityAgentRequest,
  CommunityAgentFilters,
  CommunityAgentRating,
  CreateRatingRequest,
  CreateReportRequest,
  DiscoverAgentsRequest,
  DiscoverAgentsResponse,
  FederationPartner,
  FederationPartnerSummary,
  CreateFederationPartnerRequest,
  UpdateFederationPartnerRequest,
  FederationPartnerFilters,
  FederatedAgent,
  VerifyFederationKeyResponse,
} from '@/shared/services/ai/types/community-types';

/**
 * CommunityAgentsApiService - Community Agents API Client
 *
 * Provides access to community agent registry, discovery, ratings,
 * and federation partner management.
 *
 * Endpoint structure:
 * Community Agents:
 * - GET    /api/v1/ai/community/agents
 * - POST   /api/v1/ai/community/agents
 * - GET    /api/v1/ai/community/agents/:id
 * - PATCH  /api/v1/ai/community/agents/:id
 * - DELETE /api/v1/ai/community/agents/:id
 * - POST   /api/v1/ai/community/agents/:id/publish
 * - POST   /api/v1/ai/community/agents/:id/unpublish
 * - POST   /api/v1/ai/community/agents/:id/rate
 * - POST   /api/v1/ai/community/agents/:id/report
 * - GET    /api/v1/ai/community/agents/my_agents
 * - GET    /api/v1/ai/community/agents/categories
 * - GET    /api/v1/ai/community/agents/skills
 * - POST   /api/v1/ai/community/agents/discover
 *
 * Federation:
 * - GET    /api/v1/ai/federation/partners
 * - POST   /api/v1/ai/federation/partners
 * - GET    /api/v1/ai/federation/partners/:id
 * - PATCH  /api/v1/ai/federation/partners/:id
 * - DELETE /api/v1/ai/federation/partners/:id
 * - POST   /api/v1/ai/federation/partners/:id/verify
 * - GET    /api/v1/ai/federation/partners/:id/agents
 * - POST   /api/v1/ai/federation/partners/:id/sync
 * - POST   /api/v1/ai/federation/register
 * - POST   /api/v1/ai/federation/verify_key
 * - GET    /api/v1/ai/federation/discover
 */

class CommunityAgentsApiService extends BaseApiService {
  private communityPath = '/ai/community/agents';
  private federationPath = '/ai/federation';

  // ===================================================================
  // Community Agent Operations
  // ===================================================================

  /**
   * Get list of community agents
   * GET /api/v1/ai/community/agents
   */
  async getAgents(filters?: CommunityAgentFilters): Promise<PaginatedResponse<CommunityAgentSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<CommunityAgentSummary>>(this.communityPath + queryString);
  }

  /**
   * Get single agent by ID
   * GET /api/v1/ai/community/agents/:id
   */
  async getAgent(agentId: string): Promise<{ agent: CommunityAgent }> {
    return this.get<{ agent: CommunityAgent }>(`${this.communityPath}/${agentId}`);
  }

  /**
   * Create a new community agent
   * POST /api/v1/ai/community/agents
   */
  async createAgent(request: CreateCommunityAgentRequest): Promise<{ agent: CommunityAgent }> {
    return this.post<{ agent: CommunityAgent }>(this.communityPath, { agent: request });
  }

  /**
   * Update a community agent
   * PATCH /api/v1/ai/community/agents/:id
   */
  async updateAgent(agentId: string, request: UpdateCommunityAgentRequest): Promise<{ agent: CommunityAgent }> {
    return this.patch<{ agent: CommunityAgent }>(`${this.communityPath}/${agentId}`, { agent: request });
  }

  /**
   * Delete a community agent
   * DELETE /api/v1/ai/community/agents/:id
   */
  async deleteAgent(agentId: string): Promise<{ message: string }> {
    return this.delete<{ message: string }>(`${this.communityPath}/${agentId}`);
  }

  /**
   * Publish an agent to the community
   * POST /api/v1/ai/community/agents/:id/publish
   */
  async publishAgent(agentId: string): Promise<{ agent: CommunityAgent }> {
    return this.post<{ agent: CommunityAgent }>(`${this.communityPath}/${agentId}/publish`);
  }

  /**
   * Unpublish an agent from the community
   * POST /api/v1/ai/community/agents/:id/unpublish
   */
  async unpublishAgent(agentId: string): Promise<{ agent: CommunityAgent }> {
    return this.post<{ agent: CommunityAgent }>(`${this.communityPath}/${agentId}/unpublish`);
  }

  /**
   * Rate a community agent
   * POST /api/v1/ai/community/agents/:id/rate
   */
  async rateAgent(agentId: string, request: CreateRatingRequest): Promise<{ rating: CommunityAgentRating; agent: CommunityAgent }> {
    return this.post<{ rating: CommunityAgentRating; agent: CommunityAgent }>(`${this.communityPath}/${agentId}/rate`, { rating: request });
  }

  /**
   * Report a community agent
   * POST /api/v1/ai/community/agents/:id/report
   */
  async reportAgent(agentId: string, request: CreateReportRequest): Promise<{ message: string; report_id: string }> {
    return this.post<{ message: string; report_id: string }>(`${this.communityPath}/${agentId}/report`, { report: request });
  }

  /**
   * Get my registered agents
   * GET /api/v1/ai/community/agents/my_agents
   */
  async getMyAgents(): Promise<PaginatedResponse<CommunityAgent>> {
    return this.get<PaginatedResponse<CommunityAgent>>(`${this.communityPath}/my_agents`);
  }

  /**
   * Get available categories
   * GET /api/v1/ai/community/agents/categories
   */
  async getCategories(): Promise<{ categories: string[] }> {
    return this.get<{ categories: string[] }>(`${this.communityPath}/categories`);
  }

  /**
   * Get available skills
   * GET /api/v1/ai/community/agents/skills
   */
  async getSkills(): Promise<{ skills: string[] }> {
    return this.get<{ skills: string[] }>(`${this.communityPath}/skills`);
  }

  /**
   * Discover agents based on task description
   * POST /api/v1/ai/community/agents/discover
   */
  async discoverAgents(request: DiscoverAgentsRequest): Promise<DiscoverAgentsResponse> {
    return this.post<DiscoverAgentsResponse>(`${this.communityPath}/discover`, request);
  }

  // ===================================================================
  // Federation Operations
  // ===================================================================

  /**
   * Get list of federation partners
   * GET /api/v1/ai/federation/partners
   */
  async getFederationPartners(filters?: FederationPartnerFilters): Promise<PaginatedResponse<FederationPartnerSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<FederationPartnerSummary>>(`${this.federationPath}/partners${queryString}`);
  }

  /**
   * Get single federation partner
   * GET /api/v1/ai/federation/partners/:id
   */
  async getFederationPartner(partnerId: string): Promise<{ partner: FederationPartner }> {
    return this.get<{ partner: FederationPartner }>(`${this.federationPath}/partners/${partnerId}`);
  }

  /**
   * Create a new federation partner
   * POST /api/v1/ai/federation/partners
   */
  async createFederationPartner(request: CreateFederationPartnerRequest): Promise<{ partner: FederationPartner }> {
    return this.post<{ partner: FederationPartner }>(`${this.federationPath}/partners`, { partner: request });
  }

  /**
   * Update a federation partner
   * PATCH /api/v1/ai/federation/partners/:id
   */
  async updateFederationPartner(partnerId: string, request: UpdateFederationPartnerRequest): Promise<{ partner: FederationPartner }> {
    return this.patch<{ partner: FederationPartner }>(`${this.federationPath}/partners/${partnerId}`, { partner: request });
  }

  /**
   * Delete a federation partner
   * DELETE /api/v1/ai/federation/partners/:id
   */
  async deleteFederationPartner(partnerId: string): Promise<{ message: string }> {
    return this.delete<{ message: string }>(`${this.federationPath}/partners/${partnerId}`);
  }

  /**
   * Verify a federation partner
   * POST /api/v1/ai/federation/partners/:id/verify
   */
  async verifyFederationPartner(partnerId: string): Promise<{ message: string; partner: FederationPartner }> {
    return this.post<{ message: string; partner: FederationPartner }>(`${this.federationPath}/partners/${partnerId}/verify`);
  }

  /**
   * Get agents from a federation partner
   * GET /api/v1/ai/federation/partners/:id/agents
   */
  async getFederationPartnerAgents(partnerId: string, filters?: { category?: string; query?: string }): Promise<{ agents: FederatedAgent[] }> {
    const queryString = this.buildQueryString(filters);
    return this.get<{ agents: FederatedAgent[] }>(`${this.federationPath}/partners/${partnerId}/agents${queryString}`);
  }

  /**
   * Sync agents from a federation partner
   * POST /api/v1/ai/federation/partners/:id/sync
   */
  async syncFederationPartner(partnerId: string): Promise<{ message: string; partner: FederationPartner }> {
    return this.post<{ message: string; partner: FederationPartner }>(`${this.federationPath}/partners/${partnerId}/sync`);
  }

  /**
   * Verify a federation key
   * POST /api/v1/ai/federation/verify_key
   */
  async verifyFederationKey(federationKey: string): Promise<VerifyFederationKeyResponse> {
    return this.post<VerifyFederationKeyResponse>(`${this.federationPath}/verify_key`, { federation_key: federationKey });
  }

  /**
   * Discover agents across all federation partners
   * GET /api/v1/ai/federation/discover
   */
  async discoverFederatedAgents(filters?: { category?: string; query?: string; limit?: number }): Promise<{ agents: FederatedAgent[] }> {
    const queryString = this.buildQueryString(filters);
    return this.get<{ agents: FederatedAgent[] }>(`${this.federationPath}/discover${queryString}`);
  }
}

export const communityAgentsApi = new CommunityAgentsApiService();
