// MCP Client - TypeScript client for Model Context Protocol communication
// Replaces all legacy API services with unified MCP protocol

// =============================================================================
// MCP CLIENT TYPES
// =============================================================================

export interface McpMessage {
  jsonrpc: '2.0';
  id?: string | number;
  method?: string;
  params?: any;
  result?: any;
  error?: McpError;
}

export interface McpError {
  code: number;
  message: string;
  data?: any;
}

export interface McpTool {
  name: string;
  description: string;
  version: string;
  capabilities: string[];
  inputSchema: any;
  outputSchema: any;
  metadata?: any;
}

export interface McpToolInvocation {
  name: string;
  arguments: Record<string, any>;
}

export interface McpConnectionInfo {
  connectionId: string;
  protocolVersion: string;
  serverCapabilities: any;
  availableTools: number;
  userPermissions: string[];
}

export interface McpSubscription {
  resourceType: string;
  resourceId: string;
  filters?: Record<string, any>;
}

// =============================================================================
// MCP CLIENT CLASS
// =============================================================================

export class McpClient {
  private ws: WebSocket | null = null;
  private messageId = 0;
  private pendingRequests = new Map<string | number, {
    resolve: (value: any) => void;
    reject: (error: any) => void;
    timestamp: number;
  }>();
  private subscriptions = new Map<string, McpSubscription>();
  private eventHandlers = new Map<string, ((data: any) => void)[]>();
  private connectionInfo: McpConnectionInfo | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 1000;

  constructor() {
    this.setupRequestTimeout();
  }

  // =============================================================================
  // CONNECTION MANAGEMENT
  // =============================================================================

  async connect(): Promise<McpConnectionInfo> {
    if (this.ws?.readyState === WebSocket.OPEN) {
      return this.connectionInfo!;
    }

    return new Promise((resolve, reject) => {
      const wsUrl = this.getWebSocketUrl();
      this.ws = new WebSocket(wsUrl);

      const connectionTimeout = setTimeout(() => {
        reject(new Error('MCP connection timeout'));
      }, 10000);

      this.ws.onopen = () => {
        clearTimeout(connectionTimeout);
        this.reconnectAttempts = 0;
        this.initializeProtocol()
          .then(resolve)
          .catch(reject);
      };

      this.ws.onmessage = (event) => {
        this.handleMessage(JSON.parse(event.data));
      };

      this.ws.onclose = (_event) => {
        this.handleDisconnection();
      };

      this.ws.onerror = (error) => {
        console.error('[MCP_CLIENT] WebSocket error:', error);
        clearTimeout(connectionTimeout);
        reject(new Error('MCP connection failed'));
      };
    });
  }

  disconnect(): void {
    if (this.ws) {
      this.ws.close(1000, 'Client disconnect');
      this.ws = null;
    }
    this.connectionInfo = null;
    this.pendingRequests.clear();
    this.subscriptions.clear();
  }

  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  // =============================================================================
  // PROTOCOL INITIALIZATION
  // =============================================================================

  private async initializeProtocol(): Promise<McpConnectionInfo> {
    const clientInfo = {
      protocolVersion: '2024-11-05',
      capabilities: {
        tools: { listChanged: true },
        resources: { subscribe: true },
        prompts: { listChanged: true }
      },
      clientInfo: {
        name: 'Powernode Frontend',
        version: '1.0.0'
      }
    };

    const response = await this.sendRequest('initialize_protocol', clientInfo);

    this.connectionInfo = {
      connectionId: response.connection_id,
      protocolVersion: response.server_capabilities.protocolVersion || '2024-11-05',
      serverCapabilities: response.server_capabilities,
      availableTools: response.available_tools,
      userPermissions: response.user_permissions
    };

    return this.connectionInfo;
  }

  // =============================================================================
  // TOOL MANAGEMENT
  // =============================================================================

  async listTools(filters?: Record<string, any>): Promise<{ tools: McpTool[] }> {
    return this.sendRequest('list_tools', filters);
  }

  async describeTool(toolName: string): Promise<McpTool> {
    return this.sendRequest('describe_tool', { name: toolName });
  }

  async callTool(invocation: McpToolInvocation): Promise<any> {
    return this.sendRequest('call_tool', {
      name: invocation.name,
      arguments: invocation.arguments
    });
  }

  // =============================================================================
  // AI AGENT OPERATIONS (MCP-ONLY)
  // =============================================================================

  async executeAgent(agentId: string, inputParameters: Record<string, any>, options?: Record<string, any>): Promise<any> {
    return this.sendRequest('execute_agent', {
      agent_id: agentId,
      input_parameters: inputParameters,
      execution_options: options || {}
    });
  }

  async getAgents(filters?: Record<string, any>): Promise<{ tools: McpTool[] }> {
    // Agents are now MCP tools, so we list tools with agent filter
    const agentFilters = { ...filters, type: 'ai_agent' };
    return this.listTools(agentFilters);
  }

  async getAgent(agentId: string): Promise<McpTool> {
    // Get agent as MCP tool
    const tools = await this.listTools({ agent_id: agentId });
    const agent = tools.tools.find(tool => tool.metadata?.agent_id === agentId);

    if (!agent) {
      throw new Error(`Agent not found: ${agentId}`);
    }

    return agent;
  }

  // =============================================================================
  // WORKFLOW OPERATIONS (MCP-ONLY)
  // =============================================================================

  async executeWorkflow(workflowId: string, inputVariables?: Record<string, any>, options?: Record<string, any>): Promise<any> {
    return this.sendRequest('execute_workflow', {
      workflow_id: workflowId,
      input_variables: inputVariables || {},
      execution_options: options || {}
    });
  }

  async getWorkflows(filters?: Record<string, any>): Promise<{ tools: McpTool[] }> {
    // Workflows are now MCP tools
    const workflowFilters = { ...filters, type: 'workflow' };
    return this.listTools(workflowFilters);
  }

  async getWorkflow(workflowId: string): Promise<McpTool> {
    const tools = await this.listTools({ workflow_id: workflowId });
    const workflow = tools.tools.find(tool => tool.metadata?.workflow_id === workflowId);

    if (!workflow) {
      throw new Error(`Workflow not found: ${workflowId}`);
    }

    return workflow;
  }

  // =============================================================================
  // RESOURCE SUBSCRIPTIONS
  // =============================================================================

  async subscribeToResource(subscription: McpSubscription): Promise<void> {
    const response = await this.sendRequest('subscribe_to_resource', {
      resource_type: subscription.resourceType,
      resource_id: subscription.resourceId,
      filters: subscription.filters
    });

    if (response.subscribed) {
      const key = `${subscription.resourceType}:${subscription.resourceId}`;
      this.subscriptions.set(key, subscription);
    }
  }

  async unsubscribeFromResource(resourceType: string, resourceId: string): Promise<void> {
    // Implementation would depend on server support for unsubscribe
    const key = `${resourceType}:${resourceId}`;
    this.subscriptions.delete(key);
  }

  // =============================================================================
  // EVENT HANDLING
  // =============================================================================

  on(eventType: string, handler: (data: any) => void): void {
    if (!this.eventHandlers.has(eventType)) {
      this.eventHandlers.set(eventType, []);
    }
    this.eventHandlers.get(eventType)!.push(handler);
  }

  off(eventType: string, handler: (data: any) => void): void {
    const handlers = this.eventHandlers.get(eventType);
    if (handlers) {
      const index = handlers.indexOf(handler);
      if (index > -1) {
        handlers.splice(index, 1);
      }
    }
  }

  // =============================================================================
  // UTILITY METHODS
  // =============================================================================

  async ping(): Promise<{ pong: boolean; timestamp: string }> {
    return this.sendRequest('ping', {});
  }

  getConnectionInfo(): McpConnectionInfo | null {
    return this.connectionInfo;
  }

  hasPermission(permission: string): boolean {
    return this.connectionInfo?.userPermissions.includes(permission) || false;
  }

  // =============================================================================
  // PRIVATE METHODS
  // =============================================================================

  private getWebSocketUrl(): string {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.host;
    return `${protocol}//${host}/cable`;
  }

  private async sendRequest(method: string, params: any = {}): Promise<any> {
    if (!this.isConnected()) {
      throw new Error('MCP client not connected');
    }

    const id = ++this.messageId;
    const message: McpMessage = {
      jsonrpc: '2.0',
      id,
      method,
      params
    };

    return new Promise((resolve, reject) => {
      this.pendingRequests.set(id, {
        resolve,
        reject,
        timestamp: Date.now()
      });

      this.ws!.send(JSON.stringify(message));

      // Timeout after 30 seconds
      setTimeout(() => {
        const pending = this.pendingRequests.get(id);
        if (pending) {
          this.pendingRequests.delete(id);
          reject(new Error(`MCP request timeout: ${method}`));
        }
      }, 30000);
    });
  }

  private handleMessage(message: McpMessage): void {
    // Handle response to request
    if (message.id && this.pendingRequests.has(message.id)) {
      const pending = this.pendingRequests.get(message.id)!;
      this.pendingRequests.delete(message.id);

      if (message.error) {
        pending.reject(new Error(`MCP Error: ${message.error.message}`));
      } else {
        pending.resolve(message.result);
      }
      return;
    }

    // Handle notification/event
    if (message.method === 'notification' && message.params) {
      this.handleNotification(message.params);
    }
  }

  private handleNotification(params: any): void {
    const eventType = params.type || 'unknown';
    const handlers = this.eventHandlers.get(eventType) || [];

    handlers.forEach(handler => {
      try {
        handler(params);
      } catch (_error) {
        // Ignore event handler errors
      }
    });

    // Also emit generic events
    const allHandlers = this.eventHandlers.get('*') || [];
    allHandlers.forEach(handler => {
      try {
        handler({ type: eventType, ...params });
      } catch (_error) {
        // Ignore generic event handler errors
      }
    });
  }

  private handleDisconnection(): void {
    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);

      setTimeout(() => {
        this.connect().catch(() => {
          // Reconnection failed, will retry
        });
      }, delay);
    } else {
      this.emit('connection_failed', { reason: 'max_attempts_reached' });
    }
  }

  private emit(eventType: string, data: any): void {
    const handlers = this.eventHandlers.get(eventType) || [];
    handlers.forEach(handler => handler(data));
  }

  private setupRequestTimeout(): void {
    // Clean up stale requests every minute
    setInterval(() => {
      const now = Date.now();
      const staleThreshold = 60000; // 1 minute

      for (const [id, request] of this.pendingRequests.entries()) {
        if (now - request.timestamp > staleThreshold) {
          this.pendingRequests.delete(id);
          request.reject(new Error('Request timeout'));
        }
      }
    }, 60000);
  }
}

// =============================================================================
// SINGLETON INSTANCE
// =============================================================================

export const mcpClient = new McpClient();

// Auto-connect when imported (with error handling)
if (typeof window !== 'undefined') {
  mcpClient.connect().catch(() => {
    // Auto-connect failed, will retry
  });
}

// =============================================================================
// CONVENIENCE FUNCTIONS
// =============================================================================

export const mcpApi = {
  // Agent operations
  async executeAgent(agentId: string, input: string, context?: Record<string, any>) {
    return mcpClient.executeAgent(agentId, { input, context });
  },

  async listAgents(filters?: Record<string, any>) {
    const result = await mcpClient.getAgents(filters);
    return {
      success: true,
      data: { agents: result.tools }
    };
  },

  async getAgent(agentId: string) {
    const agent = await mcpClient.getAgent(agentId);
    return {
      success: true,
      data: agent
    };
  },

  // Workflow operations
  async executeWorkflow(workflowId: string, inputVariables?: Record<string, any>) {
    return mcpClient.executeWorkflow(workflowId, inputVariables);
  },

  async listWorkflows(filters?: Record<string, any>) {
    const result = await mcpClient.getWorkflows(filters);
    return {
      success: true,
      data: { workflows: result.tools }
    };
  },

  async getWorkflow(workflowId: string) {
    const workflow = await mcpClient.getWorkflow(workflowId);
    return {
      success: true,
      data: workflow
    };
  },

  // Tool operations
  async listTools(filters?: Record<string, any>) {
    const result = await mcpClient.listTools(filters);
    return {
      success: true,
      data: result
    };
  },

  async callTool(toolName: string, arguments_: Record<string, any>) {
    return mcpClient.callTool({ name: toolName, arguments: arguments_ });
  },

  // Connection info
  getConnectionInfo() {
    return mcpClient.getConnectionInfo();
  },

  isConnected() {
    return mcpClient.isConnected();
  }
};

// =============================================================================
// LEGACY API COMPATIBILITY LAYER (DEPRECATED)
// =============================================================================

// These functions provide temporary compatibility with existing code
// They will be removed once all components are updated to use MCP directly

export const legacyCompatApi = {
  async get(url: string) {
    if (process.env.NODE_ENV === 'development') {
      console.warn('[MCP_CLIENT] DEPRECATED: Using legacy API compatibility layer for GET', url);
    }

    // Map legacy URLs to MCP operations
    if (url.includes('/ai/agents')) {
      return mcpApi.listAgents();
    } else if (url.includes('/ai/workflows')) {
      return mcpApi.listWorkflows();
    } else {
      throw new Error(`Legacy API call not supported via MCP: ${url}`);
    }
  },

  async post(url: string, data: any) {
    if (process.env.NODE_ENV === 'development') {
      console.warn('[MCP_CLIENT] DEPRECATED: Using legacy API compatibility layer for POST', url);
    }

    if (url.includes('/ai/agents') && url.includes('/execute')) {
      const agentId = url.match(/\/ai\/agents\/([^/]+)/)?.[1];
      if (agentId) {
        return mcpApi.executeAgent(agentId, data.input_parameters?.input || '', data.input_parameters?.context);
      }
    } else if (url.includes('/ai/workflows') && url.includes('/execute')) {
      const workflowId = url.match(/\/ai\/workflows\/([^/]+)/)?.[1];
      if (workflowId) {
        return mcpApi.executeWorkflow(workflowId, data.input_variables);
      }
    }

    throw new Error(`Legacy API call not supported via MCP: ${url}`);
  }
};

export default mcpClient;