import { BaseApiService, PaginatedResponse } from '@/shared/services/ai/BaseApiService';
import type {
  AgentCard,
  AgentCardFilters,
  CreateAgentCardRequest,
  UpdateAgentCardRequest,
  A2aAgentCardJson,
  DiscoverAgentsResponse,
} from '@/shared/services/ai/types/a2a-types';

/**
 * AgentCardsApiService - A2A Agent Cards API Client
 *
 * Provides access to A2A Agent Card management and discovery endpoints.
 *
 * Endpoint structure:
 * - GET    /api/v1/ai/agent_cards
 * - POST   /api/v1/ai/agent_cards
 * - GET    /api/v1/ai/agent_cards/:id
 * - PATCH  /api/v1/ai/agent_cards/:id
 * - DELETE /api/v1/ai/agent_cards/:id
 * - GET    /api/v1/ai/agent_cards/:id/a2a
 * - POST   /api/v1/ai/agent_cards/:id/publish
 * - POST   /api/v1/ai/agent_cards/:id/deprecate
 * - POST   /api/v1/ai/agent_cards/:id/refresh_metrics
 * - GET    /api/v1/ai/agent_cards/discover
 * - POST   /api/v1/ai/agent_cards/find_for_task
 */

class AgentCardsApiService extends BaseApiService {
  private resource = 'agent_cards';

  // ===================================================================
  // Agent Card CRUD Operations
  // ===================================================================

  /**
   * Get list of agent cards with optional filters
   * GET /api/v1/ai/agent_cards
   */
  async getAgentCards(filters?: AgentCardFilters): Promise<PaginatedResponse<AgentCard>> {
    return this.getList<AgentCard>(this.resource, filters);
  }

  /**
   * Get single agent card by ID
   * GET /api/v1/ai/agent_cards/:id
   */
  async getAgentCard(id: string): Promise<{ agent_card: AgentCard }> {
    return this.getOne<{ agent_card: AgentCard }>(this.resource, id);
  }

  /**
   * Get A2A-compliant JSON for an agent card
   * GET /api/v1/ai/agent_cards/:id/a2a
   */
  async getA2aJson(id: string): Promise<A2aAgentCardJson> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'a2a');
    return this.get<A2aAgentCardJson>(path);
  }

  /**
   * Create new agent card
   * POST /api/v1/ai/agent_cards
   */
  async createAgentCard(data: CreateAgentCardRequest): Promise<{ agent_card: AgentCard }> {
    return this.create<{ agent_card: AgentCard }>(this.resource, { agent_card: data });
  }

  /**
   * Update existing agent card
   * PATCH /api/v1/ai/agent_cards/:id
   */
  async updateAgentCard(id: string, data: UpdateAgentCardRequest): Promise<{ agent_card: AgentCard }> {
    return this.update<{ agent_card: AgentCard }>(this.resource, id, { agent_card: data });
  }

  /**
   * Delete agent card
   * DELETE /api/v1/ai/agent_cards/:id
   */
  async deleteAgentCard(id: string): Promise<{ message: string }> {
    return this.remove<{ message: string }>(this.resource, id);
  }

  // ===================================================================
  // Agent Card Actions
  // ===================================================================

  /**
   * Publish an agent card
   * POST /api/v1/ai/agent_cards/:id/publish
   */
  async publishAgentCard(id: string): Promise<{ agent_card: AgentCard; message: string }> {
    return this.performAction<{ agent_card: AgentCard; message: string }>(this.resource, id, 'publish');
  }

  /**
   * Deprecate an agent card
   * POST /api/v1/ai/agent_cards/:id/deprecate
   */
  async deprecateAgentCard(id: string, reason?: string): Promise<{ agent_card: AgentCard; message: string }> {
    return this.performAction<{ agent_card: AgentCard; message: string }>(this.resource, id, 'deprecate', { reason });
  }

  /**
   * Refresh metrics for an agent card
   * POST /api/v1/ai/agent_cards/:id/refresh_metrics
   */
  async refreshMetrics(id: string): Promise<{ agent_card: AgentCard; message: string }> {
    return this.performAction<{ agent_card: AgentCard; message: string }>(this.resource, id, 'refresh_metrics');
  }

  // ===================================================================
  // Discovery Operations
  // ===================================================================

  /**
   * Discover agents with optional filters
   * GET /api/v1/ai/agent_cards/discover
   */
  async discoverAgents(filters?: AgentCardFilters): Promise<DiscoverAgentsResponse> {
    const queryString = this.buildQueryString(filters);
    const path = this.buildPath(this.resource) + '/discover' + queryString;
    return this.get<DiscoverAgentsResponse>(path);
  }

  /**
   * Find agents capable of handling a task
   * POST /api/v1/ai/agent_cards/find_for_task
   */
  async findAgentsForTask(description: string, limit?: number): Promise<{ agents: A2aAgentCardJson[] }> {
    const path = this.buildPath(this.resource) + '/find_for_task';
    return this.post<{ agents: A2aAgentCardJson[] }>(path, { description, limit });
  }
}

// Export singleton instance
export const agentCardsApiService = new AgentCardsApiService();
export default agentCardsApiService;
