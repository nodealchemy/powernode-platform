import { BaseApiService, QueryFilters, PaginatedResponse } from './BaseApiService';
import type {
  AiAgent,
  AiAgentExecution,
  AiConversation,
  AiMessage
} from '../../types/ai';

/**
 * AgentsApiService - Agents Controller API Client
 *
 * Provides access to the consolidated Agents Controller endpoints.
 * Replaces the following old controllers:
 * - ai_agents_controller
 * - ai_agent_executions_controller
 * - ai_messages_controller (partial)
 * - ai_conversations_controller
 *
 * New endpoint structure:
 * - GET    /api/v1/ai/agents
 * - POST   /api/v1/ai/agents
 * - GET    /api/v1/ai/agents/:id
 * - PATCH  /api/v1/ai/agents/:id
 * - DELETE /api/v1/ai/agents/:id
 * - POST   /api/v1/ai/agents/:id/execute
 * - POST   /api/v1/ai/agents/:id/clone
 * - POST   /api/v1/ai/agents/:id/test
 * - GET    /api/v1/ai/agents/:id/validate
 * - POST   /api/v1/ai/agents/:id/pause
 * - POST   /api/v1/ai/agents/:id/resume
 * - POST   /api/v1/ai/agents/:id/archive
 * - GET    /api/v1/ai/agents/:id/stats
 * - GET    /api/v1/ai/agents/:id/analytics
 * - GET    /api/v1/ai/agents/my_agents
 * - GET    /api/v1/ai/agents/public_agents
 * - GET    /api/v1/ai/agents/agent_types
 * - GET    /api/v1/ai/agents/statistics
 * - GET    /api/v1/ai/agents/:agent_id/executions
 * - POST   /api/v1/ai/agents/:agent_id/executions
 * - GET    /api/v1/ai/agents/:agent_id/executions/:id
 * - POST   /api/v1/ai/agents/:agent_id/executions/:id/cancel
 * - POST   /api/v1/ai/agents/:agent_id/executions/:id/retry
 * - GET    /api/v1/ai/agents/:agent_id/executions/:id/logs
 * - GET    /api/v1/ai/agents/:agent_id/conversations
 * - POST   /api/v1/ai/agents/:agent_id/conversations
 * - GET    /api/v1/ai/agents/:agent_id/conversations/:id
 * - POST   /api/v1/ai/agents/:agent_id/conversations/:id/send_message
 * - POST   /api/v1/ai/agents/:agent_id/conversations/:id/complete
 * - POST   /api/v1/ai/agents/:agent_id/conversations/:id/archive
 * - GET    /api/v1/ai/agents/:agent_id/conversations/:id/messages
 */

export interface AgentFilters extends QueryFilters {
  provider_id?: string;
  agent_type?: string;
  status?: 'active' | 'paused' | 'archived';
  visibility?: 'private' | 'account' | 'public';
}

export interface AgentExecutionFilters extends QueryFilters {
  status?: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  date_range?: {
    start?: string;
    end?: string;
  };
}

export interface ConversationFilters extends QueryFilters {
  status?: 'active' | 'paused' | 'completed' | 'archived';
}

export interface CreateAgentRequest {
  name: string;
  description?: string;
  agent_type: string;
  ai_provider_id: string;
  model_name?: string;
  system_instructions?: string;
  configuration?: Record<string, any>;
  input_schema?: Record<string, any>;
  output_schema?: Record<string, any>;
  max_iterations?: number;
  timeout_seconds?: number;
  visibility?: 'private' | 'account' | 'public';
  tags?: string[];
}

export interface ExecuteAgentRequest {
  input_parameters: Record<string, any>;
  ai_provider_id?: string;
  execution_options?: Record<string, any>;
}

export interface AgentStats {
  total_executions: number;
  successful_executions: number;
  failed_executions: number;
  success_rate: number;
  avg_execution_time: number;
  estimated_total_cost: string;
  last_execution_at?: string;
  created_at: string;
}

export interface AgentAnalytics {
  execution_trends: Array<{
    date: string;
    count: number;
    success_rate: number;
  }>;
  performance_metrics: {
    avg_duration_ms: number;
    p50_duration_ms: number;
    p95_duration_ms: number;
    p99_duration_ms: number;
  };
  cost_analysis: {
    total_cost_usd: number;
    avg_cost_per_execution: number;
    cost_by_provider: Record<string, number>;
  };
}

export interface AgentType {
  value: string;
  label: string;
  description: string;
}

export interface SendMessageRequest {
  content: string;
  role?: 'user' | 'assistant' | 'system';
  metadata?: Record<string, any>;
}

class AgentsApiService extends BaseApiService {
  private resource = 'agents';

  // ===================================================================
  // Agent CRUD Operations
  // ===================================================================

  /**
   * Get list of agents with optional filters
   * GET /api/v1/ai/agents
   */
  async getAgents(filters?: AgentFilters): Promise<PaginatedResponse<AiAgent>> {
    return this.getList<AiAgent>(this.resource, filters);
  }

  /**
   * Get single agent by ID
   * GET /api/v1/ai/agents/:id
   */
  async getAgent(id: string): Promise<AiAgent> {
    return this.getOne<AiAgent>(this.resource, id);
  }

  /**
   * Create new agent
   * POST /api/v1/ai/agents
   */
  async createAgent(data: CreateAgentRequest): Promise<AiAgent> {
    return this.create<AiAgent>(this.resource, { agent: data });
  }

  /**
   * Update existing agent
   * PATCH /api/v1/ai/agents/:id
   */
  async updateAgent(id: string, data: Partial<CreateAgentRequest>): Promise<AiAgent> {
    return this.update<AiAgent>(this.resource, id, { agent: data });
  }

  /**
   * Delete agent
   * DELETE /api/v1/ai/agents/:id
   */
  async deleteAgent(id: string): Promise<void> {
    return this.remove<void>(this.resource, id);
  }

  // ===================================================================
  // Agent Actions
  // ===================================================================

  /**
   * Execute agent
   * POST /api/v1/ai/agents/:id/execute
   */
  async executeAgent(id: string, request: ExecuteAgentRequest): Promise<AiAgentExecution> {
    return this.performAction<AiAgentExecution>(this.resource, id, 'execute', request);
  }

  /**
   * Clone agent
   * POST /api/v1/ai/agents/:id/clone
   */
  async cloneAgent(id: string, name?: string): Promise<AiAgent> {
    return this.performAction<AiAgent>(this.resource, id, 'clone', { name });
  }

  /**
   * Test agent configuration
   * POST /api/v1/ai/agents/:id/test
   */
  async testAgent(id: string, testInput?: Record<string, any>): Promise<any> {
    return this.performAction<any>(this.resource, id, 'test', { test_input: testInput });
  }

  /**
   * Validate agent configuration
   * GET /api/v1/ai/agents/:id/validate
   */
  async validateAgent(id: string): Promise<any> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'validate');
    return this.get<any>(path);
  }

  /**
   * Pause agent
   * POST /api/v1/ai/agents/:id/pause
   */
  async pauseAgent(id: string): Promise<AiAgent> {
    return this.performAction<AiAgent>(this.resource, id, 'pause');
  }

  /**
   * Resume agent
   * POST /api/v1/ai/agents/:id/resume
   */
  async resumeAgent(id: string): Promise<AiAgent> {
    return this.performAction<AiAgent>(this.resource, id, 'resume');
  }

  /**
   * Archive agent
   * POST /api/v1/ai/agents/:id/archive
   */
  async archiveAgent(id: string): Promise<AiAgent> {
    return this.performAction<AiAgent>(this.resource, id, 'archive');
  }

  /**
   * Get agent statistics
   * GET /api/v1/ai/agents/:id/stats
   */
  async getAgentStats(id: string): Promise<AgentStats> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'stats');
    return this.get<AgentStats>(path);
  }

  /**
   * Get agent analytics
   * GET /api/v1/ai/agents/:id/analytics
   */
  async getAgentAnalytics(id: string, timeRange?: string): Promise<AgentAnalytics> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'analytics');
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<AgentAnalytics>(`${path}${queryString}`);
  }

  // ===================================================================
  // Agent Collection Actions
  // ===================================================================

  /**
   * Get current user's agents
   * GET /api/v1/ai/agents/my_agents
   */
  async getMyAgents(): Promise<AiAgent[]> {
    const path = this.buildPath(this.resource);
    return this.get<AiAgent[]>(`${path}/my_agents`);
  }

  /**
   * Get public agents
   * GET /api/v1/ai/agents/public_agents
   */
  async getPublicAgents(): Promise<AiAgent[]> {
    const path = this.buildPath(this.resource);
    return this.get<AiAgent[]>(`${path}/public_agents`);
  }

  /**
   * Get available agent types
   * GET /api/v1/ai/agents/agent_types
   */
  async getAgentTypes(): Promise<AgentType[]> {
    const path = this.buildPath(this.resource);
    return this.get<AgentType[]>(`${path}/agent_types`);
  }

  /**
   * Get agent statistics (account-wide)
   * GET /api/v1/ai/agents/statistics
   */
  async getStatistics(): Promise<any> {
    const path = this.buildPath(this.resource);
    return this.get<any>(`${path}/statistics`);
  }

  // ===================================================================
  // Agent Executions - Nested Resource
  // ===================================================================

  /**
   * Get list of agent executions
   * GET /api/v1/ai/agents/:agent_id/executions
   */
  async getExecutions(
    agentId: string,
    filters?: AgentExecutionFilters
  ): Promise<PaginatedResponse<AiAgentExecution>> {
    return this.getNestedList<AiAgentExecution>(this.resource, agentId, 'executions', filters);
  }

  /**
   * Get single agent execution
   * GET /api/v1/ai/agents/:agent_id/executions/:id
   */
  async getExecution(agentId: string, executionId: string): Promise<AiAgentExecution> {
    return this.getNestedOne<AiAgentExecution>(this.resource, agentId, 'executions', executionId);
  }

  /**
   * Cancel agent execution
   * POST /api/v1/ai/agents/:agent_id/executions/:id/cancel
   */
  async cancelExecution(agentId: string, executionId: string): Promise<AiAgentExecution> {
    return this.performNestedAction<AiAgentExecution>(
      this.resource,
      agentId,
      'executions',
      executionId,
      'cancel'
    );
  }

  /**
   * Retry agent execution
   * POST /api/v1/ai/agents/:agent_id/executions/:id/retry
   */
  async retryExecution(agentId: string, executionId: string): Promise<AiAgentExecution> {
    return this.performNestedAction<AiAgentExecution>(
      this.resource,
      agentId,
      'executions',
      executionId,
      'retry'
    );
  }

  /**
   * Get agent execution logs
   * GET /api/v1/ai/agents/:agent_id/executions/:id/logs
   */
  async getExecutionLogs(agentId: string, executionId: string): Promise<any[]> {
    const path = this.buildPath(this.resource, agentId, 'executions', executionId, 'logs');
    return this.get<any[]>(path);
  }

  // ===================================================================
  // Agent Conversations - Nested Resource
  // ===================================================================

  /**
   * Get list of agent conversations
   * GET /api/v1/ai/agents/:agent_id/conversations
   */
  async getConversations(
    agentId: string,
    filters?: ConversationFilters
  ): Promise<PaginatedResponse<AiConversation>> {
    return this.getNestedList<AiConversation>(this.resource, agentId, 'conversations', filters);
  }

  /**
   * Get active conversations
   * GET /api/v1/ai/agents/:agent_id/conversations?status=active
   */
  async getActiveConversations(agentId: string): Promise<PaginatedResponse<AiConversation>> {
    return this.getConversations(agentId, { status: 'active' });
  }

  /**
   * Create new conversation
   * POST /api/v1/ai/agents/:agent_id/conversations
   */
  async createConversation(
    agentId: string,
    data: { title?: string; metadata?: Record<string, any> }
  ): Promise<AiConversation> {
    return this.createNested<AiConversation>(this.resource, agentId, 'conversations', {
      conversation: data,
    });
  }

  /**
   * Start conversation (alias for createConversation)
   * POST /api/v1/ai/agents/:agent_id/conversations
   */
  async startConversation(
    agentId: string,
    data?: { title?: string; metadata?: Record<string, any> }
  ): Promise<AiConversation> {
    return this.createConversation(agentId, data || {});
  }

  /**
   * Get single conversation
   * GET /api/v1/ai/agents/:agent_id/conversations/:id
   */
  async getConversation(agentId: string, conversationId: string): Promise<AiConversation> {
    return this.getNestedOne<AiConversation>(this.resource, agentId, 'conversations', conversationId);
  }

  /**
   * Send message in conversation
   * POST /api/v1/ai/agents/:agent_id/conversations/:id/send_message
   */
  async sendMessage(
    agentId: string,
    conversationId: string,
    message: SendMessageRequest
  ): Promise<AiMessage> {
    return this.performNestedAction<AiMessage>(
      this.resource,
      agentId,
      'conversations',
      conversationId,
      'send_message',
      message
    );
  }

  /**
   * Pause conversation
   * POST /api/v1/ai/agents/:agent_id/conversations/:id/pause
   */
  async pauseConversation(agentId: string, conversationId: string): Promise<AiConversation> {
    return this.performNestedAction<AiConversation>(
      this.resource,
      agentId,
      'conversations',
      conversationId,
      'pause'
    );
  }

  /**
   * Resume conversation
   * POST /api/v1/ai/agents/:agent_id/conversations/:id/resume
   */
  async resumeConversation(agentId: string, conversationId: string): Promise<AiConversation> {
    return this.performNestedAction<AiConversation>(
      this.resource,
      agentId,
      'conversations',
      conversationId,
      'resume'
    );
  }

  /**
   * Complete conversation
   * POST /api/v1/ai/agents/:agent_id/conversations/:id/complete
   */
  async completeConversation(agentId: string, conversationId: string): Promise<AiConversation> {
    return this.performNestedAction<AiConversation>(
      this.resource,
      agentId,
      'conversations',
      conversationId,
      'complete'
    );
  }

  /**
   * Archive conversation
   * POST /api/v1/ai/agents/:agent_id/conversations/:id/archive
   */
  async archiveConversation(agentId: string, conversationId: string): Promise<AiConversation> {
    return this.performNestedAction<AiConversation>(
      this.resource,
      agentId,
      'conversations',
      conversationId,
      'archive'
    );
  }

  /**
   * Get conversation messages
   * GET /api/v1/ai/agents/:agent_id/conversations/:id/messages
   */
  async getMessages(agentId: string, conversationId: string): Promise<AiMessage[]> {
    const path = this.buildPath(this.resource, agentId, 'conversations', conversationId, 'messages');
    const response = await this.get<{ messages: AiMessage[] }>(path);
    // Handle both wrapped and direct array responses
    return Array.isArray(response) ? response : (response.messages || []);
  }

  /**
   * Export conversation
   * GET /api/v1/ai/agents/:agent_id/conversations/:id/export
   */
  async exportConversation(agentId: string, conversationId: string): Promise<any> {
    const path = this.buildPath(this.resource, agentId, 'conversations', conversationId, 'export');
    return this.get<any>(path);
  }

  // ===================================================================
  // Global Conversations - Cross-Agent Management
  // ===================================================================

  /**
   * Get all conversations across all agents (global view)
   * GET /api/v1/ai/conversations
   */
  async getGlobalConversations(
    filters?: ConversationFilters & {
      agent_id?: string;
      user_id?: string;
      search?: string;
    }
  ): Promise<PaginatedResponse<AiConversation>> {
    const path = '/api/v1/ai/conversations';
    const params = new URLSearchParams();

    if (filters?.page) params.append('page', filters.page.toString());
    if (filters?.per_page) params.append('per_page', filters.per_page.toString());
    if (filters?.status) params.append('status', filters.status);
    if (filters?.agent_id) params.append('agent_id', filters.agent_id);
    if (filters?.user_id) params.append('user_id', filters.user_id);
    if (filters?.search) params.append('search', filters.search);

    const queryString = params.toString();
    const fullPath = queryString ? `${path}?${queryString}` : path;

    return this.get<PaginatedResponse<AiConversation>>(fullPath);
  }

  /**
   * Get single conversation (global endpoint)
   * GET /api/v1/ai/conversations/:id
   */
  async getGlobalConversation(conversationId: string): Promise<AiConversation> {
    const path = `/api/v1/ai/conversations/${conversationId}`;
    return this.get<AiConversation>(path);
  }

  /**
   * Update conversation (global endpoint)
   * PATCH /api/v1/ai/conversations/:id
   */
  async updateGlobalConversation(
    conversationId: string,
    data: {
      title?: string;
      status?: string;
      is_collaborative?: boolean;
      participants?: string[];
    }
  ): Promise<AiConversation> {
    const path = `/api/v1/ai/conversations/${conversationId}`;
    return this.patch<AiConversation>(path, { conversation: data });
  }

  /**
   * Delete conversation (global endpoint)
   * DELETE /api/v1/ai/conversations/:id
   */
  async deleteGlobalConversation(conversationId: string): Promise<void> {
    const path = `/api/v1/ai/conversations/${conversationId}`;
    return this.delete<void>(path);
  }

  /**
   * Archive conversation (global endpoint)
   * POST /api/v1/ai/conversations/:id/archive
   */
  async archiveGlobalConversation(conversationId: string): Promise<AiConversation> {
    const path = `/api/v1/ai/conversations/${conversationId}/archive`;
    return this.post<AiConversation>(path, {});
  }

  /**
   * Unarchive conversation (global endpoint)
   * POST /api/v1/ai/conversations/:id/unarchive
   */
  async unarchiveGlobalConversation(conversationId: string): Promise<AiConversation> {
    const path = `/api/v1/ai/conversations/${conversationId}/unarchive`;
    return this.post<AiConversation>(path, {});
  }

  /**
   * Duplicate conversation (global endpoint)
   * POST /api/v1/ai/conversations/:id/duplicate
   */
  async duplicateGlobalConversation(
    conversationId: string,
    options?: {
      title?: string;
      include_messages?: boolean;
    }
  ): Promise<AiConversation> {
    const path = `/api/v1/ai/conversations/${conversationId}/duplicate`;
    return this.post<AiConversation>(path, options || {});
  }

  // ===================================================================
  // Conversation Messages - Deeply Nested Resource
  // ===================================================================

  /**
   * Edit message content
   * PATCH /api/v1/ai/agents/:agent_id/conversations/:conversation_id/messages/:id/edit_content
   */
  async editMessageContent(
    agentId: string,
    conversationId: string,
    messageId: string,
    content: string
  ): Promise<AiMessage> {
    const path = this.buildPath(this.resource, agentId, 'conversations', conversationId);
    const fullPath = `${path}/messages/${messageId}/edit_content`;
    return this.patch<AiMessage>(fullPath, { content });
  }

  /**
   * Regenerate AI response for a message
   * POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/messages/:id/regenerate
   */
  async regenerateMessage(
    agentId: string,
    conversationId: string,
    messageId: string
  ): Promise<{ message: AiMessage; regeneration_queued: boolean }> {
    const path = this.buildPath(this.resource, agentId, 'conversations', conversationId);
    const fullPath = `${path}/messages/${messageId}/regenerate`;
    return this.post<{ message: AiMessage; regeneration_queued: boolean }>(fullPath, {});
  }

  /**
   * Rate a message with thumbs up or down
   * POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/messages/:id/rate
   */
  async rateMessage(
    agentId: string,
    conversationId: string,
    messageId: string,
    rating: 'thumbs_up' | 'thumbs_down',
    feedback?: string
  ): Promise<{ message: AiMessage; rating: { rating: string; rated_at: string; rated_by: string } }> {
    const path = this.buildPath(this.resource, agentId, 'conversations', conversationId);
    const fullPath = `${path}/messages/${messageId}/rate`;
    return this.post<{ message: AiMessage; rating: { rating: string; rated_at: string; rated_by: string } }>(fullPath, { rating, feedback });
  }
}

// Export singleton instance
export const agentsApi = new AgentsApiService();
export default agentsApi;
