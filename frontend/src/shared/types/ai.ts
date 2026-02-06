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
  agent_type: 'assistant' | 'code_assistant' | 'data_analyst' | 'content_generator' | 'image_generator' | 'workflow_optimizer';
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
  ai_agent: {
    id: string;
    name: string;
    agent_type: string;
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

export interface AiMessage {
  id: string;
  sender_type: 'user' | 'ai' | 'system';
  sender_id?: string;
  content: string;
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
    user_rating?: {
      rating: string;
      rated_at: string;
      rated_by: string;
    };
    [key: string]: unknown;
  };
  created_at: string;
  sender_info?: {
    name: string;
    avatar_url?: string;
    provider?: string;
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
export interface CreateProviderCredentialRequest {
  credential: {
    ai_provider_id: string;
    name: string;
    credentials: Record<string, unknown>;
    access_scopes?: string[];
    rate_limits?: Record<string, unknown>;
    expires_at?: string;
  };
}

export interface CreateAiAgentRequest {
  agent: {
    ai_provider_id: string;
    name: string;
    description?: string;
    agent_type: string;
    configuration: AgentConfiguration;
    metadata?: Record<string, unknown>;
  };
}

export interface CreateConversationRequest {
  conversation: {
    ai_agent_id: string;
    title: string;
    metadata?: Record<string, unknown>;
  };
}

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
export interface ProviderTestResult {
  success: boolean;
  response_time_ms?: number;
  provider?: string;
  model?: string;
  error?: string;
  error_details?: Record<string, unknown>;
}

export interface BulkTestResult {
  credential_id: string;
  credential_name: string;
  provider_name: string;
  success: boolean;
  response_time_ms?: number;
  error?: string;
}

// Analytics and Usage Types
export interface ProviderUsageSummary {
  total_executions: number;
  successful_executions: number;
  failed_executions: number;
  total_tokens_used: number;
  estimated_cost: number;
  avg_response_time: number;
  success_rate: number;
}

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
  type: 'subscription_confirmed' | 'message_created' | 'ai_response_streaming' | 'ai_response_complete' | 'processing_status' | 'typing_indicator' | 'message_read' | 'conversation_status' | 'error';
  conversation_id?: string;
  status?: string;
  message?: AiMessage;
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

export interface ExecutionChannelMessage {
  type: 'subscription_confirmed' | 'execution_started' | 'execution_progress' | 'execution_log' | 'execution_error' | 'execution_complete' | 'execution_cancelled' | 'execution_heartbeat' | 'execution_final_status' | 'execution_logs' | 'execution_metrics' | 'execution_artifacts' | 'error';
  execution_id?: string;
  status?: string;
  progress?: number;
  status_message?: string;
  started_at?: string;
  completed_at?: string;
  duration_seconds?: number;
  success?: boolean;
  cancelled_by?: string;
  cancelled_at?: string;
  reason?: string;
  log?: {
    id: string;
    level: 'debug' | 'info' | 'warn' | 'error';
    message: string;
    timestamp: string;
    metadata: Record<string, unknown>;
  };
  logs?: Array<{
    id: string;
    level: string;
    message: string;
    timestamp: string;
    metadata: Record<string, unknown>;
  }>;
  pagination?: {
    page: number;
    per_page: number;
    total_count: number;
  };
  metrics?: {
    duration_seconds: number;
    tokens_used: number;
    api_calls: number;
    cost_estimate: number;
    memory_usage_mb?: number;
    error_count: number;
    retry_count: number;
  };
  performance?: {
    avg_response_time: number;
    throughput: number;
    success_rate: number;
  };
  artifacts?: Array<{
    name: string;
    type: string;
    size: number;
    url: string;
    metadata: Record<string, unknown>;
    created_at: string;
  }>;
  result_summary?: {
    success: boolean;
    output_size: number;
    artifacts_count: number;
    tokens_used: number;
  };
  result_preview?: {
    output_size: number;
    error_count: number;
    has_artifacts: boolean;
    metrics_available: boolean;
  };
  agent?: {
    id: string;
    name: string;
  };
  updated_at?: string;
  timestamp?: string;
  system_stats?: Record<string, unknown>;
  health_status?: string;
  error_message?: string;
  error_details?: Record<string, unknown>;
}

export interface MonitoringChannelMessage {
  type: 'initial_monitoring_status' | 'monitoring_update' | 'system_alert' | 'provider_status_update' | 'account_metrics_update' | 'execution_anomaly' | 'performance_degradation' | 'alert_history' | 'monitoring_config_updated' | 'detailed_system_metrics' | 'detailed_account_metrics' | 'detailed_provider_metrics' | 'detailed_providers_metrics' | 'detailed_agent_metrics' | 'detailed_agents_metrics' | 'alert_acknowledged' | 'error';
  status?: {
    system?: SystemHealthStatus;
    account?: AccountMetrics;
    providers?: Array<{
      id: string;
      name: string;
      health_status: string;
      active_credentials: number;
      recent_executions: number;
      success_rate: number;
    }>;
    agents?: Array<{
      id: string;
      name: string;
      status: string;
      executions_today: number;
      success_rate: number;
      last_execution?: string;
    }>;
    executions?: {
      total_recent: number;
      running: number;
      completed: number;
      failed: number;
      cancelled: number;
      avg_duration: number;
    };
  };
  interval?: string;
  components?: string[];
  timestamp?: string;
  data?: {
    system_health?: Record<string, unknown>;
    account_metrics?: Record<string, unknown>;
    provider_health?: Record<string, unknown>;
  };
  alert?: Record<string, unknown>;
  provider_id?: string;
  provider_name?: string;
  account_id?: string;
  metrics?: Record<string, unknown>;
  execution_id?: string;
  anomaly?: Record<string, unknown>;
  component?: string;
  alerts?: Array<{
    id: string;
    severity: 'low' | 'medium' | 'high' | 'critical';
    component: string;
    title: string;
    message: string;
    metadata: Record<string, unknown>;
    acknowledged: boolean;
    acknowledged_at?: string;
    acknowledged_by?: string;
    created_at: string;
    resolved_at?: string;
  }>;
  pagination?: {
    page: number;
    per_page: number;
    total_count: number;
  };
  alert_id?: string;
  acknowledged_by?: string;
  acknowledged_at?: string;
  time_range?: string;
  agent_id?: string;
  generated_at?: string;
  message?: string;
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

export interface CredentialsFilters extends PaginationParams {
  provider_id?: string;
  active?: boolean;
  default_only?: boolean;
  search?: string;
  sort?: 'name' | 'provider' | 'last_used' | 'created_at';
}

export interface AgentsFilters extends PaginationParams {
  provider_id?: string;
  agent_type?: string;
  status?: string;
  search?: string;
  sort?: 'name' | 'provider' | 'created_at' | 'last_used';
}

export interface ConversationsFilters extends PaginationParams {
  agent_id?: string;
  status?: string;
  search?: string;
  sort?: 'title' | 'created_at' | 'updated_at' | 'last_activity';
}

export interface ExecutionsFilters extends PaginationParams {
  agent_id?: string;
  status?: string;
  sort?: 'created_at' | 'started_at' | 'completed_at' | 'duration';
  time_range?: string;
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