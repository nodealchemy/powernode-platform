import { BaseApiService, PaginatedResponse } from './BaseApiService';
import type {
  ChatChannel,
  ChatChannelSummary,
  CreateChannelRequest,
  UpdateChannelRequest,
  ChannelFilters,
  ChatSession,
  ChatSessionSummary,
  SessionFilters,
  ChatMessage,
  ChatMessageSummary,
  SendMessageRequest,
  MessageFilters,
  ChannelMetrics,
  SessionStats,
  PlatformInfo,
} from './types/chat-types';

/**
 * ChatChannelsApiService - Chat Gateway API Client
 *
 * Provides access to chat channel management, session handling,
 * and messaging across external platforms.
 *
 * Endpoint structure:
 * - GET    /api/v1/chat/channels
 * - POST   /api/v1/chat/channels
 * - GET    /api/v1/chat/channels/:id
 * - PATCH  /api/v1/chat/channels/:id
 * - DELETE /api/v1/chat/channels/:id
 * - POST   /api/v1/chat/channels/:id/connect
 * - POST   /api/v1/chat/channels/:id/disconnect
 * - POST   /api/v1/chat/channels/:id/test
 * - POST   /api/v1/chat/channels/:id/regenerate_token
 * - GET    /api/v1/chat/channels/:id/sessions
 * - GET    /api/v1/chat/channels/:id/metrics
 * - GET    /api/v1/chat/channels/platforms
 *
 * Session endpoints:
 * - GET    /api/v1/chat/sessions
 * - GET    /api/v1/chat/sessions/:id
 * - PATCH  /api/v1/chat/sessions/:id
 * - DELETE /api/v1/chat/sessions/:id
 * - POST   /api/v1/chat/sessions/:id/transfer
 * - POST   /api/v1/chat/sessions/:id/close
 * - GET    /api/v1/chat/sessions/:id/messages
 * - POST   /api/v1/chat/sessions/:id/messages
 * - GET    /api/v1/chat/sessions/active
 * - GET    /api/v1/chat/sessions/stats
 */

class ChatChannelsApiService extends BaseApiService {
  private channelsPath = '/chat/channels';
  private sessionsPath = '/chat/sessions';

  // ===================================================================
  // Channel Operations
  // ===================================================================

  /**
   * Get list of chat channels
   * GET /api/v1/chat/channels
   */
  async getChannels(filters?: ChannelFilters): Promise<PaginatedResponse<ChatChannelSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ChatChannelSummary>>(this.channelsPath + queryString);
  }

  /**
   * Get single channel by ID
   * GET /api/v1/chat/channels/:id
   */
  async getChannel(channelId: string): Promise<{ channel: ChatChannel }> {
    return this.get<{ channel: ChatChannel }>(`${this.channelsPath}/${channelId}`);
  }

  /**
   * Create a new chat channel
   * POST /api/v1/chat/channels
   */
  async createChannel(request: CreateChannelRequest): Promise<{ channel: ChatChannel }> {
    return this.post<{ channel: ChatChannel }>(this.channelsPath, { channel: request });
  }

  /**
   * Update a chat channel
   * PATCH /api/v1/chat/channels/:id
   */
  async updateChannel(channelId: string, request: UpdateChannelRequest): Promise<{ channel: ChatChannel }> {
    return this.patch<{ channel: ChatChannel }>(`${this.channelsPath}/${channelId}`, { channel: request });
  }

  /**
   * Delete a chat channel
   * DELETE /api/v1/chat/channels/:id
   */
  async deleteChannel(channelId: string): Promise<{ message: string }> {
    return this.delete<{ message: string }>(`${this.channelsPath}/${channelId}`);
  }

  /**
   * Connect a chat channel
   * POST /api/v1/chat/channels/:id/connect
   */
  async connectChannel(channelId: string): Promise<{ channel: ChatChannel }> {
    return this.post<{ channel: ChatChannel }>(`${this.channelsPath}/${channelId}/connect`);
  }

  /**
   * Disconnect a chat channel
   * POST /api/v1/chat/channels/:id/disconnect
   */
  async disconnectChannel(channelId: string): Promise<{ channel: ChatChannel }> {
    return this.post<{ channel: ChatChannel }>(`${this.channelsPath}/${channelId}/disconnect`);
  }

  /**
   * Test channel connection
   * POST /api/v1/chat/channels/:id/test
   */
  async testChannel(channelId: string): Promise<{ message: string; details?: Record<string, unknown> }> {
    return this.post<{ message: string; details?: Record<string, unknown> }>(`${this.channelsPath}/${channelId}/test`);
  }

  /**
   * Regenerate webhook token
   * POST /api/v1/chat/channels/:id/regenerate_token
   */
  async regenerateToken(channelId: string): Promise<{ channel: ChatChannel; webhook_url: string }> {
    return this.post<{ channel: ChatChannel; webhook_url: string }>(`${this.channelsPath}/${channelId}/regenerate_token`);
  }

  /**
   * Get channel sessions
   * GET /api/v1/chat/channels/:id/sessions
   */
  async getChannelSessions(channelId: string, filters?: SessionFilters): Promise<PaginatedResponse<ChatSessionSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ChatSessionSummary>>(`${this.channelsPath}/${channelId}/sessions${queryString}`);
  }

  /**
   * Get channel metrics
   * GET /api/v1/chat/channels/:id/metrics
   */
  async getChannelMetrics(channelId: string): Promise<{ metrics: ChannelMetrics }> {
    return this.get<{ metrics: ChannelMetrics }>(`${this.channelsPath}/${channelId}/metrics`);
  }

  /**
   * Get supported platforms
   * GET /api/v1/chat/channels/platforms
   */
  async getPlatforms(): Promise<{ platforms: PlatformInfo[] }> {
    return this.get<{ platforms: PlatformInfo[] }>(`${this.channelsPath}/platforms`);
  }

  // ===================================================================
  // Session Operations
  // ===================================================================

  /**
   * Get list of sessions
   * GET /api/v1/chat/sessions
   */
  async getSessions(filters?: SessionFilters): Promise<PaginatedResponse<ChatSessionSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ChatSessionSummary>>(this.sessionsPath + queryString);
  }

  /**
   * Get single session by ID
   * GET /api/v1/chat/sessions/:id
   */
  async getSession(sessionId: string): Promise<{ session: ChatSession }> {
    return this.get<{ session: ChatSession }>(`${this.sessionsPath}/${sessionId}`);
  }

  /**
   * Update a session
   * PATCH /api/v1/chat/sessions/:id
   */
  async updateSession(sessionId: string, updates: Partial<ChatSession>): Promise<{ session: ChatSession }> {
    return this.patch<{ session: ChatSession }>(`${this.sessionsPath}/${sessionId}`, { session: updates });
  }

  /**
   * Delete a session
   * DELETE /api/v1/chat/sessions/:id
   */
  async deleteSession(sessionId: string): Promise<{ message: string }> {
    return this.delete<{ message: string }>(`${this.sessionsPath}/${sessionId}`);
  }

  /**
   * Transfer session to another agent
   * POST /api/v1/chat/sessions/:id/transfer
   */
  async transferSession(sessionId: string, agentId: string): Promise<{ session: ChatSession; message: string }> {
    return this.post<{ session: ChatSession; message: string }>(`${this.sessionsPath}/${sessionId}/transfer`, { agent_id: agentId });
  }

  /**
   * Close a session
   * POST /api/v1/chat/sessions/:id/close
   */
  async closeSession(sessionId: string, reason?: string): Promise<{ session: ChatSession }> {
    return this.post<{ session: ChatSession }>(`${this.sessionsPath}/${sessionId}/close`, { reason });
  }

  /**
   * Get session messages
   * GET /api/v1/chat/sessions/:id/messages
   */
  async getSessionMessages(sessionId: string, filters?: MessageFilters): Promise<PaginatedResponse<ChatMessageSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ChatMessageSummary>>(`${this.sessionsPath}/${sessionId}/messages${queryString}`);
  }

  /**
   * Send message to session
   * POST /api/v1/chat/sessions/:id/messages
   */
  async sendMessage(sessionId: string, request: SendMessageRequest): Promise<{ message: ChatMessage }> {
    return this.post<{ message: ChatMessage }>(`${this.sessionsPath}/${sessionId}/messages`, request);
  }

  /**
   * Get active sessions
   * GET /api/v1/chat/sessions/active
   */
  async getActiveSessions(groupByChannel?: boolean): Promise<PaginatedResponse<ChatSessionSummary> | { sessions_by_channel: Record<string, ChatSessionSummary[]> }> {
    const queryString = groupByChannel ? '?group_by_channel=true' : '';
    return this.get(`${this.sessionsPath}/active${queryString}`);
  }

  /**
   * Get session statistics
   * GET /api/v1/chat/sessions/stats
   */
  async getSessionStats(): Promise<{ stats: SessionStats }> {
    return this.get<{ stats: SessionStats }>(`${this.sessionsPath}/stats`);
  }
}

export const chatChannelsApi = new ChatChannelsApiService();
