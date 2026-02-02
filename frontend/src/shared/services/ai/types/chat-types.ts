/**
 * Chat Gateway Types
 *
 * Types for chat channels, sessions, and messaging across
 * external platforms (Telegram, Discord, Slack, WhatsApp, Mattermost)
 */

// Platform types
export type ChatPlatform = 'telegram' | 'discord' | 'slack' | 'whatsapp' | 'mattermost';

export type ChannelStatus = 'active' | 'inactive' | 'error' | 'disconnected';

export type SessionStatus = 'active' | 'idle' | 'transferred' | 'closed' | 'expired';

export type MessageDirection = 'inbound' | 'outbound';

export type MessageType = 'text' | 'image' | 'audio' | 'video' | 'document' | 'location' | 'contact' | 'sticker';

export type DeliveryStatus = 'pending' | 'sent' | 'delivered' | 'read' | 'failed';

// Channel types
export interface ChatChannel {
  id: string;
  account_id: string;
  platform: ChatPlatform;
  name: string;
  status: ChannelStatus;
  webhook_token: string;
  webhook_url?: string;
  default_agent_id?: string;
  default_agent_name?: string;
  rate_limit_per_minute: number;
  auto_respond: boolean;
  welcome_message?: string;
  session_timeout_minutes: number;
  configuration: Record<string, unknown>;
  connected_at?: string;
  last_message_at?: string;
  total_sessions: number;
  active_sessions: number;
  created_at: string;
  updated_at: string;
}

export interface ChatChannelSummary {
  id: string;
  platform: ChatPlatform;
  name: string;
  status: ChannelStatus;
  active_sessions: number;
  total_sessions: number;
  last_message_at?: string;
}

export interface CreateChannelRequest {
  name: string;
  platform: ChatPlatform;
  default_agent_id?: string;
  rate_limit_per_minute?: number;
  auto_respond?: boolean;
  welcome_message?: string;
  session_timeout_minutes?: number;
  configuration?: Record<string, unknown>;
}

export interface UpdateChannelRequest {
  name?: string;
  default_agent_id?: string;
  rate_limit_per_minute?: number;
  auto_respond?: boolean;
  welcome_message?: string;
  session_timeout_minutes?: number;
  configuration?: Record<string, unknown>;
}

export interface ChannelFilters {
  platform?: ChatPlatform;
  status?: ChannelStatus;
  active?: boolean;
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

// Session types
export interface ChatSession {
  id: string;
  channel_id: string;
  channel_name: string;
  platform: ChatPlatform;
  platform_user_id: string;
  platform_username?: string;
  ai_conversation_id?: string;
  assigned_agent_id?: string;
  assigned_agent_name?: string;
  status: SessionStatus;
  context_window: Record<string, unknown>;
  message_count: number;
  first_message_at?: string;
  last_activity_at: string;
  avg_response_time_ms?: number;
  created_at: string;
  updated_at: string;
}

export interface ChatSessionSummary {
  id: string;
  channel_id: string;
  platform: ChatPlatform;
  platform_user_id: string;
  platform_username?: string;
  status: SessionStatus;
  message_count: number;
  last_activity_at: string;
}

export interface SessionFilters {
  channel_id?: string;
  status?: SessionStatus;
  agent_id?: string;
  active?: boolean;
  platform_user_id?: string;
  since?: string;
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

// Message types
export interface ChatMessage {
  id: string;
  session_id: string;
  channel_id: string;
  ai_message_id?: string;
  direction: MessageDirection;
  message_type: MessageType;
  content: string;
  sanitized_content: string;
  delivery_status: DeliveryStatus;
  platform_metadata: Record<string, unknown>;
  attachments?: ChatMessageAttachment[];
  created_at: string;
}

export interface ChatMessageSummary {
  id: string;
  direction: MessageDirection;
  message_type: MessageType;
  content: string;
  delivery_status: DeliveryStatus;
  created_at: string;
}

export interface ChatMessageAttachment {
  id: string;
  file_type: string;
  file_name: string;
  file_size: number;
  mime_type: string;
  url?: string;
  transcription?: string;
}

export interface SendMessageRequest {
  content: string;
  message_type?: MessageType;
}

export interface MessageFilters {
  direction?: MessageDirection;
  type?: MessageType;
  since?: string;
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

// Metrics types
export interface ChannelMetrics {
  total_sessions: number;
  active_sessions: number;
  total_messages: number;
  messages_today: number;
  avg_response_time_ms?: number;
  resolution_rate?: number;
  messages_per_hour?: number;
  avg_session_duration_ms?: number;
  error_rate?: number;
  last_message_at?: string;
  status: ChannelStatus;
}

export interface SessionStats {
  total: number;
  active: number;
  closed: number;
  avg_duration_minutes?: number;
  avg_messages_per_session?: number;
  by_platform: Record<ChatPlatform, number>;
  by_status: Record<SessionStatus, number>;
}

// Platform info
export interface PlatformInfo {
  id: ChatPlatform;
  name: string;
  supported: boolean;
  webhook_required: boolean;
  oauth_required: boolean;
}
