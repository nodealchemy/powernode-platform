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
