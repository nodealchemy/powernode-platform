import { useMemo } from 'react';
import { AiWorkflowNode, AiWorkflowVariable } from '@/shared/types/workflow';

export interface WorkflowVariable {
  name: string;
  path: string;
  type: 'input' | 'output' | 'node_output';
  dataType: string;
  nodeId?: string;
  nodeName?: string;
  description?: string;
}

interface UseWorkflowVariablesOptions {
  /** Current node ID - variables from this node and later nodes will be excluded */
  currentNodeId?: string;
  /** All nodes in the workflow */
  nodes: AiWorkflowNode[];
  /** Workflow input variables */
  inputVariables?: AiWorkflowVariable[];
  /** All edges in the workflow - used to determine node ordering */
  edges?: Array<{ source_node_id: string; target_node_id: string }>;
}

/**
 * Hook to get available workflow variables that can be mapped to node parameters.
 * Returns variables from:
 * - Workflow input variables (always available)
 * - Output from previous nodes (based on workflow execution order)
 */
export function useWorkflowVariables({
  currentNodeId,
  nodes,
  inputVariables = [],
  edges = [],
}: UseWorkflowVariablesOptions): {
  variables: WorkflowVariable[];
  getVariablePath: (variable: WorkflowVariable) => string;
} {
  const variables = useMemo(() => {
    const result: WorkflowVariable[] = [];

    // Add workflow input variables
    inputVariables.forEach(variable => {
      if (variable.is_input) {
        result.push({
          name: variable.name,
          path: `input.${variable.name}`,
          type: 'input',
          dataType: variable.variable_type,
          description: variable.description,
        });
      }
    });

    // Determine execution order of nodes (topological sort based on edges)
    const nodeOrder = getNodeExecutionOrder(nodes, edges);

    // Find current node position
    const currentNodeIndex = currentNodeId
      ? nodeOrder.findIndex(id => id === currentNodeId)
      : nodeOrder.length;

    // Add outputs from previous nodes
    for (let i = 0; i < currentNodeIndex; i++) {
      const nodeId = nodeOrder[i];
      const node = nodes.find(n => n.node_id === nodeId);

      if (node) {
        // Standard node output
        result.push({
          name: `${node.name} Output`,
          path: `nodes.${node.node_id}.output`,
          type: 'node_output',
          dataType: 'any',
          nodeId: node.node_id,
          nodeName: node.name,
          description: `Output from ${node.name}`,
        });

        // Also expose specific output fields based on node type
        const outputFields = getNodeOutputFields(node);
        outputFields.forEach(field => {
          result.push({
            name: `${node.name} → ${field.name}`,
            path: `nodes.${node.node_id}.${field.path}`,
            type: 'node_output',
            dataType: field.dataType,
            nodeId: node.node_id,
            nodeName: node.name,
            description: field.description,
          });
        });
      }
    }

    return result;
  }, [currentNodeId, nodes, inputVariables, edges]);

  const getVariablePath = (variable: WorkflowVariable): string => {
    return `{{${variable.path}}}`;
  };

  return { variables, getVariablePath };
}

/**
 * Get node execution order using topological sort
 */
function getNodeExecutionOrder(
  nodes: AiWorkflowNode[],
  edges: Array<{ source_node_id: string; target_node_id: string }>
): string[] {
  // Build adjacency list
  const adjacencyList = new Map<string, string[]>();
  const inDegree = new Map<string, number>();

  // Initialize
  nodes.forEach(node => {
    adjacencyList.set(node.node_id, []);
    inDegree.set(node.node_id, 0);
  });

  // Build graph
  edges.forEach(edge => {
    const neighbors = adjacencyList.get(edge.source_node_id);
    if (neighbors) {
      neighbors.push(edge.target_node_id);
    }
    inDegree.set(edge.target_node_id, (inDegree.get(edge.target_node_id) || 0) + 1);
  });

  // Find start nodes (in-degree = 0)
  const queue: string[] = [];
  inDegree.forEach((degree, nodeId) => {
    if (degree === 0) {
      queue.push(nodeId);
    }
  });

  // Topological sort
  const result: string[] = [];
  while (queue.length > 0) {
    const nodeId = queue.shift()!;
    result.push(nodeId);

    const neighbors = adjacencyList.get(nodeId) || [];
    neighbors.forEach(neighbor => {
      const newDegree = (inDegree.get(neighbor) || 0) - 1;
      inDegree.set(neighbor, newDegree);
      if (newDegree === 0) {
        queue.push(neighbor);
      }
    });
  }

  return result;
}

/**
 * Get specific output fields for a node type
 */
function getNodeOutputFields(node: AiWorkflowNode): Array<{
  name: string;
  path: string;
  dataType: string;
  description?: string;
}> {
  const fields: Array<{
    name: string;
    path: string;
    dataType: string;
    description?: string;
  }> = [];

  switch (node.node_type) {
    case 'ai_agent':
      fields.push(
        { name: 'Response', path: 'result.response', dataType: 'string', description: 'AI agent response text' },
        { name: 'Tokens Used', path: 'metadata.tokens_used', dataType: 'number', description: 'Token count' }
      );
      break;

    case 'api_call':
      fields.push(
        { name: 'Response Body', path: 'data.body', dataType: 'object', description: 'API response body' },
        { name: 'Status Code', path: 'data.status_code', dataType: 'number', description: 'HTTP status code' },
        { name: 'Headers', path: 'data.headers', dataType: 'object', description: 'Response headers' }
      );
      break;

    case 'transform':
      fields.push(
        { name: 'Transformed Data', path: 'data', dataType: 'any', description: 'Transformed output' }
      );
      break;

    case 'condition':
      fields.push(
        { name: 'Result', path: 'result', dataType: 'boolean', description: 'Condition result' },
        { name: 'Branch', path: 'data.branch', dataType: 'string', description: 'Selected branch' }
      );
      break;

    case 'mcp_operation':
      // Consolidated MCP operation node (tool, resource, prompt)
      // Output fields vary based on operation_type in configuration
      fields.push(
        { name: 'Result', path: 'result', dataType: 'any', description: 'MCP operation result' },
        { name: 'Data', path: 'data', dataType: 'object', description: 'Full operation response data' },
        { name: 'Content', path: 'data.content', dataType: 'any', description: 'Resource/prompt content' },
        { name: 'Messages', path: 'data.messages', dataType: 'array', description: 'Prompt messages (if prompt operation)' }
      );
      break;

    case 'kb_article':
      // Consolidated KB article node (create, read, update, search, publish)
      // Output fields vary based on action in configuration
      fields.push(
        { name: 'Article', path: 'result', dataType: 'object', description: 'Article data' },
        { name: 'Articles', path: 'data.articles', dataType: 'array', description: 'Search results (if search action)' },
        { name: 'Count', path: 'data.total', dataType: 'number', description: 'Result count (if search action)' }
      );
      break;

    case 'page':
      // Consolidated page node (create, read, update, publish)
      fields.push(
        { name: 'Page', path: 'result', dataType: 'object', description: 'Page data' },
        { name: 'Content', path: 'data.content', dataType: 'string', description: 'Page content' }
      );
      break;

    case 'loop':
      fields.push(
        { name: 'Current Item', path: 'data.current_item', dataType: 'any', description: 'Current iteration item' },
        { name: 'Index', path: 'data.index', dataType: 'number', description: 'Current iteration index' },
        { name: 'Results', path: 'data.results', dataType: 'array', description: 'All iteration results' }
      );
      break;

    default:
      // Generic output for other node types
      fields.push(
        { name: 'Data', path: 'data', dataType: 'any', description: 'Node output data' }
      );
  }

  return fields;
}

/**
 * Helper to resolve a variable path from workflow context
 */
export function resolveVariablePath(
  path: string,
  context: {
    input?: Record<string, unknown>;
    nodes?: Record<string, { output?: unknown; data?: unknown; result?: unknown; metadata?: unknown }>;
  }
): unknown {
  // Remove {{ }} wrapper if present
  const cleanPath = path.replace(/^\{\{|\}\}$/g, '').trim();
  const parts = cleanPath.split('.');

  let current: unknown = context;
  for (const part of parts) {
    if (current === null || current === undefined) {
      return undefined;
    }
    if (typeof current === 'object') {
      current = (current as Record<string, unknown>)[part];
    } else {
      return undefined;
    }
  }

  return current;
}
