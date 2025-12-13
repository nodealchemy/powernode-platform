#!/usr/bin/env node
/**
 * MCP Base Server - Shared utilities for MCP server implementations
 *
 * This module provides the core JSON-RPC 2.0 message handling and MCP protocol
 * implementation that all example servers can use.
 *
 * MCP Protocol Version: 2024-11-05
 */

const readline = require('readline');

class McpBaseServer {
  constructor(serverInfo) {
    this.serverInfo = {
      name: serverInfo.name || 'mcp-server',
      version: serverInfo.version || '1.0.0',
      description: serverInfo.description || 'MCP Server'
    };
    this.tools = new Map();
    this.resources = new Map();
    this.initialized = false;
  }

  /**
   * Register a tool with the server
   * @param {Object} toolDefinition - Tool definition with name, description, inputSchema, handler
   */
  registerTool(toolDefinition) {
    const { name, description, inputSchema, outputSchema, handler, permissionLevel, requiredPermissions, allowedScopes } = toolDefinition;

    this.tools.set(name, {
      name,
      description: description || '',
      inputSchema: inputSchema || { type: 'object', properties: {} },
      outputSchema: outputSchema || { type: 'object' },
      handler,
      permissionLevel: permissionLevel || 'public',
      requiredPermissions: requiredPermissions || [],
      allowedScopes: allowedScopes || {}
    });
  }

  /**
   * Register a resource with the server
   * @param {Object} resourceDefinition - Resource definition
   */
  registerResource(resourceDefinition) {
    const { uri, name, description, mimeType } = resourceDefinition;
    this.resources.set(uri, { uri, name, description, mimeType });
  }

  /**
   * Build server capabilities response
   */
  getCapabilities() {
    return {
      protocolVersion: '2024-11-05',
      capabilities: {
        tools: { listChanged: true },
        resources: { subscribe: false, listChanged: false }
      },
      serverInfo: this.serverInfo
    };
  }

  /**
   * Handle incoming JSON-RPC message
   * @param {Object} message - Parsed JSON-RPC message
   */
  async handleMessage(message) {
    const { jsonrpc, method, params, id } = message;

    // Validate JSON-RPC version
    if (jsonrpc !== '2.0') {
      return this.createError(id, -32600, 'Invalid Request: jsonrpc must be "2.0"');
    }

    try {
      switch (method) {
        case 'initialize':
          return this.handleInitialize(id, params);

        case 'initialized':
          this.initialized = true;
          return null; // No response for notifications

        case 'ping':
          return this.createResponse(id, { pong: true, timestamp: new Date().toISOString() });

        case 'tools/list':
          return this.handleListTools(id, params);

        case 'tools/call':
          return await this.handleCallTool(id, params);

        case 'resources/list':
          return this.handleListResources(id, params);

        case 'resources/read':
          return this.handleReadResource(id, params);

        default:
          return this.createError(id, -32601, `Method not found: ${method}`);
      }
    } catch (error) {
      return this.createError(id, -32603, `Internal error: ${error.message}`);
    }
  }

  /**
   * Handle initialize request
   */
  handleInitialize(id, params) {
    const clientInfo = params?.clientInfo || {};
    this.log(`Client connected: ${clientInfo.name || 'unknown'} v${clientInfo.version || '?'}`);

    return this.createResponse(id, this.getCapabilities());
  }

  /**
   * Handle tools/list request
   */
  handleListTools(id, params) {
    const tools = Array.from(this.tools.values()).map(tool => ({
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema
    }));

    return this.createResponse(id, { tools });
  }

  /**
   * Handle tools/call request
   */
  async handleCallTool(id, params) {
    const { name, arguments: args } = params;

    const tool = this.tools.get(name);
    if (!tool) {
      return this.createError(id, -32602, `Tool not found: ${name}`);
    }

    try {
      // Validate input against schema (basic validation)
      this.validateInput(args, tool.inputSchema);

      // Execute the tool handler
      const result = await tool.handler(args || {});

      return this.createResponse(id, {
        content: [
          {
            type: 'text',
            text: typeof result === 'string' ? result : JSON.stringify(result, null, 2)
          }
        ]
      });
    } catch (error) {
      return this.createError(id, -32000, `Tool execution failed: ${error.message}`);
    }
  }

  /**
   * Handle resources/list request
   */
  handleListResources(id, params) {
    const resources = Array.from(this.resources.values());
    return this.createResponse(id, { resources });
  }

  /**
   * Handle resources/read request
   */
  handleReadResource(id, params) {
    const { uri } = params;
    const resource = this.resources.get(uri);

    if (!resource) {
      return this.createError(id, -32602, `Resource not found: ${uri}`);
    }

    return this.createResponse(id, {
      contents: [
        {
          uri: resource.uri,
          mimeType: resource.mimeType || 'text/plain',
          text: `Resource: ${resource.name}`
        }
      ]
    });
  }

  /**
   * Basic input validation against JSON Schema
   */
  validateInput(input, schema) {
    if (!schema || schema.type !== 'object') return;

    const required = schema.required || [];
    for (const field of required) {
      if (input[field] === undefined) {
        throw new Error(`Missing required field: ${field}`);
      }
    }

    const properties = schema.properties || {};
    for (const [key, value] of Object.entries(input || {})) {
      const propSchema = properties[key];
      if (propSchema) {
        this.validateType(value, propSchema.type, key);
      }
    }
  }

  /**
   * Validate value type
   */
  validateType(value, expectedType, fieldName) {
    if (!expectedType) return;

    const actualType = Array.isArray(value) ? 'array' : typeof value;

    if (expectedType === 'integer' && (typeof value !== 'number' || !Number.isInteger(value))) {
      throw new Error(`Field ${fieldName} must be an integer`);
    } else if (expectedType === 'number' && typeof value !== 'number') {
      throw new Error(`Field ${fieldName} must be a number`);
    } else if (expectedType !== 'integer' && expectedType !== 'number' && actualType !== expectedType) {
      throw new Error(`Field ${fieldName} must be of type ${expectedType}`);
    }
  }

  /**
   * Create a JSON-RPC response
   */
  createResponse(id, result) {
    return {
      jsonrpc: '2.0',
      id,
      result
    };
  }

  /**
   * Create a JSON-RPC error response
   */
  createError(id, code, message, data = null) {
    const error = { code, message };
    if (data) error.data = data;

    return {
      jsonrpc: '2.0',
      id,
      error
    };
  }

  /**
   * Log a message to stderr (won't interfere with stdio communication)
   */
  log(message) {
    console.error(`[${this.serverInfo.name}] ${message}`);
  }

  /**
   * Start the server in stdio mode
   */
  startStdio() {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: false
    });

    this.log('Server started in stdio mode');

    rl.on('line', async (line) => {
      try {
        const message = JSON.parse(line);
        const response = await this.handleMessage(message);

        if (response) {
          console.log(JSON.stringify(response));
        }
      } catch (error) {
        const errorResponse = this.createError(null, -32700, `Parse error: ${error.message}`);
        console.log(JSON.stringify(errorResponse));
      }
    });

    rl.on('close', () => {
      this.log('Connection closed');
      process.exit(0);
    });

    process.on('SIGINT', () => {
      this.log('Received SIGINT, shutting down');
      process.exit(0);
    });

    process.on('SIGTERM', () => {
      this.log('Received SIGTERM, shutting down');
      process.exit(0);
    });
  }
}

module.exports = { McpBaseServer };
