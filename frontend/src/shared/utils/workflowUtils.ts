import { AiWorkflowNode, AiWorkflowEdge } from '@/shared/types/workflow';

/**
 * Sort workflow nodes in execution order using topological sorting
 * This ensures that nodes are displayed in the order they would execute
 *
 * @param nodes - Array of workflow nodes
 * @param edges - Array of workflow edges defining connections
 * @returns Sorted array of nodes in execution order
 */
export function sortNodesInExecutionOrder(
  nodes: AiWorkflowNode[],
  edges?: AiWorkflowEdge[]
): AiWorkflowNode[] {
  if (!nodes || nodes.length === 0) {
    return [];
  }

  if (!edges || edges.length === 0) {
    // If no edges, sort by: start nodes first, then regular nodes, then end nodes
    return sortNodesByType(nodes);
  }

  // Build adjacency list and in-degree map for topological sort
  const adjacencyList = new Map<string, string[]>();
  const inDegree = new Map<string, number>();
  const nodeMap = new Map<string, AiWorkflowNode>();

  // Initialize maps
  nodes.forEach(node => {
    nodeMap.set(node.node_id, node);
    adjacencyList.set(node.node_id, []);
    inDegree.set(node.node_id, 0);
  });

  // Build graph from edges
  edges.forEach(edge => {
    const sourceList = adjacencyList.get(edge.source_node_id);
    if (sourceList) {
      sourceList.push(edge.target_node_id);
    }

    const targetDegree = inDegree.get(edge.target_node_id);
    if (targetDegree !== undefined) {
      inDegree.set(edge.target_node_id, targetDegree + 1);
    }
  });

  // Kahn's algorithm for topological sorting
  const queue: string[] = [];
  const sorted: AiWorkflowNode[] = [];

  // Find all nodes with no incoming edges (in-degree = 0)
  // Prioritize start nodes
  const startNodes: string[] = [];
  const regularZeroDegree: string[] = [];

  inDegree.forEach((degree, nodeId) => {
    if (degree === 0) {
      const node = nodeMap.get(nodeId);
      if (node?.is_start_node) {
        startNodes.push(nodeId);
      } else {
        regularZeroDegree.push(nodeId);
      }
    }
  });

  // Add start nodes first, then other zero-degree nodes
  queue.push(...startNodes, ...regularZeroDegree);

  while (queue.length > 0) {
    const currentNodeId = queue.shift()!;
    const currentNode = nodeMap.get(currentNodeId);

    if (currentNode) {
      sorted.push(currentNode);
    }

    // Process neighbors
    const neighbors = adjacencyList.get(currentNodeId) || [];
    for (const neighborId of neighbors) {
      const neighborDegree = inDegree.get(neighborId);
      if (neighborDegree !== undefined) {
        const newDegree = neighborDegree - 1;
        inDegree.set(neighborId, newDegree);

        if (newDegree === 0) {
          // Prioritize non-end nodes in the queue
          const neighborNode = nodeMap.get(neighborId);
          if (neighborNode?.is_end_node) {
            queue.push(neighborId); // Add end nodes to the end
          } else {
            // Insert non-end nodes before any end nodes
            const endNodeIndex = queue.findIndex(id => nodeMap.get(id)?.is_end_node);
            if (endNodeIndex === -1) {
              queue.push(neighborId);
            } else {
              queue.splice(endNodeIndex, 0, neighborId);
            }
          }
        }
      }
    }
  }

  // Handle disconnected nodes (not part of the main flow)
  const sortedIds = new Set(sorted.map(n => n.node_id));
  const disconnected = nodes.filter(n => !sortedIds.has(n.node_id));

  if (disconnected.length > 0) {
    // Add disconnected nodes at the end, sorted by type
    sorted.push(...sortNodesByType(disconnected));
  }

  return sorted;
}

/**
 * Sort nodes by type: start nodes first, regular nodes, then end nodes
 */
function sortNodesByType(nodes: AiWorkflowNode[]): AiWorkflowNode[] {
  const startNodes = nodes.filter(n => n.is_start_node);
  const endNodes = nodes.filter(n => n.is_end_node);
  const regularNodes = nodes.filter(n => !n.is_start_node && !n.is_end_node);

  return [...startNodes, ...regularNodes, ...endNodes];
}

/**
 * Get execution level for each node (distance from start)
 * Useful for visualizing node hierarchy
 */
export function getNodeExecutionLevels(
  nodes: AiWorkflowNode[],
  edges?: AiWorkflowEdge[]
): Map<string, number> {
  const levels = new Map<string, number>();

  if (!nodes || nodes.length === 0) {
    return levels;
  }

  // Initialize all nodes to level 0
  nodes.forEach(node => levels.set(node.node_id, 0));

  if (!edges || edges.length === 0) {
    return levels;
  }

  // Build adjacency list
  const adjacencyList = new Map<string, string[]>();
  nodes.forEach(node => adjacencyList.set(node.node_id, []));
  edges.forEach(edge => {
    const list = adjacencyList.get(edge.source_node_id);
    if (list) {
      list.push(edge.target_node_id);
    }
  });

  // Find start nodes
  const startNodes = nodes.filter(n => n.is_start_node).map(n => n.node_id);
  if (startNodes.length === 0) {
    // If no explicit start nodes, find nodes with no incoming edges
    const hasIncoming = new Set(edges.map(e => e.target_node_id));
    startNodes.push(...nodes.filter(n => !hasIncoming.has(n.node_id)).map(n => n.node_id));
  }

  // BFS to assign levels
  const queue: [string, number][] = startNodes.map(id => [id, 0]);
  const visited = new Set<string>();

  while (queue.length > 0) {
    const [nodeId, level] = queue.shift()!;

    if (visited.has(nodeId)) continue;
    visited.add(nodeId);

    levels.set(nodeId, level);

    const neighbors = adjacencyList.get(nodeId) || [];
    for (const neighborId of neighbors) {
      if (!visited.has(neighborId)) {
        queue.push([neighborId, level + 1]);
      }
    }
  }

  return levels;
}

/**
 * Format node type for display
 */
export function formatNodeType(nodeType: string): string {
  return nodeType
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(' ');
}

/**
 * Get node type color/variant for badges
 */
export function getNodeTypeVariant(nodeType: string): string {
  const typeVariants: Record<string, string> = {
    'ai_agent': 'info',
    'api_call': 'warning',
    'webhook': 'secondary',
    'condition': 'default',
    'loop': 'outline',
    'transform': 'default',
    'delay': 'secondary',
    'human_approval': 'destructive',
    'sub_workflow': 'info',
    'merge': 'default',
    'split': 'default',
    // Knowledge Base Article Management
    'kb_article_create': 'info',
    'kb_article_read': 'default',
    'kb_article_update': 'warning',
    'kb_article_search': 'default',
    'kb_article_publish': 'info',
    // Page Content Management
    'page_create': 'info',
    'page_read': 'default',
    'page_update': 'warning',
    'page_publish': 'info'
  };

  return typeVariants[nodeType] || 'default';
}