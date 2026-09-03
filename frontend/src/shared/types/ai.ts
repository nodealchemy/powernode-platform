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
    by_executor_kind?: ExecutionsByExecutorKind;
  };
}

/**
 * Executions split by who ran them (HIER-P1C): the platform's own executor vs
 * a Claude Code session that ran the agent locally and reported back through
 * platform.record_agent_execution. Both count toward total_executions. A
 * Claude Code run's input tokens include cache_read + cache_creation, so its
 * token figures are not directly comparable to a platform execution's.
 */
export interface ExecutionsByExecutorKind {
  platform: number;
  claude_code: number;
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
    parameters: Record<string, unknown>;
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

export type DataSourceHealthStatus = 'healthy' | 'degraded' | 'critical' | 'unknown';

// x-com-provider campaign (I5): provider-agnostic OAuth2 connect config, read-only
// here — a source gets this from a template (e.g. the X.com template) or an admin
// tool, never from this UI. authorize_url's presence is what the frontend uses to
// decide whether to show the OAuth2 connect panel for a source.
export interface DataSourceAuthConfig {
  authorize_url?: string;
  token_url?: string;
  scopes?: string[];
  scope?: string;
  [key: string]: unknown;
}

export interface AiDataSource {
  id: string;
  account_id: string;
  name: string;
  slug: string;
  source_type: string;
  // Free-form grouping label (weather/finance/sports/news/…). Nullable: legacy
  // rows and sources without a category yet. Backfilled from source_type.
  category?: string | null;
  // Request protocol selecting the backend adapter (rest|graphql|rss|atom).
  // Defaults to "rest" server-side; optional so older serializers degrade.
  protocol?: DataSourceProtocol | string | null;
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
  // Crawl-politeness: when true, the monitor honors the host's robots.txt and
  // paces requests per host. Off by default. crawl_delay_seconds is the minimum
  // seconds between requests to the same host (used as the floor; robots.txt
  // Crawl-delay may raise it). Optional so the UI degrades while the backend
  // serializer rollout is in flight.
  respect_robots?: boolean;
  crawl_delay_seconds?: number | null;
  health_status: DataSourceHealthStatus;
  last_health_check_at?: string;
  credential_count: number;
  created_at: string;
  updated_at: string;
  credentials?: AiDataSourceCredential[];
  quota?: DataSourceQuota;
  // Detail-view only (serialize_data_source_detail). Absent from list rows.
  auth_config?: DataSourceAuthConfig | null;
  // Phase 2 trust signals — populated once the backend serializer exposes the
  // effectiveness/usage columns (Ai::DataSource#recalculate_effectiveness!).
  // Optional so cards degrade gracefully while the rollout is in flight.
  effectiveness_score?: number | null;
  usage_count?: number | null;
  positive_usage_count?: number | null;
  negative_usage_count?: number | null;
  usage_success_rate?: number | null;
  last_used_at?: string | null;
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
  // x-com-provider campaign (I5): OAuth2 connect state. client_id, tokens, and
  // client_secret are NEVER serialized — only presence/derived booleans travel here.
  oauth_configured?: boolean;
  oauth_connected?: boolean;
  oauth_scopes?: string[];
  oauth_token_expires_at?: string | null;
  oauth_token_expired?: boolean;
}

// x-com-provider campaign (I5): response of POST .../oauth/authorize.
export interface DataSourceOauthAuthorizeResponse {
  authorization_url: string;
  redirect_uri: string;
  state: string;
}

export interface DataSourceQuota {
  usage: { minute: number; hour: number; day: number; bandwidth_today: number };
  limits: Record<string, number>;
  utilization: { minute_pct: number | null; hour_pct: number | null; day_pct: number | null };
}

export interface DataSourceFilters extends PaginationParams {
  source_type?: string;
  // Free-form category filter (mirrors Ai::DataSource scope :by_category).
  category?: string;
  search?: string;
  sort?: 'name' | 'priority' | 'created_at';
}

// Request protocol selecting which backend adapter the registry uses. REST is
// the generic fallback; graphql/rss/atom have dedicated adapters. Backend stores
// it as a free-form string column (default "rest"), so allow string widening.
export type DataSourceProtocol = 'rest' | 'graphql' | 'rss' | 'atom';

// Data Source Endpoints — governed external-fetch endpoint definitions.
// Mirrors Ai::DataSourceSerialization#serialize_data_source_endpoint.

export type DataSourceHttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD';

export type DataSourceResponseFormat =
  | 'json' | 'xml' | 'csv' | 'ndjson' | 'rss' | 'atom' | 'html' | 'text' | 'binary';

export type DataSourceChangeDetection =
  | 'etag' | 'last_modified' | 'content_hash' | 'polling' | 'none';

// Outbound pagination strategy for an endpoint. When configured, the REST
// adapter / QueryService follows up to `max_pages` (hard-capped server-side,
// e.g. 20), concatenating canonical records. Blank/absent => single request
// (the default). Mirrors the ai_data_source_endpoints.pagination jsonb column.
export type DataSourcePaginationType = 'offset' | 'page' | 'cursor' | 'link';

export interface DataSourceEndpointPagination {
  type?: DataSourcePaginationType;
  limit_param?: string;
  // offset-based
  offset_param?: string;
  // page-number-based
  page_param?: string;
  // cursor-based: param to send the cursor in + JSON path to read the next cursor
  cursor_param?: string;
  cursor_path?: string;
  // Hard cap on follow-up requests (server clamps to its own max).
  max_pages?: number;
}

// Incremental-sync mode for an endpoint. "cursor" carries an opaque cursor token;
// "timestamp" carries a high-watermark time value. Both inject the stored
// subscription high-watermark into the next fetch and read the next watermark
// back from the response. Mirrors the ai_data_source_endpoints.incremental jsonb.
export type DataSourceIncrementalMode = 'cursor' | 'timestamp';

// Incremental-sync config (ai_data_source_endpoints.incremental jsonb). When
// configured AND a subscription has a sync_cursor, the monitor injects the
// cursor into the fetch params under `cursor_param` and extracts the next cursor
// from the response via `cursor_path`. Empty object => incremental disabled.
export interface DataSourceEndpointIncremental {
  // Request param that carries the stored high-watermark (cursor/timestamp).
  cursor_param?: string;
  // JSON path to read the next high-watermark from the response.
  cursor_path?: string;
  mode?: DataSourceIncrementalMode;
}

export interface AiDataSourceEndpoint {
  id: string;
  ai_data_source_id: string;
  name: string;
  slug: string;
  http_method: DataSourceHttpMethod;
  path_template: string | null;
  response_format: DataSourceResponseFormat | null;
  expected_content_type: string | null;
  cache_ttl_seconds: number | null;
  monitorable: boolean;
  change_detection: DataSourceChangeDetection | null;
  query_template: Record<string, unknown>;
  body_template: Record<string, unknown>;
  response_mapping: Record<string, unknown>;
  response_schema: Record<string, unknown>;
  metadata: Record<string, unknown>;
  // Outbound pagination config (ai_data_source_endpoints.pagination jsonb).
  // Empty object => single request (the default). Optional so the UI degrades
  // gracefully until the backend serializer exposes the column.
  pagination?: DataSourceEndpointPagination;
  // Incremental-sync config (ai_data_source_endpoints.incremental jsonb). Empty
  // object => incremental disabled (the default). Optional so the UI degrades
  // gracefully until the backend serializer exposes the column.
  incremental?: DataSourceEndpointIncremental;
  // Phase 2b observability opt-in flags + SLA/ownership/contract metadata. All
  // OFF by default; populated once the backend serializer exposes the columns
  // added by AddQualityOptInToAiDataSourceEndpoints. Optional so the UI degrades
  // gracefully while the rollout is in flight.
  track_schema?: boolean;
  quality_checks_enabled?: boolean;
  quarantine_on_failure?: boolean;
  sla_max_age_seconds?: number | null;
  owner?: string | null;
  contract?: Record<string, unknown>;
  // Phase 3 stale-while-revalidate window (seconds) for the response cache. When
  // set, a cache hit within [hard_expiry, hard_expiry + stale_while_revalidate]
  // serves the stale payload (flagged) and triggers a background refresh;
  // stale_if_error serves a stale entry on upstream 5xx/timeout/breaker-OPEN.
  // Both null/absent => SWR disabled (the default). Optional so the UI degrades
  // gracefully until the backend serializer exposes the columns.
  stale_while_revalidate_seconds?: number | null;
  stale_if_error_seconds?: number | null;
  created_at: string;
  updated_at: string;
}

// Payload accepted by the endpoint create/update controller actions.
export interface DataSourceEndpointRequest {
  name: string;
  slug?: string;
  http_method: DataSourceHttpMethod;
  path_template?: string | null;
  response_format?: DataSourceResponseFormat | null;
  expected_content_type?: string | null;
  cache_ttl_seconds?: number | null;
  monitorable?: boolean;
  change_detection?: DataSourceChangeDetection | null;
  query_template?: Record<string, unknown>;
  body_template?: Record<string, unknown>;
  response_mapping?: Record<string, unknown>;
  response_schema?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  // Outbound pagination config. Send {} (or omit) to leave pagination off.
  pagination?: DataSourceEndpointPagination;
  // Incremental-sync config. Send {} (or omit) to leave incremental sync off.
  incremental?: DataSourceEndpointIncremental;
  // Phase 2b opt-in observability controls.
  track_schema?: boolean;
  quality_checks_enabled?: boolean;
  quarantine_on_failure?: boolean;
  sla_max_age_seconds?: number | null;
  owner?: string | null;
  contract?: Record<string, unknown>;
  // Phase 3 stale-while-revalidate / stale-if-error windows (seconds). null or
  // omitted leaves SWR disabled for the endpoint.
  stale_while_revalidate_seconds?: number | null;
  stale_if_error_seconds?: number | null;
}

// Canonical record returned by the governed fetch — shape is source-specific.
export type DataSourceCanonicalRecord = Record<string, unknown>;

export type DataSourceQueryStatus =
  | 'success' | 'error' | 'timeout' | 'rate_limited' | 'blocked' | 'cached';

export interface DataSourceContentTypeComparison {
  declared?: string | null;
  detected?: string | null;
  content_type?: string | null;
  mismatch?: boolean;
}

// Mirrors the FetchEnvelope provenance from Ai::DataSources::QueryService.
export interface DataSourceQueryProvenance {
  slug?: string;
  endpoint_id?: string | null;
  fetched_at?: string | null;
  from_cache?: boolean;
  cache_age_seconds?: number;
  response_sha256?: string | null;
  source_url?: string | null;
  declared_vs_detected_content_type?: DataSourceContentTypeComparison | null;
  charset?: string | null;
  applied_encoding?: string | null;
  schema_valid?: boolean | null;
  record_count?: number;
  anomalies?: string[];
  normalization?: unknown;
  retry_after?: number;
  limit?: string;
  // Phase 2b stage outputs surfaced on provenance when the endpoint's opt-in
  // drift / quality / quarantine stages ran during the governed fetch.
  schema_drift?: DataSourceSchemaClassification | null;
  quality_score?: number | null;
  quality_passed?: boolean | null;
  quarantined?: boolean;
}

// FetchEnvelope returned by POST .../endpoints/:endpoint_id/query.
export interface DataSourceFetchEnvelope {
  success: boolean;
  data: DataSourceCanonicalRecord[];
  provenance: DataSourceQueryProvenance;
  status: DataSourceQueryStatus;
  duration_ms: number;
  bytes: number;
  error?: string | null;
  retry_after?: number;
  // Cost attribution is emitted server-side; surfaced when the API includes it.
  cost?: { amount?: number; currency?: string } | null;
  // Phase 2b: when the endpoint's quality stage ran, the verdict may ride on the
  // envelope directly (mirrors ContractService's envelope-first quality lookup).
  quality_passed?: boolean | null;
  quality_score?: number | null;
  quarantined?: boolean;
}

// ── Semantic discovery ────────────────────────────────────────────────────
// Ranked data-source discovery backed by Ai::DataSources::SemanticDiscoveryService
// (embedding + pgvector nearest-neighbor blended with effectiveness / health /
// recency). Mirrors DataSourceTool#discovery_result (a summarize_source payload
// merged with the blended score + its component signals).

// Per-candidate breakdown of the blended ranking score (each 0..1).
export interface DataSourceDiscoverySignals {
  semantic?: number;
  effectiveness?: number;
  health?: number;
  recency?: number;
}

// One ranked candidate. Carries the compact source summary surfaced by
// summarize_source plus the discovery ranking metadata.
export interface DataSourceDiscoveryResult {
  id: string;
  name: string;
  slug: string;
  source_type: string;
  protocol?: string | null;
  auth_scheme?: string | null;
  is_active: boolean;
  requires_auth: boolean;
  priority_order: number;
  health_status: DataSourceHealthStatus;
  credential_count: number;
  // Blended rank score (0..1) and its component signals.
  score: number;
  signals: DataSourceDiscoverySignals;
  effectiveness_score?: number | null;
}

// Envelope returned by DataSourcesApiService.discover().
export interface DataSourceDiscoveryResponse {
  query: string;
  count: number;
  results: DataSourceDiscoveryResult[];
}

// ── Phase 2b: schema drift, data quality, OpenAPI import, contract ──────────
// Mirrors the backend Ai::DataSources::{SchemaDriftService, QualityService,
// OpenApiImportService, ContractService} contracts and the Phase 2b models
// (Ai::DataSourceSchemaVersion, Ai::DataSourceExpectation).

// How a recorded schema version differs from its immediate predecessor.
//   initial  : first version for the endpoint (no prior schema)
//   none     : structurally identical to the previous version
//   additive : only new optional fields added (backward compatible)
//   breaking : a field was removed or changed type (NOT backward compatible)
export type DataSourceSchemaClassification = 'initial' | 'none' | 'additive' | 'breaking';

// One field whose declared type changed between two schema versions.
export interface DataSourceSchemaTypeChange {
  field: string;
  from: string;
  to: string;
}

// Structural diff stored on a schema version (vs the prior version). Dotted
// property paths; array element schemas use a "[]" suffix.
export interface DataSourceSchemaDiff {
  added_fields: string[];
  removed_fields: string[];
  type_changes: DataSourceSchemaTypeChange[];
}

// One appended response-schema snapshot for an endpoint.
// Mirrors Ai::DataSourceSchemaVersion.
export interface AiDataSourceSchemaVersion {
  id: string;
  ai_data_source_endpoint_id: string;
  version: number;
  schema: Record<string, unknown>;
  checksum: string | null;
  classification: DataSourceSchemaClassification;
  diff: DataSourceSchemaDiff;
  created_at: string;
  updated_at?: string;
}

// Response of GET .../endpoints/:endpoint_id/schema_history. `latest` is a
// convenience pointer to the most recent version (versions[0] when desc-ordered).
export interface DataSourceSchemaHistoryResponse {
  endpoint_id: string;
  count: number;
  versions: AiDataSourceSchemaVersion[];
  latest?: AiDataSourceSchemaVersion | null;
}

// Data-quality expectation rule kinds (Ai::DataSourceExpectation::RULE_TYPES).
export type DataSourceExpectationRuleType =
  | 'required_fields'
  | 'min_records'
  | 'max_records'
  | 'non_null'
  | 'allowed_values'
  | 'distribution';

// warn lowers the score only; error fails the batch (and can trigger quarantine).
export type DataSourceExpectationSeverity = 'warn' | 'error';

// One configured expectation for an endpoint. Mirrors Ai::DataSourceExpectation.
export interface AiDataSourceExpectation {
  id: string;
  ai_data_source_endpoint_id: string;
  name: string;
  rule_type: DataSourceExpectationRuleType;
  config: Record<string, unknown>;
  severity: DataSourceExpectationSeverity;
  is_active: boolean;
  created_at: string;
  updated_at?: string;
}

// One rule outcome from a QualityService evaluation.
export interface DataSourceQualityResult {
  name: string;
  rule_type: string;
  passed: boolean;
  severity: DataSourceExpectationSeverity;
  detail: string;
}


// The latest persisted quality outcome for an endpoint, distilled from the most
// recent quality-evaluated query-log row. All optional: an endpoint that has
// never run a quality-checked fetch has no latest outcome.
export interface DataSourceLatestQuality {
  quality_score?: number | null;
  quality_passed?: boolean | null;
  quarantined?: boolean;
  schema_drift?: DataSourceSchemaClassification | null;
  evaluated_at?: string | null;
  results?: DataSourceQualityResult[];
  anomalies?: string[];
}

// Response of GET .../endpoints/:endpoint_id/quality: the latest outcome plus the
// endpoint's configured expectations and whether the quality stage is enabled.
export interface DataSourceQualityResponse {
  endpoint_id: string;
  quality_checks_enabled: boolean;
  quarantine_on_failure: boolean;
  latest?: DataSourceLatestQuality | null;
  expectations: AiDataSourceExpectation[];
}

// One previewed/created endpoint from an OpenAPI import (the compact serialize
// shape OpenApiImportService returns in `created`/`preview`).
export interface DataSourceOpenApiImportPreview {
  id?: string;
  name: string;
  slug?: string;
  http_method: DataSourceHttpMethod;
  path_template: string | null;
  response_format: DataSourceResponseFormat | string | null;
  response_schema?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

// Result of an OpenAPI import. On dry_run, `created` is empty and `preview` lists
// what would be created; on confirm, `created` holds the persisted endpoints.
export interface DataSourceOpenApiImportResult {
  created: DataSourceOpenApiImportPreview[];
  preview: DataSourceOpenApiImportPreview[];
  errors: string[];
  dry_run?: boolean;
}

// Request body for the introspect (OpenAPI import) action. Supply either a
// parsed/raw spec or a URL for the server to fetch (SSRF-guarded server-side).
export interface DataSourceOpenApiImportRequest {
  spec?: Record<string, unknown>;
  url?: string;
  dry_run?: boolean;
}

// ContractService verdict for a source+endpoint fetch. A nil signal means "not
// asserted" (e.g. no schema configured / no SLA) and is not a violation.
export interface DataSourceContractVerdict {
  met: boolean;
  schema_valid: boolean | null;
  quality_passed: boolean | null;
  within_sla: boolean | null;
  violations: string[];
}

// Phase 3 — pull-based monitoring subscriptions. A subscription binds an endpoint
// to a poll cadence; the server-side Ai::DataSources::MonitorService walks due
// subscriptions, runs the governed fetch, change-detects (etag/checksum), warms
// the cache, and emits a "data_source_changed" signal on change.

// Cadence values mirror Ai::DataSourceSubscription::POLL_FREQUENCIES.
export type DataSourcePollFrequency =
  | 'manual' | '5min' | 'hourly' | 'daily' | 'weekly' | 'monthly' | 'realtime';

// Lifecycle status (Ai::DataSourceSubscription::STATUSES). "error" is set after
// repeated consecutive poll failures; the monitor keeps polling to self-heal.
export type DataSourceSubscriptionStatus = 'active' | 'paused' | 'error';

// Mirrors Ai::Tools::DataSourceTool#subscription_summary (the serialized shape
// returned by the subscribe action and the per-source subscription listing).
export interface AiDataSourceSubscription {
  id: string;
  data_source_id: string;
  endpoint_id: string;
  poll_frequency: DataSourcePollFrequency;
  status: DataSourceSubscriptionStatus;
  params: Record<string, unknown>;
  next_poll_at: string | null;
  last_polled_at: string | null;
  // Change fingerprint from the most recent successful poll.
  last_checksum: string | null;
  last_etag?: string | null;
  // Incremental-sync high-watermark (opaque cursor or timestamp token) carried
  // across polls when the endpoint has incremental sync configured. null until
  // the first incremental poll persists one. Optional so the UI degrades while
  // the backend serializer rollout is in flight.
  sync_cursor?: string | null;
  // Count of consecutive failed polls; reset to 0 on a successful poll.
  consecutive_failures: number;
  // Optional owning agent (the agent that subscribed), null for system/UI subs.
  agent_id?: string | null;
}

// Envelope returned by the per-source subscription listing. `count` mirrors the
// other nested-collection responses (endpoints#index returns { items, count }).
export interface DataSourceSubscriptionsResponse {
  items: AiDataSourceSubscription[];
  count: number;
}

// Payload accepted when creating/updating a subscription. Idempotent on the
// (source, endpoint) pair server-side: re-subscribing an endpoint updates the
// existing subscription's cadence/params rather than creating a duplicate.
export interface CreateDataSourceSubscriptionRequest {
  endpoint_id: string;
  poll_frequency?: DataSourcePollFrequency;
  params?: Record<string, unknown>;
}
