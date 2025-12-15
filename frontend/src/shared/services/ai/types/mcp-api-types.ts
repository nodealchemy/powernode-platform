// MCP (Model Context Protocol) API Types

// JSON Schema type for tool input schemas
export interface JsonSchema {
  type?: string;
  properties?: Record<string, JsonSchema>;
  required?: string[];
  items?: JsonSchema;
  description?: string;
  default?: unknown;
  enum?: unknown[];
  [key: string]: unknown;
}

// Prompt argument type
export interface McpPromptArgument {
  name: string;
  description?: string;
  required?: boolean;
  type?: string;
  default?: unknown;
}

// Raw backend response types for MCP servers
export interface McpServerRawResponse {
  id: string;
  name: string;
  description?: string;
  status: 'connected' | 'disconnected' | 'connecting' | 'error';
  connection_type: 'stdio' | 'sse' | 'websocket' | 'http';
  auth_type?: 'none' | 'api_key' | 'oauth2';
  tools_count?: number;
  last_connected_at?: string;
  last_error?: string;
  config?: {
    version?: string;
    protocol_version?: string;
    capabilities?: {
      tools?: boolean;
      resources?: boolean;
      prompts?: boolean;
      logging?: boolean;
    };
    resources_count?: number;
    prompts_count?: number;
    metadata?: {
      author?: string;
      url?: string;
      icon?: string;
    };
  };
  tools?: McpToolRawResponse[];
  oauth_status?: McpServerOAuthStatus;
}

export interface McpToolRawResponse {
  id: string;
  name: string;
  description?: string;
  input_schema?: JsonSchema;
  category?: string;
  tags?: string[];
}

export interface McpServerOAuthStatus {
  auth_type: 'none' | 'api_key' | 'oauth2';
  oauth_configured: boolean;
  oauth_connected: boolean;
  oauth_token_expires_at?: string;
  oauth_token_expired?: boolean;
  oauth_last_refreshed_at?: string;
  oauth_error?: string;
  oauth_provider?: string;
  oauth_scopes?: string;
}

export interface McpServerOAuthConfig {
  auth_type: 'none' | 'api_key' | 'oauth2';
  oauth_provider?: string;
  oauth_client_id?: string;
  oauth_client_secret?: string;
  oauth_authorization_url?: string;
  oauth_token_url?: string;
  oauth_scopes?: string;
}

export interface McpServer {
  id: string;
  name: string;
  description?: string;
  version: string;
  protocol_version: string;
  status: 'connected' | 'disconnected' | 'connecting' | 'error';
  connection_type: 'stdio' | 'sse' | 'websocket' | 'http';
  auth_type?: 'none' | 'api_key' | 'oauth2';
  capabilities: {
    tools?: boolean;
    resources?: boolean;
    prompts?: boolean;
    logging?: boolean;
  };
  tools_count: number;
  resources_count: number;
  prompts_count: number;
  last_connected_at?: string;
  error_message?: string;
  metadata?: {
    author?: string;
    url?: string;
    icon?: string;
  };
  oauth_status?: McpServerOAuthStatus;
}

export interface McpTool {
  id: string;
  server_id: string;
  server_name: string;
  name: string;
  description?: string;
  input_schema: JsonSchema;
  category?: string;
  tags?: string[];
}

export interface McpResource {
  id: string;
  server_id: string;
  server_name: string;
  uri: string;
  name: string;
  description?: string;
  mime_type?: string;
}

export interface McpPrompt {
  id: string;
  server_id: string;
  server_name: string;
  name: string;
  description?: string;
  arguments?: McpPromptArgument[];
}

export interface McpToolExecutionResult {
  success: boolean;
  result?: unknown;
  error?: string;
  execution_time_ms: number;
  tool_id: string;
  tool_name: string;
}

export interface McpToolExecution {
  id: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  user_id: string;
  user_name?: string;
  parameters?: Record<string, unknown>;
  result?: Record<string, unknown>;
  error_message?: string;
  duration_ms?: number;
  created_at: string;
  started_at?: string;
  completed_at?: string;
}

export interface McpExecutionHistoryResponse {
  executions: McpToolExecution[];
  mcp_tool: { id: string; name: string };
  mcp_server: { id: string; name: string };
  pagination: {
    current_page: number;
    per_page: number;
    total_pages: number;
    total_count: number;
  };
  meta: {
    pending_count: number;
    running_count: number;
    success_count: number;
    failed_count: number;
    cancelled_count: number;
  };
}

// ===== Filter Types =====

export interface McpServerFilters {
  status?: 'connected' | 'disconnected' | 'error';
  connection_type?: 'stdio' | 'sse' | 'websocket';
}

export interface McpToolFilters {
  server_id?: string;
  category?: string;
  search?: string;
}

export interface McpResourceFilters {
  server_id?: string;
  mime_type?: string;
  search?: string;
}

export interface McpPromptFilters {
  server_id?: string;
  search?: string;
}

// ===== Request Types =====

export interface CreateMcpServerRequest {
  name: string;
  description?: string;
  connection_type: 'stdio' | 'websocket' | 'http';
  command?: string;
  args?: string[];
  env?: Record<string, string>;
}

export interface UpdateMcpServerRequest {
  name?: string;
  description?: string;
  connection_type?: 'stdio' | 'websocket' | 'http';
  command?: string;
  args?: string[];
  env?: Record<string, string>;
}

export interface ExecutionHistoryOptions {
  status?: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  since?: string;
  page?: number;
  per_page?: number;
}

// ===== Response Types =====

export interface McpServerResponse {
  server: McpServer;
}

export interface McpServersResponse {
  servers: McpServer[];
  tools: McpTool[];
}

export interface McpServerDetailResponse {
  server: McpServer;
  tools: McpTool[];
  resources: McpResource[];
  prompts: McpPrompt[];
}

export interface McpToolsResponse {
  tools: McpTool[];
}

export interface McpToolResponse {
  tool: McpTool;
}

export interface McpResourcesResponse {
  resources: McpResource[];
}

export interface McpPromptsResponse {
  prompts: McpPrompt[];
}

export interface McpConnectionTestResult {
  success: boolean;
  latency_ms: number;
  protocol_version: string;
  error?: string;
}

export interface McpCapabilitiesRefreshResult {
  server: McpServer;
  capabilities_updated: boolean;
}

export interface McpToolStatistics {
  mcp_tool_id: string;
  stats: {
    total_executions: number;
    success_count: number;
    failure_count: number;
    pending_count: number;
    running_count: number;
    success_rate: number;
    average_duration_ms: number;
    recent_30_days: number;
    last_execution_at?: string;
    first_execution_at?: string;
  };
}

// ===== OAuth Types =====

export interface McpOAuthInitiateResponse {
  authorization_url: string;
  state: string;
}

export interface McpOAuthCallbackParams {
  code: string;
  state: string;
  redirect_uri?: string;
}

export interface McpOAuthCallbackResponse {
  mcp_server_id: string;
  mcp_server_name: string;
  oauth_connected: boolean;
  token_expires_at?: string;
}

export interface McpOAuthDisconnectResponse {
  oauth_connected: boolean;
}

export interface McpOAuthRefreshResponse {
  oauth_connected: boolean;
  token_expires_at?: string;
}
