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
