import * as dagre from 'dagre';
import { Node, Edge } from '@xyflow/react';

export interface LayoutOptions {
  direction?: 'TB' | 'LR' | 'BT' | 'RL';
  nodeWidth?: number;
  nodeHeight?: number;
  nodesep?: number;
  ranksep?: number;
}

export interface CanvasConfig {
  defaultWidth: number;
  defaultHeight: number;
  expandMargin: number; // Margin from edges when layout exceeds default size
}

/**
 * Auto-arrange workflow nodes using dagre layout algorithm, centered on default canvas
 * @param nodes - Array of React Flow nodes
 * @param edges - Array of React Flow edges
 * @param options - Layout configuration options
 * @param defaultCanvasWidth - Default canvas width for centering (default: 1200, canvas can expand beyond)
 * @param defaultCanvasHeight - Default canvas height for centering (default: 800, canvas can expand beyond)
 * @returns Array of nodes with updated positions
 */
export const autoArrangeNodes = (
  nodes: Node[],
  edges: Edge[],
  options: LayoutOptions = {},
  defaultCanvasWidth: number = 1200,
  defaultCanvasHeight: number = 800
): Node[] => {
  const {
    direction = 'TB', // Top to Bottom for multi-row layout
    nodeWidth = 220,  // Width to prevent overlap
    nodeHeight = 120, // Height for all node types
    nodesep = 50,     // Horizontal spacing between nodes in same rank
    ranksep = 60      // Vertical spacing between ranks/rows
  } = options;

  // Create a new directed graph
  const dagreGraph = new dagre.graphlib.Graph();
  dagreGraph.setDefaultEdgeLabel(() => ({}));

  // Set graph options with compact margins
  dagreGraph.setGraph({
    rankdir: direction,
    nodesep,
    ranksep,
    marginx: 30,     // Horizontal margins
    marginy: 30,     // Vertical margins
    acyclicer: 'greedy',  // Better handling of cycles
    ranker: 'network-simplex'  // Better for multi-row layouts
  });

  // Add nodes to the graph
  nodes.forEach((node) => {
    dagreGraph.setNode(node.id, {
      width: nodeWidth,
      height: nodeHeight
    });
  });

  // Add edges to the graph
  edges.forEach((edge) => {
    dagreGraph.setEdge(edge.source, edge.target);
  });

  // Calculate the layout
  dagre.layout(dagreGraph);

  // Update node positions based on the calculated layout
  const layoutedNodes = nodes.map((node) => {
    const nodeWithPosition = dagreGraph.node(node.id);

    // Center the node position (dagre gives center coordinates)
    const position = {
      x: nodeWithPosition.x - nodeWidth / 2,
      y: nodeWithPosition.y - nodeHeight / 2
    };

    return {
      ...node,
      position,
      // Mark as not dragging to ensure smooth repositioning
      dragging: false,
      selected: false
    };
  });

  // Calculate bounds of the arranged layout
  const bounds = layoutedNodes.reduce(
    (acc, node) => ({
      minX: Math.min(acc.minX, node.position.x),
      maxX: Math.max(acc.maxX, node.position.x + nodeWidth),
      minY: Math.min(acc.minY, node.position.y),
      maxY: Math.max(acc.maxY, node.position.y + nodeHeight)
    }),
    { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity }
  );

  // Calculate layout dimensions
  const layoutWidth = bounds.maxX - bounds.minX;
  const layoutHeight = bounds.maxY - bounds.minY;

  // Calculate center offset to position layout optimally:
  // - Small layouts (≤ default canvas): Centered for professional appearance
  // - Large layouts (> default canvas): Positioned with margins, allowing expansion
  let centerOffsetX: number;
  let centerOffsetY: number;

  // Standard margin for large layouts that exceed default canvas
  const expandMargin = 100;

  if (layoutWidth <= defaultCanvasWidth) {
    // Layout fits within default canvas - center it horizontally
    centerOffsetX = (defaultCanvasWidth - layoutWidth) / 2 - bounds.minX;
  } else {
    // Layout exceeds default canvas width - position with margin from origin
    centerOffsetX = expandMargin - bounds.minX;
  }

  if (layoutHeight <= defaultCanvasHeight) {
    // Layout fits within default canvas - center it vertically
    centerOffsetY = (defaultCanvasHeight - layoutHeight) / 2 - bounds.minY;
  } else {
    // Layout exceeds default canvas height - position with margin from origin
    centerOffsetY = expandMargin - bounds.minY;
  }

  // Apply center offset to all nodes
  const centeredNodes = layoutedNodes.map((node) => ({
    ...node,
    position: {
      x: node.position.x + centerOffsetX,
      y: node.position.y + centerOffsetY
    }
  }));

  return centeredNodes;
};

/**
 * Auto-arrange workflow nodes with configurable canvas settings
 * @param nodes - Array of React Flow nodes
 * @param edges - Array of React Flow edges
 * @param options - Layout configuration options
 * @param canvasConfig - Canvas configuration for centering behavior
 * @returns Array of nodes with updated positions
 */
export const autoArrangeNodesWithCanvas = (
  nodes: Node[],
  edges: Edge[],
  options: LayoutOptions = {},
  canvasConfig: CanvasConfig = {
    defaultWidth: 1200,
    defaultHeight: 800,
    expandMargin: 100
  }
): Node[] => {
  return autoArrangeNodes(
    nodes,
    edges,
    options,
    canvasConfig.defaultWidth,
    canvasConfig.defaultHeight
  );
};

/**
 * Check if nodes have overlapping positions
 * @param nodes - Array of React Flow nodes
 * @param threshold - Distance threshold to consider as overlap
 * @returns true if any nodes overlap
 */
export const hasNodeOverlap = (nodes: Node[], threshold: number = 10): boolean => {
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const node1 = nodes[i];
      const node2 = nodes[j];

      const dx = Math.abs(node1.position.x - node2.position.x);
      const dy = Math.abs(node1.position.y - node2.position.y);

      if (dx < threshold && dy < threshold) {
        return true;
      }
    }
  }
  return false;
};

/**
 * Get layout options based on workflow complexity
 * @param nodeCount - Number of nodes in the workflow
 * @param _edgeCount - Number of edges in the workflow
 * @returns Optimized layout options
 */
export const getOptimalLayoutOptions = (
  nodeCount: number,
  _edgeCount: number
): LayoutOptions => {
  // Adaptive layout with compact spacing
  if (nodeCount > 20) {
    // Very large workflows - compact spacing (canvas will expand)
    return {
      direction: 'TB',
      nodeWidth: 210,
      nodeHeight: 110,
      nodesep: 45,      // Horizontal spacing
      ranksep: 55       // Vertical spacing
    };
  } else if (nodeCount > 10) {
    // Medium workflows - balanced spacing
    return {
      direction: 'TB',
      nodeWidth: 220,
      nodeHeight: 120,
      nodesep: 50,      // Horizontal spacing
      ranksep: 60       // Vertical spacing
    };
  } else {
    // Small workflows - comfortable spacing
    return {
      direction: 'TB',
      nodeWidth: 240,
      nodeHeight: 140,
      nodesep: 60,      // Horizontal spacing
      ranksep: 70       // Vertical spacing
    };
  }
};