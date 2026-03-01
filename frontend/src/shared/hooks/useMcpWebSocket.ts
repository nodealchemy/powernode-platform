import { useCallback, useRef, useEffect, useState } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

// JSON-RPC 2.0 message types
interface JsonRpcRequest {
  jsonrpc: '2.0';
  method: string;
  params?: Record<string, unknown>;
  id: string | number;
}

interface JsonRpcResponse {
  jsonrpc: '2.0';
  result?: unknown;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
  id: string | number;
}

interface JsonRpcNotification {
  jsonrpc: '2.0';
  method: string;
  params?: Record<string, unknown>;
}

// MCP-specific types
interface McpTool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  outputSchema?: Record<string, unknown>;
}

interface McpWorkflowExecution {
  workflow_id: string;
  run_id: string;
  status: 'initializing' | 'running' | 'completed' | 'failed';
}

interface McpAgentExecution {
  agent_id: string;
  execution_id: string;
  status: 'initializing' | 'running' | 'completed' | 'failed';
}

interface McpToolExecution {
  execution_id: string;
  tool_id: string;
  tool_name: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  result?: unknown;
  error?: string;
  duration_ms?: number;
  timestamp: string;
}

interface McpWebSocketOptions {
  onToolsUpdated?: (tools: McpTool[]) => void;
  onWorkflowUpdate?: (execution: McpWorkflowExecution) => void;
  onAgentUpdate?: (execution: McpAgentExecution) => void;
  onToolExecutionUpdate?: (execution: McpToolExecution) => void;
  onNotification?: (notification: JsonRpcNotification) => void;
  onError?: (error: string) => void;
  requestTimeout?: number; // Default: 30000ms
}

interface PendingRequest {
  resolve: (result: unknown) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
}

export const useMcpWebSocket = ({
  onToolsUpdated,
  onWorkflowUpdate,
  onAgentUpdate,
  onToolExecutionUpdate,
  onNotification,
  onError,
  requestTimeout = 30000
}: McpWebSocketOptions) => {
  const { isConnected, subscribe, sendMessage, error: connectionError } = useWebSocket();
  const unsubscribeRef = useRef<(() => void) | null>(null);
  const requestIdCounter = useRef(0);
  const pendingRequests = useRef<Map<string | number, PendingRequest>>(new Map());
  const [protocolInitialized, setProtocolInitialized] = useState(false);

  // Store latest callback refs
  const onToolsUpdatedRef = useRef(onToolsUpdated);
  const onWorkflowUpdateRef = useRef(onWorkflowUpdate);
  const onAgentUpdateRef = useRef(onAgentUpdate);
  const onToolExecutionUpdateRef = useRef(onToolExecutionUpdate);
  const onNotificationRef = useRef(onNotification);
  const onErrorRef = useRef(onError);

  onToolsUpdatedRef.current = onToolsUpdated;
  onWorkflowUpdateRef.current = onWorkflowUpdate;
  onAgentUpdateRef.current = onAgentUpdate;
  onToolExecutionUpdateRef.current = onToolExecutionUpdate;
  onNotificationRef.current = onNotification;
  onErrorRef.current = onError;

  // Generate unique request ID
  const generateRequestId = useCallback((): string => {
    return `mcp_${Date.now()}_${++requestIdCounter.current}`;
  }, []);

  // Type guard for WebSocket message data
  const isWebSocketMessage = (data: unknown): data is { type: string; data?: unknown; message?: string } => {
    return typeof data === 'object' && data !== null && 'type' in data;
  };

  // Type guard for JSON-RPC response
  const isJsonRpcResponse = (data: unknown): data is JsonRpcResponse => {
    return typeof data === 'object' && data !== null && 'jsonrpc' in data && data.jsonrpc === '2.0' && 'id' in data;
  };

  // Type guard for JSON-RPC notification
  const isJsonRpcNotification = (data: unknown): data is JsonRpcNotification => {
    return typeof data === 'object' && data !== null && 'jsonrpc' in data && data.jsonrpc === '2.0' && 'method' in data && !('id' in data);
  };

  // Send JSON-RPC request and wait for response
  const sendJsonRpcRequest = useCallback((method: string, params?: Record<string, unknown>): Promise<unknown> => {
    return new Promise((resolve, reject) => {
      if (!isConnected) {
        reject(new Error('WebSocket not connected'));
        return;
      }

      const requestId = generateRequestId();
      const request: JsonRpcRequest = {
        jsonrpc: '2.0',
        method,
        params,
        id: requestId
      };

      // Set up timeout
      const timeout = setTimeout(() => {
        pendingRequests.current.delete(requestId);
        reject(new Error(`Request timeout after ${requestTimeout}ms`));
      }, requestTimeout);

      // Store pending request
      pendingRequests.current.set(requestId, { resolve, reject, timeout });

      // Send via WebSocket
      sendMessage('McpChannel', 'json_rpc_request', request as unknown as Record<string, unknown>)
        .catch((error) => {
          clearTimeout(timeout);
          pendingRequests.current.delete(requestId);
          reject(error);
        });
    });
  }, [isConnected, sendMessage, generateRequestId, requestTimeout]);

  // Handle incoming messages
  const handleMessage = useCallback((data: unknown) => {
    if (!isWebSocketMessage(data)) return;

    // Handle JSON-RPC responses
    if (data.type === 'json_rpc_response' && data.data) {
      const response = data.data;

      if (isJsonRpcResponse(response)) {
        const pending = pendingRequests.current.get(response.id);
        if (pending) {
          clearTimeout(pending.timeout);
          pendingRequests.current.delete(response.id);

          if (response.error) {
            pending.reject(new Error(response.error.message));
          } else {
            pending.resolve(response.result);
          }
        }
      }
    }

    // Handle JSON-RPC notifications
    if (data.type === 'json_rpc_notification' && data.data) {
      const notification = data.data;

      if (isJsonRpcNotification(notification)) {
        // Route notifications to appropriate handlers
        switch (notification.method) {
          case 'tools/list_changed':
            if (notification.params && 'tools' in notification.params) {
              onToolsUpdatedRef.current?.(notification.params.tools as McpTool[]);
            }
            break;
          case 'workflow/status_changed':
            if (notification.params) {
              onWorkflowUpdateRef.current?.(notification.params as unknown as McpWorkflowExecution);
            }
            break;
          case 'agent/status_changed':
            if (notification.params) {
              onAgentUpdateRef.current?.(notification.params as unknown as McpAgentExecution);
            }
            break;
          case 'tool_execution/status_changed':
            if (notification.params) {
              onToolExecutionUpdateRef.current?.(notification.params as unknown as McpToolExecution);
            }
            break;
          default:
            onNotificationRef.current?.(notification);
        }
      }
    }

    // Handle errors
    if (data.type === 'error') {
      onErrorRef.current?.(data.message || 'MCP protocol error');
    }
  }, []);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to MCP channel
  const subscribeToMcp = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }

    unsubscribeRef.current = subscribe({
      channel: 'McpChannel',
      onMessage: handleMessage,
      onError: handleError
    });
  }, [subscribe, handleMessage, handleError]);

  // Initialize MCP protocol
  const initializeProtocol = useCallback(async (): Promise<{ protocolVersion: string; serverInfo: Record<string, unknown> }> => {
    try {
      const result = await sendJsonRpcRequest('initialize', {
        protocolVersion: '2025-06-18',
        capabilities: {
          tools: {},
          workflows: {},
          agents: {}
        },
        clientInfo: {
          name: 'Powernode Frontend',
          version: '1.0.0'
        }
      });

      setProtocolInitialized(true);
      return result as { protocolVersion: string; serverInfo: Record<string, unknown> };
    } catch (error) {
      setProtocolInitialized(false);
      throw error;
    }
  }, [sendJsonRpcRequest]);

  // List available tools
  const listTools = useCallback(async (): Promise<McpTool[]> => {
    const result = await sendJsonRpcRequest('tools/list');
    if (result && typeof result === 'object' && 'tools' in result) {
      return (result as { tools: McpTool[] }).tools;
    }
    return [];
  }, [sendJsonRpcRequest]);

  // Call a tool
  const callTool = useCallback(async (name: string, args?: Record<string, unknown>): Promise<unknown> => {
    return sendJsonRpcRequest('tools/call', {
      name,
      arguments: args || {}
    });
  }, [sendJsonRpcRequest]);

  // Execute workflow via MCP
  const executeWorkflow = useCallback(async (
    workflowId: string,
    variables?: Record<string, unknown>
  ): Promise<McpWorkflowExecution> => {
    return sendJsonRpcRequest('workflow/execute', {
      workflow_id: workflowId,
      variables: variables || {}
    }) as Promise<McpWorkflowExecution>;
  }, [sendJsonRpcRequest]);

  // Execute agent via MCP
  const executeAgent = useCallback(async (
    agentId: string,
    params?: Record<string, unknown>
  ): Promise<McpAgentExecution> => {
    return sendJsonRpcRequest('agent/execute', {
      agent_id: agentId,
      parameters: params || {}
    }) as Promise<McpAgentExecution>;
  }, [sendJsonRpcRequest]);

  // Get tool description
  const describeTool = useCallback(async (name: string): Promise<McpTool> => {
    return sendJsonRpcRequest('tools/describe', { name }) as Promise<McpTool>;
  }, [sendJsonRpcRequest]);

  // Auto-subscribe when connected
  useEffect(() => {
    if (isConnected) {
      subscribeToMcp();
    }

    // Capture ref value for cleanup
    const requests = pendingRequests.current;

    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }

      // Clear all pending requests
      requests.forEach(({ timeout, reject }) => {
        clearTimeout(timeout);
        reject(new Error('WebSocket disconnected'));
      });
      requests.clear();
      setProtocolInitialized(false);
    };
  }, [isConnected, subscribeToMcp]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    protocolInitialized,
    initializeProtocol,
    listTools,
    callTool,
    executeWorkflow,
    executeAgent,
    describeTool,
    error: connectionError
  };
};
