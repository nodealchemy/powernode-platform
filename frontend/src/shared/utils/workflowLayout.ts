import * as dagre from 'dagre';
import { Node, Edge } from '@xyflow/react';

export interface LayoutOptions {
  direction?: 'TB' | 'LR';
  nodeWidth?: number;
  nodeHeight?: number;
  spacing?: number;
}

/**
 * Auto-arrange workflow nodes using dagre's Sugiyama-based hierarchical layout.
 *
 * Dagre implements the standard Sugiyama framework:
 * 1. Cycle removal (acyclic graph creation)
 * 2. Layer assignment (rank assignment using network simplex)
 * 3. Crossing reduction (layer-by-layer sweep with barycenter heuristic)
 * 4. Coordinate assignment (Brandes-Köpf algorithm for compact layout)
 *
 * This is the same approach used by GraphViz dot and other professional tools.
 */
export const autoArrangeNodes = (
  nodes: Node[],
  edges: Edge[],
  options: LayoutOptions = {}
): Node[] => {
  if (nodes.length === 0) return nodes;

  const {
    direction = 'TB',
    nodeWidth = 280,
    nodeHeight = 120,
    spacing = 80
  } = options;

  // Create dagre graph
  const g = new dagre.graphlib.Graph({ compound: false, multigraph: false });

  g.setGraph({
    rankdir: direction,
    align: 'UL',
    nodesep: spacing * 1.5,
    edgesep: spacing,
    ranksep: spacing,
    marginx: 50,
    marginy: 50,
    acyclicer: 'greedy',
    ranker: 'network-simplex'
  });

  g.setDefaultEdgeLabel(() => ({}));

  // Add nodes
  nodes.forEach((node) => {
    g.setNode(node.id, {
      width: nodeWidth,
      height: nodeHeight,
      label: node.id
    });
  });

  // Add edges with validation
  edges.forEach((edge) => {
    if (g.hasNode(edge.source) && g.hasNode(edge.target)) {
      g.setEdge(edge.source, edge.target, {
        weight: 1,
        minlen: 1
      });
    }
  });

  // Run layout algorithm
  dagre.layout(g);

  // Extract positions (dagre returns center coordinates)
  return nodes.map((node) => {
    const nodeData = g.node(node.id);
    return {
      ...node,
      position: {
        x: nodeData.x - nodeWidth / 2,
        y: nodeData.y - nodeHeight / 2
      }
    };
  });
};

/**
 * Get layout options for direction
 */
export const getLayoutOptions = (direction: 'vertical' | 'horizontal'): LayoutOptions => ({
  direction: direction === 'vertical' ? 'TB' : 'LR',
  nodeWidth: 280,
  nodeHeight: 120,
  spacing: 80
});
