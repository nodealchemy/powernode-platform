import { BaseApiService } from './BaseApiService';
import type {
  McpServerRawResponse,
  McpToolRawResponse,
  McpServerOAuthStatus,
  McpServerOAuthConfig,
  McpServer,
  McpTool,
  McpResource,
  McpPrompt,
  McpToolExecutionResult,
  McpToolExecution,
  McpExecutionHistoryResponse,
  McpServerFilters,
  McpToolFilters,
  CreateMcpServerRequest,
  UpdateMcpServerRequest,
  ExecutionHistoryOptions
} from './types/mcp-api-types';

/**
 * API service for MCP (Model Context Protocol) operations
 */
class McpApiService extends BaseApiService {
  protected resource = 'mcp_servers';

  /**
   * Get all MCP servers with their tools
   */
  async getServers(filters?: McpServerFilters): Promise<{ servers: McpServer[]; tools: McpTool[] }> {
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
      mcp_servers: McpServerRawResponse[];
      meta: {
        total: number;
        connected_count: number;
        disconnected_count: number;
        error_count: number;
      };
    }>(url);

    // Map backend response to frontend types
    const servers: McpServer[] = response.mcp_servers.map((s) => ({
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
      mcp_server: McpServerRawResponse;
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

    const tools: McpTool[] = (s.tools || []).map((t) => ({
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
      mcp_server: McpServerRawResponse;
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
      mcp_server: McpServerRawResponse;
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
  async createServer(data: CreateMcpServerRequest): Promise<{ server: McpServer }> {
    const response = await this.post<{
      mcp_server: McpServerRawResponse;
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
  async updateServer(serverId: string, data: UpdateMcpServerRequest): Promise<{ server: McpServer }> {
    const response = await this.patch<{
      mcp_server: McpServerRawResponse;
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
  async getTools(filters?: McpToolFilters): Promise<{ tools: McpTool[] }> {
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
      mcp_tools: McpToolRawResponse[];
      mcp_server: { id: string; name: string };
    }>(url);

    const tools: McpTool[] = response.mcp_tools.map((t) => ({
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
      mcp_tool: McpToolRawResponse;
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
    parameters: Record<string, unknown>
  ): Promise<McpToolExecutionResult> {
    const response = await this.post<{
      execution: {
        id: string;
        status: string;
        result?: unknown;
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
   * Get MCP resources for a specific server
   */
  async getResources(filters?: {
    server_id?: string;
    mime_type?: string;
    search?: string;
  }): Promise<{ resources: McpResource[] }> {
    if (!filters?.server_id) {
      // Resources require a server_id
      return { resources: [] };
    }

    const queryParams = new URLSearchParams();
    if (filters?.mime_type) {
      queryParams.append('mime_type', filters.mime_type);
    }
    if (filters?.search) {
      queryParams.append('search', filters.search);
    }

    const query = queryParams.toString();
    const url = `/mcp/mcp_servers/${filters.server_id}/resources${query ? `?${query}` : ''}`;

    const response = await this.get<{
      resources: Array<{
        id: string;
        uri: string;
        name: string;
        description?: string;
        mime_type?: string;
      }>;
      mcp_server: { id: string; name: string; status: string };
    }>(url);

    return {
      resources: response.resources.map((r) => ({
        id: r.id,
        server_id: filters.server_id!,
        server_name: response.mcp_server.name,
        uri: r.uri,
        name: r.name,
        description: r.description,
        mime_type: r.mime_type
      }))
    };
  }

  /**
   * Get specific MCP resource
   */
  async getResource(serverId: string, resourceId: string): Promise<{
    resource: McpResource;
  }> {
    const response = await this.get<{
      resource: {
        id: string;
        uri: string;
        name: string;
        description?: string;
        mime_type?: string;
      };
      mcp_server: { id: string; name: string };
    }>(`/mcp/mcp_servers/${serverId}/resources/${resourceId}`);

    return {
      resource: {
        id: response.resource.id,
        server_id: serverId,
        server_name: response.mcp_server.name,
        uri: response.resource.uri,
        name: response.resource.name,
        description: response.resource.description,
        mime_type: response.resource.mime_type
      }
    };
  }

  /**
   * Read MCP resource content
   */
  async readResource(serverId: string, resourceId: string): Promise<{
    uri: string;
    content: unknown;
    mime_type?: string;
  }> {
    return this.post(`/mcp/mcp_servers/${serverId}/resources/${resourceId}/read`, {});
  }

  /**
   * Get MCP prompts for a specific server
   */
  async getPrompts(filters?: {
    server_id?: string;
    search?: string;
  }): Promise<{ prompts: McpPrompt[] }> {
    if (!filters?.server_id) {
      // Prompts require a server_id
      return { prompts: [] };
    }

    const queryParams = new URLSearchParams();
    if (filters?.search) {
      queryParams.append('search', filters.search);
    }

    const query = queryParams.toString();
    const url = `/mcp/mcp_servers/${filters.server_id}/prompts${query ? `?${query}` : ''}`;

    const response = await this.get<{
      prompts: Array<{
        id: string;
        name: string;
        description?: string;
        arguments?: Array<{
          name: string;
          description?: string;
          required?: boolean;
        }>;
      }>;
      mcp_server: { id: string; name: string; status: string };
    }>(url);

    return {
      prompts: response.prompts.map((p) => ({
        id: p.id,
        server_id: filters.server_id!,
        server_name: response.mcp_server.name,
        name: p.name,
        description: p.description,
        arguments: p.arguments
      }))
    };
  }

  /**
   * Get specific MCP prompt
   */
  async getPrompt(serverId: string, promptId: string): Promise<{ prompt: McpPrompt }> {
    const response = await this.get<{
      prompt: {
        id: string;
        name: string;
        description?: string;
        arguments?: Array<{
          name: string;
          description?: string;
          required?: boolean;
        }>;
      };
      mcp_server: { id: string; name: string };
    }>(`/mcp/mcp_servers/${serverId}/prompts/${promptId}`);

    return {
      prompt: {
        id: response.prompt.id,
        server_id: serverId,
        server_name: response.mcp_server.name,
        name: response.prompt.name,
        description: response.prompt.description,
        arguments: response.prompt.arguments
      }
    };
  }

  /**
   * Execute MCP prompt
   */
  async executePrompt(
    serverId: string,
    promptId: string,
    promptArguments: Record<string, unknown>
  ): Promise<{
    prompt_id: string;
    messages: Array<{
      role: string;
      content: string;
    }>;
  }> {
    return this.post(`/mcp/mcp_servers/${serverId}/prompts/${promptId}/execute`, {
      arguments: promptArguments
    });
  }

  /**
   * Get tool execution history
   */
  async getExecutionHistory(
    serverId: string,
    toolId: string,
    options?: ExecutionHistoryOptions
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
      tools: McpToolRawResponse[];
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
      mcp_server: McpServerRawResponse;
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

// Re-export types for convenience
export type { McpServerOAuthStatus } from './types/mcp-api-types';
