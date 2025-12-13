import { AiWorkflowNode, AiWorkflowEdge } from '@/shared/types/workflow';
import { Node, Edge } from '@xyflow/react';

// =============================================================================
// PERFORMANCE UTILITIES
// =============================================================================

/**
 * Fast deep equality check for objects
 * More efficient than JSON.stringify for comparison
 */
export function isDeepEqual(obj1: unknown, obj2: unknown): boolean {
  if (obj1 === obj2) return true;
  if (obj1 === null || obj2 === null) return obj1 === obj2;
  if (typeof obj1 !== 'object' || typeof obj2 !== 'object') return obj1 === obj2;

  const keys1 = Object.keys(obj1 as object);
  const keys2 = Object.keys(obj2 as object);

  if (keys1.length !== keys2.length) return false;

  for (const key of keys1) {
    if (!keys2.includes(key)) return false;
    if (!isDeepEqual((obj1 as Record<string, unknown>)[key], (obj2 as Record<string, unknown>)[key])) {
      return false;
    }
  }

  return true;
}

/**
 * Create a Map for O(1) node lookups by ID
 */
export function createNodeMap<T extends { id: string }>(nodes: T[]): Map<string, T> {
  return new Map(nodes.map(node => [node.id, node]));
}

/**
 * Create a Map for O(1) edge lookups by ID
 */
export function createEdgeMap<T extends { id: string }>(edges: T[]): Map<string, T> {
  return new Map(edges.map(edge => [edge.id, edge]));
}

/**
 * Create a Map grouping edges by source node ID for O(1) lookup
 */
export function createEdgesBySourceMap<T extends { source: string }>(edges: T[]): Map<string, T[]> {
  const map = new Map<string, T[]>();
  for (const edge of edges) {
    const existing = map.get(edge.source);
    if (existing) {
      existing.push(edge);
    } else {
      map.set(edge.source, [edge]);
    }
  }
  return map;
}

/**
 * Create a Map grouping edges by target node ID for O(1) lookup
 */
export function createEdgesByTargetMap<T extends { target: string }>(edges: T[]): Map<string, T[]> {
  const map = new Map<string, T[]>();
  for (const edge of edges) {
    const existing = map.get(edge.target);
    if (existing) {
      existing.push(edge);
    } else {
      map.set(edge.target, [edge]);
    }
  }
  return map;
}

/**
 * Efficient check if nodes have changed (compared to original)
 * Uses reference equality first, then deep comparison only when needed
 */
export function haveNodesChanged<T extends Node>(
  currentNodes: T[],
  originalNodes: T[],
  originalNodeMap?: Map<string, T>
): boolean {
  if (currentNodes === originalNodes) return false;
  if (currentNodes.length !== originalNodes.length) return true;

  const nodeMap = originalNodeMap || createNodeMap(originalNodes);

  for (const node of currentNodes) {
    const original = nodeMap.get(node.id);
    if (!original) return true;
    if (node === original) continue;

    // Check position changes
    if (node.position.x !== original.position.x || node.position.y !== original.position.y) {
      return true;
    }

    // Check data changes with deep equality
    if (!isDeepEqual(node.data, original.data)) {
      return true;
    }
  }

  return false;
}

/**
 * Efficient check if edges have changed (compared to original)
 */
export function haveEdgesChanged<T extends Edge>(
  currentEdges: T[],
  originalEdges: T[],
  originalEdgeMap?: Map<string, T>
): boolean {
  if (currentEdges === originalEdges) return false;
  if (currentEdges.length !== originalEdges.length) return true;

  const edgeMap = originalEdgeMap || createEdgeMap(originalEdges);

  for (const edge of currentEdges) {
    const original = edgeMap.get(edge.id);
    if (!original) return true;
    if (edge === original) continue;

    // Check connection changes
    if (
      edge.source !== original.source ||
      edge.target !== original.target ||
      edge.sourceHandle !== original.sourceHandle ||
      edge.targetHandle !== original.targetHandle
    ) {
      return true;
    }

    // Check data changes
    if (!isDeepEqual(edge.data, original.data)) {
      return true;
    }
  }

  return false;
}

/**
 * Debounce function for rate-limiting expensive operations
 */
export function debounce<T extends (...args: Parameters<T>) => ReturnType<T>>(
  fn: T,
  delay: number
): (...args: Parameters<T>) => void {
  let timeoutId: ReturnType<typeof setTimeout> | null = null;

  return function (this: unknown, ...args: Parameters<T>) {
    if (timeoutId) {
      clearTimeout(timeoutId);
    }
    timeoutId = setTimeout(() => {
      fn.apply(this, args);
      timeoutId = null;
    }, delay);
  };
}

/**
 * Throttle function for limiting call frequency
 */
export function throttle<T extends (...args: Parameters<T>) => ReturnType<T>>(
  fn: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle = false;
  let lastArgs: Parameters<T> | null = null;

  return function (this: unknown, ...args: Parameters<T>) {
    if (!inThrottle) {
      fn.apply(this, args);
      inThrottle = true;
      setTimeout(() => {
        inThrottle = false;
        if (lastArgs) {
          fn.apply(this, lastArgs);
          lastArgs = null;
        }
      }, limit);
    } else {
      lastArgs = args;
    }
  };
}

/**
 * Batch updates using requestAnimationFrame for smoother rendering
 */
export function batchUpdates(callback: () => void): void {
  if (typeof requestAnimationFrame !== 'undefined') {
    requestAnimationFrame(() => {
      callback();
    });
  } else {
    // Fallback for non-browser environments
    setTimeout(callback, 0);
  }
}

/**
 * Schedule multiple updates to be executed in sequence after layout
 */
export function scheduleSequentialUpdates(callbacks: (() => void)[]): void {
  if (callbacks.length === 0) return;

  const runNext = (index: number) => {
    if (index >= callbacks.length) return;
    batchUpdates(() => {
      callbacks[index]();
      if (index + 1 < callbacks.length) {
        runNext(index + 1);
      }
    });
  };

  runNext(0);
}

// =============================================================================
// GRAPH UTILITIES
// =============================================================================

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

// =============================================================================
// EDGE VALIDATION UTILITIES
// =============================================================================

export interface EdgeValidationResult {
  valid: boolean;
  reason?: string;
}

export interface NodeForValidation {
  id: string;
  type?: string;
  data?: {
    is_start_node?: boolean;
    is_end_node?: boolean;
    node_type?: string;
    isStartNode?: boolean;
    isEndNode?: boolean;
  };
}

export interface EdgeForValidation {
  id: string;
  source: string;
  target: string;
  sourceHandle?: string | null;
  targetHandle?: string | null;
}

/**
 * Validate a new edge connection against various rules
 */
export function validateEdgeConnection(
  source: NodeForValidation,
  target: NodeForValidation,
  sourceHandle: string | null | undefined,
  targetHandle: string | null | undefined,
  existingEdges: EdgeForValidation[]
): EdgeValidationResult {
  // Rule 1: Self-loop prevention
  if (source.id === target.id) {
    return { valid: false, reason: 'Cannot connect a node to itself' };
  }

  // Rule 2: Check for duplicate edges (same source, target, and handles)
  const isDuplicate = existingEdges.some(edge =>
    edge.source === source.id &&
    edge.target === target.id &&
    edge.sourceHandle === sourceHandle &&
    edge.targetHandle === targetHandle
  );
  if (isDuplicate) {
    return { valid: false, reason: 'This connection already exists' };
  }

  // Rule 3: Prevent connections TO start/trigger nodes
  const targetType = target.type || target.data?.node_type || '';
  const isTargetStartNode = targetType === 'start' ||
    targetType === 'trigger' ||
    target.data?.is_start_node === true ||
    target.data?.isStartNode === true;

  if (isTargetStartNode) {
    return { valid: false, reason: 'Start nodes cannot have incoming connections' };
  }

  // Rule 4: Prevent connections FROM end nodes
  const sourceType = source.type || source.data?.node_type || '';
  const isSourceEndNode = sourceType === 'end' ||
    source.data?.is_end_node === true ||
    source.data?.isEndNode === true;

  if (isSourceEndNode) {
    return { valid: false, reason: 'End nodes cannot have outgoing connections' };
  }

  // Rule 5: Check for cycles (optional - can be expensive for large graphs)
  // This creates a simple cycle detection by checking if target can reach source
  const wouldCreateCycle = checkForCycle(source.id, target.id, existingEdges);
  if (wouldCreateCycle) {
    return { valid: false, reason: 'This connection would create a cycle' };
  }

  return { valid: true };
}

/**
 * Check if adding an edge from source to target would create a cycle
 * Uses BFS to check if target can reach source through existing edges
 */
function checkForCycle(
  sourceId: string,
  targetId: string,
  existingEdges: EdgeForValidation[]
): boolean {
  // Build adjacency list
  const adjacencyList = new Map<string, string[]>();
  for (const edge of existingEdges) {
    const existing = adjacencyList.get(edge.source);
    if (existing) {
      existing.push(edge.target);
    } else {
      adjacencyList.set(edge.source, [edge.target]);
    }
  }

  // BFS from target to see if we can reach source
  const visited = new Set<string>();
  const queue = [targetId];

  while (queue.length > 0) {
    const current = queue.shift()!;
    if (current === sourceId) {
      return true; // Found a path from target to source - would create cycle
    }

    if (visited.has(current)) continue;
    visited.add(current);

    const neighbors = adjacencyList.get(current) || [];
    for (const neighbor of neighbors) {
      if (!visited.has(neighbor)) {
        queue.push(neighbor);
      }
    }
  }

  return false;
}

/**
 * Validate all edges in a workflow for consistency
 */
export function validateWorkflowEdges(
  nodes: NodeForValidation[],
  edges: EdgeForValidation[]
): { valid: boolean; errors: string[] } {
  const errors: string[] = [];
  const nodeMap = new Map(nodes.map(n => [n.id, n]));

  for (const edge of edges) {
    const sourceNode = nodeMap.get(edge.source);
    const targetNode = nodeMap.get(edge.target);

    // Check for orphaned edges (referencing non-existent nodes)
    if (!sourceNode) {
      errors.push(`Edge ${edge.id} references non-existent source node: ${edge.source}`);
      continue;
    }
    if (!targetNode) {
      errors.push(`Edge ${edge.id} references non-existent target node: ${edge.target}`);
      continue;
    }

    // Validate the connection
    const validation = validateEdgeConnection(
      sourceNode,
      targetNode,
      edge.sourceHandle,
      edge.targetHandle,
      edges.filter(e => e.id !== edge.id) // Exclude current edge from duplicate check
    );

    if (!validation.valid && validation.reason) {
      errors.push(`Edge ${edge.id}: ${validation.reason}`);
    }
  }

  // Check for duplicate edge IDs
  const edgeIds = edges.map(e => e.id);
  const duplicateIds = edgeIds.filter((id, index) => edgeIds.indexOf(id) !== index);
  if (duplicateIds.length > 0) {
    errors.push(`Duplicate edge IDs found: ${[...new Set(duplicateIds)].join(', ')}`);
  }

  return {
    valid: errors.length === 0,
    errors
  };
}

/**
 * Get maximum allowed outgoing connections for a node type
 */
export function getMaxOutgoingConnections(nodeType: string): number {
  const maxConnections: Record<string, number> = {
    'start': 1,
    'trigger': 1,
    'end': 0,
    'condition': 3, // true, false, default
    'split': 5,     // multiple branches
    'loop': 2,      // continue, exit
  };

  return maxConnections[nodeType] ?? Infinity;
}

/**
 * Get maximum allowed incoming connections for a node type
 */
export function getMaxIncomingConnections(nodeType: string): number {
  const maxConnections: Record<string, number> = {
    'start': 0,
    'trigger': 0,
    'merge': 5, // multiple inputs
  };

  return maxConnections[nodeType] ?? Infinity;
}