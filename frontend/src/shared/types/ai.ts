// AI Provider System TypeScript Interfaces

export interface AiProvider {
  id: string;
  name: string;
  slug: string;
  provider_type: 'text_generation' | 'image_generation' | 'code_execution' | 'embedding' | 'multimodal';
  description: string;
  api_base_url: string;
  capabilities: string[];
  supported_models: ModelInfo[];
  configuration_schema: Record<string, unknown>;
  default_parameters: Record<string, unknown>;
  rate_limits: Record<string, unknown>;
  pricing_info: Record<string, unknown>;
  metadata: Record<string, unknown>;
  is_active: boolean;
  requires_auth: boolean;
  supports_streaming: boolean;
  supports_functions: boolean;
  supports_vision: boolean;
  supports_code_execution: boolean;
  documentation_url?: string;
  status_url?: string;
  priority_order: number;
  credential_count: number;
  model_count: number;
  health_status: 'healthy' | 'unhealthy' | 'unknown' | 'inactive';
  created_at: string;
  updated_at: string;
  credentials?: AiProviderCredential[];
}

export interface ModelInfo {
  id: string;
  name: string;
  context_length: number | string;
  cost_per_token?: number;
  input_cost_per_token?: number;
  output_cost_per_token?: number;
  max_tokens?: number;
  supports_streaming?: boolean;
  supports_functions?: boolean;
  supports_vision?: boolean;
  description?: string;
  size_bytes?: number;
  family?: string;
  parameter_size?: string;
  quantization_level?: string;
}

export interface AiProviderCredential {
  id: string;
  name: string;
  ai_provider: {
    id: string;
    name: string;
    slug: string;
    provider_type: string;
  };
  is_active: boolean;
  is_default: boolean;
  expires_at?: string;
  last_used_at?: string;
  consecutive_failures: number;
  health_status: 'healthy' | 'unhealthy';
  access_scopes: string[];
  rate_limits: Record<string, unknown>;
  usage_stats: Record<string, unknown>;
  last_error?: string;
  encryption_key_id: string;
  expires_soon: boolean;
  can_be_used: boolean;
  last_test_at?: string;
  last_test_status?: 'success' | 'failure';
  created_at: string;
  updated_at: string;
  recent_test?: {
    success: boolean;
    last_tested_at: string;
    failures_since_success: number;
  };
}

export interface AiAgent {
  id: string;
  name: string;
  description: string;
  agent_type: 'assistant' | 'code_assistant' | 'data_analyst' | 'content_generator' | 'image_generator';
  // Provider info
  provider?: {
    id: string;
    name: string;
    slug: string;
    provider_type: string;
  };
  // Model config - single source of truth (from backend accessors)
  model?: string;
  temperature?: number;
  max_tokens?: number;
  system_prompt?: string;
  // MCP Architecture fields
  mcp_tool_manifest: {
    name: string;
    description: string;
    type: string;
    version: string;
    configuration?: AgentConfiguration;
    [key: string]: unknown;
  };
  mcp_input_schema: Record<string, unknown>;
  mcp_output_schema: Record<string, unknown>;
  mcp_metadata: Record<string, unknown>;
  // Skills
  skill_slugs?: string[];
  skills?: Array<{
    id: string;
    name: string;
    slug: string;
    category: string;
    is_active: boolean;
    priority: number;
    command_count: number;
  }>;
  status: 'active' | 'inactive' | 'error';
  metadata: Record<string, unknown>;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  execution_stats?: {
    total_executions: number;
    successful_executions: number;
    failed_executions: number;
    success_rate: number;
    avg_execution_time: number;
  };
}

export interface AgentConfiguration {
  model: string;
  temperature?: number;
  max_tokens?: number;
  top_p?: number;
  frequency_penalty?: number;
  presence_penalty?: number;
  system_prompt?: string;
  tools?: string[];
  [key: string]: string | number | boolean | string[] | undefined;
}

export interface AiConversation {
  id: string;
  title: string;
  status: 'active' | 'completed' | 'archived' | 'error';
  conversation_type?: 'agent' | 'team' | 'provisioning';
  ai_agent: {
    id: string;
    name: string;
    agent_type: string;
    is_concierge?: boolean;
  };
  agent_team?: {
    id: string;
    name: string;
    team_type?: string;
  };
  metadata: {
    created_by: string;
    total_messages: number;
    total_tokens: number;
    total_cost: number;
    last_activity: string;
    [key: string]: string | number | boolean | undefined;
  };
  created_at: string;
  updated_at: string;
  message_count?: number;
}

export interface MessageAction {
  type: 'approve' | 'request_changes';
  label: string;
  style: 'primary' | 'secondary';
  icon?: string;
}

export interface ActionContext {
  execution_id: string;
  team_id: string;
  team_name: string;
  status: 'pending' | 'approved' | 'changes_requested';
  resolved_at?: string;
}

/**
 * Rich chat card surfaced from a tool result. The Concierge writes these to
 * `assistant_message.content_metadata.cards` whenever a whitelisted tool fires
 * (see `Ai::AgentToolBridge::CARD_TOOLS` on the backend). The frontend reads
 * them via `mapBackendMessage` and renders the appropriate component per `kind`.
 */
export type ChatCardKind =
  | 'provisioning_brief'
  | 'provisioning_plan'
  | 'provisioning_plan_approved'
  | 'provisioning_execution'
  | 'provisioning_status'
  | 'provisioning_adaptation'
  // D3 — Platform deployment wizard. Two-shape payload: form (no mode
  // supplied → render the inline form) and done (mode set → show the
  // success summary + acceptance_token for federated mode).
  | 'platform_deployment_wizard'
  // A2UI (Google's declarative generative-UI spec, v0.9) surface. payload is an
  // A2uiSurfacePayload (see features/ai/a2ui); rendered by A2uiChatCardSlot.
  | 'a2ui_surface';

export interface ChatCard {
  kind: ChatCardKind;
  tool: string;
  arguments?: Record<string, unknown>;
  payload: Record<string, unknown>;
}

export interface AiMessage {
  id: string;
  sender_type: 'user' | 'ai' | 'system';
  sender_id?: string;
  user_id?: string;
  content: string;
  role?: 'user' | 'assistant' | 'system' | 'function';
  message_type?: 'text' | 'image' | 'audio' | 'video' | 'file' | 'code';
  status?: 'sent' | 'processing' | 'completed' | 'failed';
  is_edited?: boolean;
  edited_at?: string;
  deleted_at?: string;
  parent_message_id?: string;
  reply_count?: number;
  sequence_number?: number;
  metadata?: {
    timestamp?: string;
    processing?: boolean;
    error?: boolean;
    error_message?: string;
    provider_id?: string;
    model_used?: string;
    tokens_used?: number;
    response_time_ms?: number;
    cost_estimate?: number;
    processing_complete?: boolean;
    actions?: MessageAction[];
    action_context?: ActionContext;
    concierge_action?: string;
    action_params?: Record<string, unknown>;
    cards?: ChatCard[];
    user_rating?: {
      rating: string;
      rated_at: string;
      rated_by: string;
    };
    [key: string]: unknown;
  };
  attachments?: Array<{
    type: string;
    name: string;
    size: number;
    url?: string;
    preview_url?: string;
  }>;
  created_at: string;
  sender_info?: {
    id?: string;
    name: string;
    avatar_url?: string;
    provider?: string;
    agent_type?: string;
  };
}

export interface AiAgentExecution {
  id: string;
  ai_agent: {
    id: string;
    name: string;
  };
  input_data: {
    prompt: string;
    parameters: Record<string, any>;
  };
  status: 'queued' | 'running' | 'processing' | 'completed' | 'failed' | 'cancelled';
  started_at?: string;
  completed_at?: string;
  result?: {
    output?: string;
    metrics?: {
      tokens_used: number;
      response_time_ms: number;
      cost_estimate: number;
      api_calls?: number;
      memory_usage_mb?: number;
    };
    artifacts?: Array<{
      name: string;
      type: string;
      size: number;
      url: string;
      metadata: Record<string, unknown>;
    }>;
    error?: boolean;
    error_message?: string;
    cancelled?: boolean;
    [key: string]: unknown;
  };
  metadata: {
    priority: 'low' | 'normal' | 'high';
    retry_count: number;
    created_by: string;
    [key: string]: string | number | boolean | undefined;
  };
  progress_percentage?: number;
  duration_seconds?: number;
  created_at: string;
  updated_at: string;
}

// API Request/Response Types

export interface SendMessageRequest {
  content: string;
  context?: Record<string, unknown>;
}

export interface ExecuteAgentRequest {
  execution: {
    ai_agent_id: string;
    input_data: {
      prompt: string;
      parameters?: Record<string, unknown>;
    };
    metadata?: {
      priority?: 'low' | 'normal' | 'high';
      [key: string]: unknown;
    };
  };
}

// Provider Test Results
// Analytics and Usage Types

export interface SystemHealthStatus {
  overall_health: 'healthy' | 'degraded' | 'unhealthy';
  active_executions: number;
  total_providers: number;
  healthy_providers: number;
  recent_errors: number;
  system_load: string | number;
}

export interface AccountMetrics {
  executions_today: number;
  successful_executions: number;
  failed_executions: number;
  active_conversations: number;
  total_tokens_used: number;
  estimated_cost: number;
}

// WebSocket Message Types
export interface ConversationChannelMessage {
  type: 'subscription_confirmed' | 'message_created' | 'message_updated' | 'ai_response_streaming' | 'ai_response_complete' | 'ai_thinking' | 'processing_status' | 'typing_indicator' | 'message_read' | 'conversation_status' | 'error';
  conversation_id?: string;
  status?: string;
  message?: AiMessage;
  agent_name?: string;
  streaming?: boolean;
  metadata?: Record<string, unknown>;
  user_id?: string;
  user_name?: string;
  typing?: boolean;
  message_id?: string;
  read_by?: string;
  read_at?: string;
  message_count?: number;
  last_activity?: string;
  participants?: Array<{
    id: string;
    name: string;
    email: string;
    last_message_at?: string;
  }>;
  ai_agent?: {
    id: string;
    name: string;
    status: string;
  };
  timestamp?: string;
}

// Pagination and Filtering
export interface PaginationParams {
  page?: number;
  per_page?: number;
}

export interface ProvidersFilters extends PaginationParams {
  provider_type?: string;
  capability?: string;
  search?: string;
  sort?: 'name' | 'priority' | 'created_at';
}

// Advanced Conversation Analytics
export interface ConversationAnalytics {
  totalConversations: number;
  avgMessagesPerConversation: number;
  avgResponseTime: number;
  sentimentBreakdown: {
    positive: number;
    neutral: number;
    negative: number;
  };
  topAgents: Array<{
    id: string;
    name: string;
    conversationCount: number;
    avgResponseTime: number;
  }>;
  activityTrend: Array<{
    date: string;
    conversations: number;
    messages: number;
  }>;
  collaborationStats: {
    soloConversations: number;
    collaborativeConversations: number;
    avgParticipants: number;
  };
}

// AI Data Source System TypeScript Interfaces

export interface AiDataSource {
  id: string;
  account_id: string;
  name: string;
  slug: string;
  source_type: string;
  description: string;
  api_base_url: string;
  capabilities: string[];
  configuration: Record<string, unknown>;
  rate_limits: Record<string, number>;
  default_parameters: Record<string, unknown>;
  metadata: Record<string, unknown>;
  is_active: boolean;
  requires_auth: boolean;
  priority_order: number;
  documentation_url?: string;
  health_status: 'healthy' | 'degraded' | 'critical' | 'unknown';
  last_health_check_at?: string;
  credential_count: number;
  created_at: string;
  updated_at: string;
  credentials?: AiDataSourceCredential[];
  quota?: DataSourceQuota;
}

export interface AiDataSourceCredential {
  id: string;
  name: string;
  is_active: boolean;
  is_default: boolean;
  expires_at?: string;
  last_used_at?: string;
  last_test_at?: string;
  last_test_status?: 'success' | 'failed';
  last_error?: string;
  consecutive_failures: number;
  success_count: number;
  failure_count: number;
  created_at: string;
  updated_at: string;
}

export interface DataSourceQuota {
  usage: { minute: number; hour: number; day: number; bandwidth_today: number };
  limits: Record<string, number>;
  utilization: { minute_pct: number | null; hour_pct: number | null; day_pct: number | null };
}

export interface DataSourceFilters extends PaginationParams {
  source_type?: string;
  search?: string;
  sort?: 'name' | 'priority' | 'created_at';
}