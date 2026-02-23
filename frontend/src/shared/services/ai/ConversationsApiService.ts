import { BaseApiService, QueryFilters, PaginatedResponse } from '@/shared/services/ai/BaseApiService';
import type { AiMessage } from '@/shared/types/ai';

/**
 * ConversationsApiService - Global Conversations Controller API Client
 *
 * Provides access to the global Conversations Controller endpoints.
 * For cross-agent conversation listing, filtering, and management.
 *
 * Endpoint structure:
 * - GET    /api/v1/ai/conversations
 * - GET    /api/v1/ai/conversations/:id
 * - PATCH  /api/v1/ai/conversations/:id
 * - DELETE /api/v1/ai/conversations/:id
 * - POST   /api/v1/ai/conversations/:id/archive
 * - POST   /api/v1/ai/conversations/:id/unarchive
 * - POST   /api/v1/ai/conversations/:id/duplicate
 * - GET    /api/v1/ai/conversations/:id/stats
 */

export interface GlobalConversationFilters extends QueryFilters {
  status?: 'active' | 'paused' | 'completed' | 'archived';
  agent_id?: string;
  user_id?: string;
  pinned?: boolean;
  tags?: string[];
  sort_by?: 'pinned' | 'last_activity' | 'created_at';
}

export interface ConversationStats {
  message_count: number;
  token_usage: number;
  avg_response_time: number;
  duration: number;
  total_cost: number;
  user_message_count: number;
  assistant_message_count: number;
  system_message_count: number;
  first_message_at: string | null;
  last_message_at: string | null;
  status: string;
  is_collaborative: boolean;
  participant_count: number;
}

export interface DuplicateConversationRequest {
  title?: string;
  include_messages?: boolean;
}

export interface UpdateConversationRequest {
  title?: string;
  status?: string;
  is_collaborative?: boolean;
  participants?: string[];
  tags?: string[];
  metadata?: Record<string, unknown>;
}

// Define conversation types locally to avoid circular dependencies
export interface ConversationBase {
  id: string;
  conversation_id: string;
  title: string | null;
  status: 'active' | 'paused' | 'completed' | 'archived';
  conversation_type?: 'agent' | 'team';
  message_count: number;
  total_tokens: number;
  total_cost: number | null;
  is_collaborative: boolean;
  participant_count: number;
  pinned: boolean;
  pinned_at: string | null;
  tags: string[];
  created_at: string;
  last_activity_at: string | null;
  ai_agent?: {
    id: string;
    name: string;
    agent_type: string;
    is_concierge?: boolean;
  } | null;
  agent_team?: {
    id: string;
    name: string;
    team_type?: string;
  };
  ai_provider: {
    id: string;
    name: string;
    provider_type: string;
  };
  user: {
    id: string;
    name: string;
    email: string;
  };
}

// Define conversation response type with full details
export interface ConversationDetail extends ConversationBase {
  summary?: string;
  websocket_channel?: string;
  websocket_session_id?: string;
  participants?: Array<{
    id: string;
    name: string;
    email: string;
  }>;
  recent_messages?: AiMessage[];
  metadata?: {
    can_send_message: boolean;
    active_session: boolean;
  };
}

// API response types
interface ConversationsListResponse {
  conversations: ConversationBase[];
  pagination: {
    current_page: number;
    per_page: number;
    total_pages: number;
    total_count: number;
  };
}

interface ConversationResponse {
  conversation: ConversationDetail;
}

interface ConversationActionResponse {
  conversation: ConversationBase;
  message: string;
}

interface StatsResponse {
  stats: ConversationStats;
}

interface ScheduledMessageResponse {
  scheduled_message: ScheduledMessage;
}

interface ScheduledMessagesListResponse {
  scheduled_messages: ScheduledMessage[];
}

export interface ScheduledMessage {
  id: string;
  content: string;
  schedule_type: 'one_time' | 'recurring' | 'interval';
  scheduled_at?: string;
  cron_expression?: string;
  interval_seconds?: number;
  max_executions?: number;
  execution_count: number;
  status: 'active' | 'paused' | 'completed' | 'cancelled';
  last_executed_at?: string;
  next_execution_at?: string;
  created_at: string;
}

export interface CreateScheduledMessageRequest {
  content: string;
  schedule_type: 'one_time' | 'recurring' | 'interval';
  scheduled_at?: string;
  cron_expression?: string;
  interval_seconds?: number;
  max_executions?: number;
}

class ConversationsApiService extends BaseApiService {
  private basePath = '/ai/conversations';

  // ===================================================================
  // Global Conversation Operations
  // ===================================================================

  /**
   * Get list of all conversations across all agents
   * GET /api/v1/ai/conversations
   */
  async getConversations(filters?: GlobalConversationFilters): Promise<PaginatedResponse<ConversationBase>> {
    const queryString = this.buildQueryString(filters);
    const response = await this.get<ConversationsListResponse>(`${this.basePath}${queryString}`);

    // Transform to PaginatedResponse format
    return {
      items: response.conversations || [],
      pagination: response.pagination || {
        current_page: 1,
        per_page: 25,
        total_pages: 1,
        total_count: 0
      }
    };
  }

  /**
   * Get a specific conversation by ID
   * GET /api/v1/ai/conversations/:id
   */
  async getConversation(id: string): Promise<ConversationDetail> {
    const response = await this.get<ConversationResponse>(`${this.basePath}/${id}`);
    return response.conversation;
  }

  /**
   * Update a conversation
   * PATCH /api/v1/ai/conversations/:id
   */
  async updateConversation(id: string, data: UpdateConversationRequest): Promise<ConversationDetail> {
    const response = await this.patch<ConversationResponse>(`${this.basePath}/${id}`, { conversation: data });
    return response.conversation;
  }

  /**
   * Delete a conversation
   * DELETE /api/v1/ai/conversations/:id
   */
  async deleteConversation(id: string): Promise<void> {
    await this.delete(`${this.basePath}/${id}`);
  }

  /**
   * Archive a conversation
   * POST /api/v1/ai/conversations/:id/archive
   */
  async archiveConversation(id: string): Promise<ConversationBase> {
    const response = await this.post<ConversationActionResponse>(`${this.basePath}/${id}/archive`);
    return response.conversation;
  }

  /**
   * Unarchive a conversation
   * POST /api/v1/ai/conversations/:id/unarchive
   */
  async unarchiveConversation(id: string): Promise<ConversationBase> {
    const response = await this.post<ConversationActionResponse>(`${this.basePath}/${id}/unarchive`);
    return response.conversation;
  }

  /**
   * Duplicate a conversation
   * POST /api/v1/ai/conversations/:id/duplicate
   */
  async duplicateConversation(id: string, options?: DuplicateConversationRequest): Promise<ConversationDetail> {
    const response = await this.post<ConversationResponse>(`${this.basePath}/${id}/duplicate`, options);
    return response.conversation;
  }

  /**
   * Get conversation statistics
   * GET /api/v1/ai/conversations/:id/stats
   */
  async getConversationStats(id: string): Promise<ConversationStats> {
    const response = await this.get<StatsResponse>(`${this.basePath}/${id}/stats`);
    return response.stats;
  }

  /**
   * Pin a conversation
   * POST /api/v1/ai/conversations/:id/pin
   */
  async pinConversation(id: string): Promise<ConversationBase> {
    const response = await this.post<ConversationActionResponse>(`${this.basePath}/${id}/pin`);
    return response.conversation;
  }

  /**
   * Unpin a conversation
   * DELETE /api/v1/ai/conversations/:id/unpin
   */
  async unpinConversation(id: string): Promise<ConversationBase> {
    const response = await this.delete<ConversationActionResponse>(`${this.basePath}/${id}/unpin`);
    return response.conversation;
  }

  /**
   * Bulk operations on conversations
   * PATCH /api/v1/ai/conversations/bulk
   */
  async bulkAction(ids: string[], action: string, params?: Record<string, unknown>): Promise<{ updated_count: number }> {
    const response = await this.patch<{ updated_count: number }>(`${this.basePath}/bulk`, {
      conversation_ids: ids,
      action_type: action,
      ...params,
    });
    return response;
  }

  /**
   * Send a plan response (approve/request changes)
   * POST /api/v1/ai/conversations/:id/plan_response
   */
  async sendPlanResponse(id: string, actionType: string, executionId: string, feedback?: string): Promise<{ message: string }> {
    return this.post<{ message: string }>(`${this.basePath}/${id}/plan_response`, {
      action_type: actionType,
      execution_id: executionId,
      feedback,
    });
  }

  /**
   * Full-text search across conversation messages
   * GET /api/v1/ai/conversations/search?q=<query>
   */
  async searchConversations(query: string): Promise<ConversationBase[]> {
    const response = await this.get<{ conversations: ConversationBase[] }>(`${this.basePath}/search?q=${encodeURIComponent(query)}`);
    return response.conversations || [];
  }

  /**
   * Create a team conversation
   * POST /api/v1/ai/conversations/team
   */
  async createTeamConversation(teamId: string, title?: string): Promise<ConversationDetail> {
    const response = await this.post<ConversationResponse>(`${this.basePath}/team`, {
      team_id: teamId,
      title,
    });
    return response.conversation;
  }

  // ===================================================================
  // Scheduled Messages
  // ===================================================================

  /**
   * List scheduled messages for a conversation
   * GET /api/v1/ai/conversations/:id/scheduled_messages
   */
  async getScheduledMessages(conversationId: string): Promise<ScheduledMessage[]> {
    const response = await this.get<ScheduledMessagesListResponse>(
      `${this.basePath}/${conversationId}/scheduled_messages`
    );
    return response.scheduled_messages || [];
  }

  /**
   * Create a scheduled message
   * POST /api/v1/ai/conversations/:id/scheduled_messages
   */
  async createScheduledMessage(
    conversationId: string,
    data: CreateScheduledMessageRequest
  ): Promise<ScheduledMessage> {
    const response = await this.post<ScheduledMessageResponse>(
      `${this.basePath}/${conversationId}/scheduled_messages`,
      { scheduled_message: data }
    );
    return response.scheduled_message;
  }

  /**
   * Pause a scheduled message
   * POST /api/v1/ai/conversations/:id/scheduled_messages/:messageId/pause
   */
  async pauseScheduledMessage(conversationId: string, messageId: string): Promise<ScheduledMessage> {
    const response = await this.post<ScheduledMessageResponse>(
      `${this.basePath}/${conversationId}/scheduled_messages/${messageId}/pause`
    );
    return response.scheduled_message;
  }

  /**
   * Resume a scheduled message
   * POST /api/v1/ai/conversations/:id/scheduled_messages/:messageId/resume
   */
  async resumeScheduledMessage(conversationId: string, messageId: string): Promise<ScheduledMessage> {
    const response = await this.post<ScheduledMessageResponse>(
      `${this.basePath}/${conversationId}/scheduled_messages/${messageId}/resume`
    );
    return response.scheduled_message;
  }

  /**
   * Cancel a scheduled message
   * DELETE /api/v1/ai/conversations/:id/scheduled_messages/:messageId
   */
  async cancelScheduledMessage(conversationId: string, messageId: string): Promise<void> {
    await this.delete(`${this.basePath}/${conversationId}/scheduled_messages/${messageId}`);
  }
}

// Export singleton instance
export const conversationsApi = new ConversationsApiService();
export default conversationsApi;
