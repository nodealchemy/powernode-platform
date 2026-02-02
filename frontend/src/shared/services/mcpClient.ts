// MCP Client - TypeScript client for Model Context Protocol communication
// Replaces all legacy API services with unified MCP protocol

// =============================================================================
// MCP CLIENT TYPES
// =============================================================================

// JSON Schema type for tool schemas
export interface JsonSchema {
  type?: string;
  properties?: Record<string, JsonSchema>;
  required?: string[];
  items?: JsonSchema;
  enum?: string[];
  description?: string;
  default?: unknown;
  [key: string]: unknown;
}

// MCP Server capabilities
export interface McpServerCapabilities {
  protocolVersion?: string;
  tools?: { listChanged?: boolean };
  resources?: { subscribe?: boolean };
  prompts?: { listChanged?: boolean };
  [key: string]: unknown;
}

// MCP tool metadata
export interface McpToolMetadata {
  agent_id?: string;
  workflow_id?: string;
  provider?: string;
  category?: string;
  [key: string]: unknown;
}

export interface McpMessage {
  jsonrpc: '2.0';
  id?: string | number;
  method?: string;
  params?: Record<string, unknown>;
  result?: unknown;
  error?: McpError;
}

export interface McpError {
  code: number;
  message: string;
  data?: Record<string, unknown>;
}

export interface McpTool {
  name: string;
  description: string;
  version: string;
  capabilities: string[];
  inputSchema: JsonSchema;
  outputSchema: JsonSchema;
  metadata?: McpToolMetadata;
}

export interface McpToolInvocation {
  name: string;
  arguments: Record<string, unknown>;
}

export interface McpConnectionInfo {
  connectionId: string;
  protocolVersion: string;
  serverCapabilities: McpServerCapabilities;
  availableTools: number;
  userPermissions: string[];
}

export interface McpSubscription {
  resourceType: string;
  resourceId: string;
  filters?: Record<string, unknown>;
}

// =============================================================================
// MCP CLIENT CLASS
// =============================================================================

// Error event types for global error handling
export interface McpErrorEvent {
  code: string;
  message: string;
  recoverable: boolean;
  timestamp: Date;
  context?: Record<string, unknown>;
}

export type McpErrorHandler = (error: McpErrorEvent) => void;

// Event data type for MCP events
export interface McpEventData {
  type?: string;
  [key: string]: unknown;
}

export type McpEventHandler = (data: McpEventData) => void;

export class McpClient {
  private ws: WebSocket | null = null;
  private messageId = 0;
  private pendingRequests = new Map<string | number, {
    resolve: (value: unknown) => void;
    reject: (error: Error) => void;
    timestamp: number;
  }>();
  private subscriptions = new Map<string, McpSubscription>();
  private eventHandlers = new Map<string, McpEventHandler[]>();
  private errorHandlers: McpErrorHandler[] = [];
  private connectionInfo: McpConnectionInfo | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 1000;

  constructor() {
    this.setupRequestTimeout();
  }

  /**
   * Register a global error handler for MCP errors
   * Returns unsubscribe function
   */
  onError(handler: McpErrorHandler): () => void {
    this.errorHandlers.push(handler);
    return () => {
      const index = this.errorHandlers.indexOf(handler);
      if (index > -1) {
        this.errorHandlers.splice(index, 1);
      }
    };
  }

  /**
   * Emit error to all registered error handlers
   */
  private emitError(code: string, message: string, recoverable: boolean, context?: Record<string, unknown>): void {
    const errorEvent: McpErrorEvent = {
      code,
      message,
      recoverable,
      timestamp: new Date(),
      context
    };

    // Log in development
    if (process.env.NODE_ENV === 'development') {
      console.error('[MCP_CLIENT] Error:', errorEvent);
    }

    // Notify all error handlers
    this.errorHandlers.forEach(handler => {
      try {
        handler(errorEvent);
      } catch (handlerError) {
        // Don't let handler errors crash the client
        if (process.env.NODE_ENV === 'development') {
          console.error('[MCP_CLIENT] Error handler threw:', handlerError);
        }
      }
    });
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
        clearTimeout(connectionTimeout);
        this.emitError('CONNECTION_ERROR', 'MCP connection failed', true, { error: String(error) });
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
      protocolVersion: '2025-06-18',
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

    const response = await this.sendRequest('initialize_protocol', clientInfo) as {
      connection_id: string;
      server_capabilities: McpServerCapabilities;
      available_tools: number;
      user_permissions: string[];
    };

    this.connectionInfo = {
      connectionId: response.connection_id,
      protocolVersion: response.server_capabilities.protocolVersion || '2025-06-18',
      serverCapabilities: response.server_capabilities,
      availableTools: response.available_tools,
      userPermissions: response.user_permissions
    };

    return this.connectionInfo;
  }

  // =============================================================================
  // TOOL MANAGEMENT
  // =============================================================================

  async listTools(filters?: Record<string, unknown>): Promise<{ tools: McpTool[] }> {
    return this.sendRequest('list_tools', filters) as Promise<{ tools: McpTool[] }>;
  }

  async describeTool(toolName: string): Promise<McpTool> {
    return this.sendRequest('describe_tool', { name: toolName }) as Promise<McpTool>;
  }

  async callTool(invocation: McpToolInvocation): Promise<unknown> {
    return this.sendRequest('call_tool', {
      name: invocation.name,
      arguments: invocation.arguments
    });
  }

  // =============================================================================
  // AI AGENT OPERATIONS (MCP-ONLY)
  // =============================================================================

  async executeAgent(agentId: string, inputParameters: Record<string, unknown>, options?: Record<string, unknown>): Promise<unknown> {
    return this.sendRequest('execute_agent', {
      agent_id: agentId,
      input_parameters: inputParameters,
      execution_options: options || {}
    });
  }

  async getAgents(filters?: Record<string, unknown>): Promise<{ tools: McpTool[] }> {
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

  async executeWorkflow(workflowId: string, inputVariables?: Record<string, unknown>, options?: Record<string, unknown>): Promise<unknown> {
    return this.sendRequest('execute_workflow', {
      workflow_id: workflowId,
      input_variables: inputVariables || {},
      execution_options: options || {}
    });
  }

  async getWorkflows(filters?: Record<string, unknown>): Promise<{ tools: McpTool[] }> {
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

    const result = response as { subscribed?: boolean };
    if (result.subscribed) {
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

  on(eventType: string, handler: McpEventHandler): void {
    if (!this.eventHandlers.has(eventType)) {
      this.eventHandlers.set(eventType, []);
    }
    this.eventHandlers.get(eventType)!.push(handler);
  }

  off(eventType: string, handler: McpEventHandler): void {
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
    return this.sendRequest('ping', {}) as Promise<{ pong: boolean; timestamp: string }>;
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

  private async sendRequest(method: string, params: Record<string, unknown> = {}): Promise<unknown> {
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
      this.handleNotification(message.params as McpEventData);
    }
  }

  private handleNotification(params: McpEventData): void {
    const eventType = params.type || 'unknown';
    const handlers = this.eventHandlers.get(eventType) || [];

    handlers.forEach(handler => {
      try {
        handler(params);
      } catch {
        // Ignore event handler errors
      }
    });

    // Also emit generic events
    const allHandlers = this.eventHandlers.get('*') || [];
    allHandlers.forEach(handler => {
      try {
        handler({ type: eventType, ...params });
      } catch {
        // Ignore generic event handler errors
      }
    });
  }

  private handleDisconnection(): void {
    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);

      this.emitError(
        'CONNECTION_LOST',
        `Connection lost. Attempting to reconnect (${this.reconnectAttempts}/${this.maxReconnectAttempts})...`,
        true,
        { attempt: this.reconnectAttempts, nextRetryMs: delay }
      );

      setTimeout(() => {
        this.connect().catch(() => {
          // Reconnection failed, will retry
        });
      }, delay);
    } else {
      this.emitError(
        'CONNECTION_FAILED',
        'Unable to establish MCP connection after multiple attempts. Please refresh the page.',
        false,
        { maxAttempts: this.maxReconnectAttempts }
      );
      this.emit('connection_failed', { reason: 'max_attempts_reached' });
    }
  }

  private emit(eventType: string, data: McpEventData): void {
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
  async executeAgent(agentId: string, input: string, context?: Record<string, unknown>) {
    return mcpClient.executeAgent(agentId, { input, context });
  },

  async listAgents(filters?: Record<string, unknown>) {
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
  async executeWorkflow(workflowId: string, inputVariables?: Record<string, unknown>) {
    return mcpClient.executeWorkflow(workflowId, inputVariables);
  },

  async listWorkflows(filters?: Record<string, unknown>) {
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
  async listTools(filters?: Record<string, unknown>) {
    const result = await mcpClient.listTools(filters);
    return {
      success: true,
      data: result
    };
  },

  async callTool(toolName: string, arguments_: Record<string, unknown>) {
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

export default mcpClient;