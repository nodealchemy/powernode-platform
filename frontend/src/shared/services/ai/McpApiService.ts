import { BaseApiService } from './BaseApiService';

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
  input_schema: any;
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
  arguments?: any[];
}

export interface McpToolExecutionResult {
  success: boolean;
  result?: any;
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
  parameters?: Record<string, any>;
  result?: Record<string, any>;
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

/**
 * API service for MCP (Model Context Protocol) operations
 */
class McpApiService extends BaseApiService {
  protected resource = 'mcp_servers';

  /**
   * Get all MCP servers with their tools
   */
  async getServers(filters?: {
    status?: 'connected' | 'disconnected' | 'error';
    connection_type?: 'stdio' | 'sse' | 'websocket';
  }): Promise<{ servers: McpServer[]; tools: McpTool[] }> {
    const queryParams = new URLSearchParams();

    if (filters?.status) {
      queryParams.append('status', filters.status);
    }
    if (filters?.connection_type) {
      queryParams.append('connection_type', filters.connection_type);
    }

    const query = queryParams.toString();
    const url = `/mcp_servers${query ? `?${query}` : ''}`;

    // Fetch servers
    const response = await this.get<{
      mcp_servers: any[];
      meta: {
        total: number;
        connected_count: number;
        disconnected_count: number;
        error_count: number;
      };
    }>(url);

    // Map backend response to frontend types
    const servers: McpServer[] = response.mcp_servers.map((s: any) => ({
      id: s.id,
      name: s.name,
      description: s.description,
      version: s.config?.version || '1.0.0',
      protocol_version: s.config?.protocol_version || '2025-06-18',
      status: s.status,
      connection_type: s.connection_type,
      capabilities: s.config?.capabilities || {
        tools: true,
        resources: false,
        prompts: false,
        logging: true
      },
      tools_count: s.tools_count || 0,
      resources_count: s.config?.resources_count || 0,
      prompts_count: s.config?.prompts_count || 0,
      last_connected_at: s.last_connected_at,
      error_message: s.last_error,
      metadata: s.config?.metadata
    }));

    // Collect all tools from servers that include them
    const tools: McpTool[] = [];
    for (const s of response.mcp_servers) {
      if (s.tools && Array.isArray(s.tools)) {
        for (const t of s.tools) {
          tools.push({
            id: t.id,
            server_id: s.id,
            server_name: s.name,
            name: t.name,
            description: t.description,
            input_schema: t.input_schema || {},
            category: t.category,
            tags: t.tags
          });
        }
      }
    }

    return { servers, tools };
  }

  /**
   * Get specific MCP server with tools
   */
  async getServer(serverId: string): Promise<{
    server: McpServer;
    tools: McpTool[];
    resources: McpResource[];
    prompts: McpPrompt[];
  }> {
    const response = await this.get<{
      mcp_server: any;
    }>(`/mcp_servers/${serverId}`);

    const s = response.mcp_server;
    const server: McpServer = {
      id: s.id,
      name: s.name,
      description: s.description,
      version: s.config?.version || '1.0.0',
      protocol_version: s.config?.protocol_version || '2025-06-18',
      status: s.status,
      connection_type: s.connection_type,
      capabilities: s.config?.capabilities || {
        tools: true,
        resources: false,
        prompts: false,
        logging: true
      },
      tools_count: s.tools_count || 0,
      resources_count: s.config?.resources_count || 0,
      prompts_count: s.config?.prompts_count || 0,
      last_connected_at: s.last_connected_at,
      error_message: s.last_error,
      metadata: s.config?.metadata
    };

    const tools: McpTool[] = (s.tools || []).map((t: any) => ({
      id: t.id,
      server_id: s.id,
      server_name: s.name,
      name: t.name,
      description: t.description,
      input_schema: t.input_schema || {},
      category: t.category,
      tags: t.tags
    }));

    return { server, tools, resources: [], prompts: [] };
  }

  /**
   * Connect to MCP server
   */
  async connectServer(serverId: string): Promise<{ server: McpServer }> {
    const response = await this.post<{
      mcp_server: any;
      message: string;
    }>(`/mcp_servers/${serverId}/connect`, {});

    const s = response.mcp_server;
    return {
      server: {
        id: s.id,
        name: s.name,
        description: s.description,
        version: s.config?.version || '1.0.0',
        protocol_version: s.config?.protocol_version || '2025-06-18',
        status: s.status,
        connection_type: s.connection_type,
        capabilities: s.config?.capabilities || { tools: true },
        tools_count: s.tools_count || 0,
        resources_count: s.config?.resources_count || 0,
        prompts_count: s.config?.prompts_count || 0,
        last_connected_at: s.last_connected_at,
        error_message: s.last_error,
        metadata: s.config?.metadata
      }
    };
  }

  /**
   * Disconnect from MCP server
   */
  async disconnectServer(serverId: string): Promise<{ server: McpServer }> {
    const response = await this.post<{
      mcp_server: any;
      message: string;
    }>(`/mcp_servers/${serverId}/disconnect`, {});

    const s = response.mcp_server;
    return {
      server: {
        id: s.id,
        name: s.name,
        description: s.description,
        version: s.config?.version || '1.0.0',
        protocol_version: s.config?.protocol_version || '2025-06-18',
        status: s.status,
        connection_type: s.connection_type,
        capabilities: s.config?.capabilities || { tools: true },
        tools_count: s.tools_count || 0,
        resources_count: s.config?.resources_count || 0,
        prompts_count: s.config?.prompts_count || 0,
        last_connected_at: s.last_connected_at,
        error_message: s.last_error,
        metadata: s.config?.metadata
      }
    };
  }

  /**
   * Reconnect to MCP server (disconnect then connect)
   */
  async reconnectServer(serverId: string): Promise<{ server: McpServer }> {
    await this.disconnectServer(serverId);
    return this.connectServer(serverId);
  }

  /**
   * Create a new MCP server
   */
  async createServer(data: {
    name: string;
    description?: string;
    connection_type: 'stdio' | 'websocket' | 'http';
    command?: string;
    args?: string[];
    env?: Record<string, string>;
  }): Promise<{ server: McpServer }> {
    const response = await this.post<{
      mcp_server: any;
    }>('/mcp_servers', { mcp_server: data });

    const s = response.mcp_server;
    return {
      server: {
        id: s.id,
        name: s.name,
        description: s.description,
        version: s.config?.version || '1.0.0',
        protocol_version: s.config?.protocol_version || '2025-06-18',
        status: s.status,
        connection_type: s.connection_type,
        capabilities: s.config?.capabilities || { tools: true },
        tools_count: s.tools_count || 0,
        resources_count: s.config?.resources_count || 0,
        prompts_count: s.config?.prompts_count || 0,
        last_connected_at: s.last_connected_at,
        error_message: s.last_error,
        metadata: s.config?.metadata
      }
    };
  }

  /**
   * Update an MCP server
   */
  async updateServer(serverId: string, data: {
    name?: string;
    description?: string;
    connection_type?: 'stdio' | 'websocket' | 'http';
    command?: string;
    args?: string[];
    env?: Record<string, string>;
  }): Promise<{ server: McpServer }> {
    const response = await this.patch<{
      mcp_server: any;
    }>(`/mcp_servers/${serverId}`, { mcp_server: data });

    const s = response.mcp_server;
    return {
      server: {
        id: s.id,
        name: s.name,
        description: s.description,
        version: s.config?.version || '1.0.0',
        protocol_version: s.config?.protocol_version || '2025-06-18',
        status: s.status,
        connection_type: s.connection_type,
        capabilities: s.config?.capabilities || { tools: true },
        tools_count: s.tools_count || 0,
        resources_count: s.config?.resources_count || 0,
        prompts_count: s.config?.prompts_count || 0,
        last_connected_at: s.last_connected_at,
        error_message: s.last_error,
        metadata: s.config?.metadata
      }
    };
  }

  /**
   * Delete an MCP server
   */
  async deleteServer(serverId: string): Promise<void> {
    await this.delete(`/mcp_servers/${serverId}`);
  }

  /**
   * Get MCP tools for a specific server
   */
  async getTools(filters?: {
    server_id?: string;
    category?: string;
    search?: string;
  }): Promise<{ tools: McpTool[] }> {
    if (!filters?.server_id) {
      // If no server_id, fetch all servers and collect tools
      const { tools } = await this.getServers();
      return { tools };
    }

    const queryParams = new URLSearchParams();
    if (filters?.category) {
      queryParams.append('category', filters.category);
    }
    if (filters?.search) {
      queryParams.append('search', filters.search);
    }

    const query = queryParams.toString();
    const url = `/mcp_servers/${filters.server_id}/mcp_tools${query ? `?${query}` : ''}`;

    const response = await this.get<{
      mcp_tools: any[];
      mcp_server: { id: string; name: string };
    }>(url);

    const tools: McpTool[] = response.mcp_tools.map((t: any) => ({
      id: t.id,
      server_id: response.mcp_server.id,
      server_name: response.mcp_server.name,
      name: t.name,
      description: t.description,
      input_schema: t.input_schema || {},
      category: t.category,
      tags: t.tags
    }));

    return { tools };
  }

  /**
   * Get specific MCP tool
   */
  async getTool(serverId: string, toolId: string): Promise<{ tool: McpTool }> {
    const response = await this.get<{
      mcp_tool: any;
      mcp_server: { id: string; name: string };
    }>(`/mcp_servers/${serverId}/mcp_tools/${toolId}`);

    return {
      tool: {
        id: response.mcp_tool.id,
        server_id: response.mcp_server.id,
        server_name: response.mcp_server.name,
        name: response.mcp_tool.name,
        description: response.mcp_tool.description,
        input_schema: response.mcp_tool.input_schema || {},
        category: response.mcp_tool.category,
        tags: response.mcp_tool.tags
      }
    };
  }

  /**
   * Execute MCP tool
   */
  async executeTool(
    serverId: string,
    toolId: string,
    parameters: Record<string, any>
  ): Promise<McpToolExecutionResult> {
    const response = await this.post<{
      execution: {
        id: string;
        status: string;
        result?: any;
        error_message?: string;
        duration_ms?: number;
      };
      mcp_tool: { id: string; name: string };
    }>(`/mcp_servers/${serverId}/mcp_tools/${toolId}/execute`, {
      parameters
    });

    return {
      success: response.execution.status === 'completed',
      result: response.execution.result,
      error: response.execution.error_message,
      execution_time_ms: response.execution.duration_ms || 0,
      tool_id: response.mcp_tool.id,
      tool_name: response.mcp_tool.name
    };
  }

  /**
   * Get MCP resources (placeholder - backend endpoint not yet implemented)
   */
  async getResources(_filters?: {
    server_id?: string;
    mime_type?: string;
    search?: string;
  }): Promise<{ resources: McpResource[] }> {
    // Resources endpoint not yet implemented in backend
    return { resources: [] };
  }

  /**
   * Get specific MCP resource (placeholder)
   */
  async getResource(_resourceId: string): Promise<{
    resource: McpResource;
    content: any;
  }> {
    throw new Error('Resources endpoint not yet implemented');
  }

  /**
   * Read MCP resource content (placeholder)
   */
  async readResource(_uri: string): Promise<{
    uri: string;
    content: any;
    mime_type?: string;
  }> {
    throw new Error('Resources endpoint not yet implemented');
  }

  /**
   * Get MCP prompts (placeholder - backend endpoint not yet implemented)
   */
  async getPrompts(_filters?: {
    server_id?: string;
    search?: string;
  }): Promise<{ prompts: McpPrompt[] }> {
    // Prompts endpoint not yet implemented in backend
    return { prompts: [] };
  }

  /**
   * Get specific MCP prompt (placeholder)
   */
  async getPrompt(_promptId: string): Promise<{ prompt: McpPrompt }> {
    throw new Error('Prompts endpoint not yet implemented');
  }

  /**
   * Execute MCP prompt (placeholder)
   */
  async executePrompt(
    _promptId: string,
    _arguments: Record<string, any>
  ): Promise<{
    prompt_id: string;
    messages: Array<{
      role: string;
      content: string;
    }>;
  }> {
    throw new Error('Prompts endpoint not yet implemented');
  }

  /**
   * Get tool execution history
   */
  async getExecutionHistory(
    serverId: string,
    toolId: string,
    options?: {
      status?: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
      since?: string;
      page?: number;
      per_page?: number;
    }
  ): Promise<McpExecutionHistoryResponse> {
    const queryParams = new URLSearchParams();
    if (options?.status) queryParams.append('status', options.status);
    if (options?.since) queryParams.append('since', options.since);
    if (options?.page) queryParams.append('page', options.page.toString());
    if (options?.per_page) queryParams.append('per_page', options.per_page.toString());

    const query = queryParams.toString();
    const url = `/mcp_servers/${serverId}/mcp_tools/${toolId}/executions${query ? `?${query}` : ''}`;

    return this.get<McpExecutionHistoryResponse>(url);
  }

  /**
   * Get single execution details
   */
  async getExecution(
    serverId: string,
    toolId: string,
    executionId: string
  ): Promise<{
    execution: McpToolExecution;
    mcp_tool: { id: string; name: string; description?: string };
    mcp_server: { id: string; name: string; status: string };
  }> {
    return this.get(`/mcp_servers/${serverId}/mcp_tools/${toolId}/executions/${executionId}`);
  }

  /**
   * Cancel a running or pending execution
   */
  async cancelExecution(
    serverId: string,
    toolId: string,
    executionId: string
  ): Promise<{
    execution: McpToolExecution;
    message: string;
  }> {
    return this.post(`/mcp_servers/${serverId}/mcp_tools/${toolId}/executions/${executionId}/cancel`, {});
  }

  /**
   * Get MCP tool statistics
   */
  async getToolStatistics(serverId: string, toolId: string): Promise<{
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
  }> {
    return this.get<{
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
    }>(`/mcp_servers/${serverId}/mcp_tools/${toolId}/stats`);
  }

  /**
   * Test MCP server connection (health check)
   */
  async testServerConnection(serverId: string): Promise<{
    success: boolean;
    latency_ms: number;
    protocol_version: string;
    error?: string;
  }> {
    const response = await this.post<{
      mcp_server_id: string;
      healthy: boolean;
      status: string;
      last_connected_at?: string;
      last_error?: string;
      checked_at: string;
    }>(`/mcp_servers/${serverId}/health_check`, {});

    return {
      success: response.healthy,
      latency_ms: 0, // Health check doesn't return latency
      protocol_version: '2025-06-18',
      error: response.last_error
    };
  }

  /**
   * Refresh MCP server capabilities (discover tools)
   */
  async refreshServerCapabilities(serverId: string): Promise<{
    server: McpServer;
    capabilities_updated: boolean;
  }> {
    const response = await this.post<{
      mcp_server_id: string;
      tools_discovered: number;
      tools: any[];
      message: string;
    }>(`/mcp_servers/${serverId}/discover_tools`, {});

    // Fetch updated server data
    const { server } = await this.getServer(serverId);

    return {
      server,
      capabilities_updated: response.tools_discovered > 0
    };
  }

  // ==========================================
  // OAuth 2.1 Methods
  // ==========================================

  /**
   * Get OAuth status for an MCP server
   */
  async getOAuthStatus(serverId: string): Promise<McpServerOAuthStatus> {
    const response = await this.get<{
      mcp_server_id: string;
      mcp_server_name: string;
      oauth_status: McpServerOAuthStatus;
    }>(`/mcp_servers/${serverId}/oauth/status`);

    return response.oauth_status;
  }

  /**
   * Initiate OAuth authorization flow
   * Returns the authorization URL to redirect the user to
   */
  async initiateOAuth(serverId: string, redirectUri?: string): Promise<{
    authorization_url: string;
    state: string;
  }> {
    const response = await this.post<{
      authorization_url: string;
      state: string;
      message: string;
    }>(`/mcp_servers/${serverId}/oauth`, {
      redirect_uri: redirectUri || `${window.location.origin}/oauth/mcp/callback`
    });

    return {
      authorization_url: response.authorization_url,
      state: response.state
    };
  }

  /**
   * Complete OAuth flow with authorization code (callback handler)
   */
  async completeOAuthCallback(params: {
    code: string;
    state: string;
    redirect_uri?: string;
  }): Promise<{
    mcp_server_id: string;
    mcp_server_name: string;
    oauth_connected: boolean;
    token_expires_at?: string;
  }> {
    const response = await this.get<{
      mcp_server_id: string;
      mcp_server_name: string;
      oauth_connected: boolean;
      token_expires_at?: string;
      message: string;
    }>(`/mcp/oauth/callback?code=${encodeURIComponent(params.code)}&state=${encodeURIComponent(params.state)}${params.redirect_uri ? `&redirect_uri=${encodeURIComponent(params.redirect_uri)}` : ''}`);

    return {
      mcp_server_id: response.mcp_server_id,
      mcp_server_name: response.mcp_server_name,
      oauth_connected: response.oauth_connected,
      token_expires_at: response.token_expires_at
    };
  }

  /**
   * Disconnect OAuth (revoke tokens)
   */
  async disconnectOAuth(serverId: string): Promise<{
    oauth_connected: boolean;
  }> {
    const response = await this.delete<{
      mcp_server_id: string;
      oauth_connected: boolean;
      message: string;
    }>(`/mcp_servers/${serverId}/oauth/disconnect`);

    return {
      oauth_connected: response.oauth_connected
    };
  }

  /**
   * Manually refresh OAuth token
   */
  async refreshOAuthToken(serverId: string): Promise<{
    oauth_connected: boolean;
    token_expires_at?: string;
  }> {
    const response = await this.post<{
      mcp_server_id: string;
      oauth_connected: boolean;
      token_expires_at?: string;
      message: string;
    }>(`/mcp_servers/${serverId}/oauth/refresh`, {});

    return {
      oauth_connected: response.oauth_connected,
      token_expires_at: response.token_expires_at
    };
  }

  /**
   * Update MCP server OAuth configuration
   */
  async updateServerOAuthConfig(
    serverId: string,
    config: McpServerOAuthConfig
  ): Promise<{ server: McpServer }> {
    const response = await this.patch<{
      mcp_server: any;
    }>(`/mcp_servers/${serverId}`, {
      mcp_server: {
        auth_type: config.auth_type,
        oauth_provider: config.oauth_provider,
        oauth_client_id: config.oauth_client_id,
        oauth_client_secret: config.oauth_client_secret,
        oauth_authorization_url: config.oauth_authorization_url,
        oauth_token_url: config.oauth_token_url,
        oauth_scopes: config.oauth_scopes
      }
    });

    const s = response.mcp_server;
    return {
      server: {
        id: s.id,
        name: s.name,
        description: s.description,
        version: s.config?.version || '1.0.0',
        protocol_version: s.config?.protocol_version || '2025-06-18',
        status: s.status,
        connection_type: s.connection_type,
        auth_type: s.auth_type,
        capabilities: s.config?.capabilities || { tools: true },
        tools_count: s.tools_count || 0,
        resources_count: s.config?.resources_count || 0,
        prompts_count: s.config?.prompts_count || 0,
        last_connected_at: s.last_connected_at,
        error_message: s.last_error,
        metadata: s.config?.metadata
      }
    };
  }
}

export const mcpApi = new McpApiService();
