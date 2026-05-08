import React, { useMemo, useState } from 'react';
import * as dagre from 'dagre';
import {
  ReactFlow,
  Background,
  Controls,
  MarkerType,
  Position,
  type Node as FlowNode,
  type Edge as FlowEdge
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import {
  Cpu,
  HardDrive,
  Database,
  Zap,
  Network,
  Globe,
  Smartphone,
  Cloud,
  Maximize2,
  Minimize2
} from 'lucide-react';
import type { TopologyNode, TopologyPreview, TopologyNodeType } from './types';

export interface StackTopologyPreviewProps {
  topology: TopologyPreview;
  /** Containing width — default 280 (modal embed). Pass `'100%'` for fluid layouts. */
  width?: number | string;
  /** Containing height — default 320 (modal embed). */
  height?: number | string;
  /** When true, render an expand toggle in the corner. Default true. */
  expandable?: boolean;
  className?: string;
}

interface NodeStyleSpec {
  width: number;
  height: number;
  background: string;
  border: string;
  borderRadius: number;
  borderStyle: 'solid' | 'dashed';
  shape: 'rounded' | 'square' | 'cylinder' | 'hexagon' | 'diamond' | 'circle';
}

/**
 * Per-type sizing + theming. Colors are sourced from theme CSS vars with hard
 * fallbacks so the diagram still looks reasonable if a theme overrides the
 * default palette without supplying every var.
 */
// Sizes are tuned for the embedded preview, not a full architecture
// diagram — compact enough to fit several rows in a modal without
// overflow. Children inside `network` containers must fit within
// CHILD_COL_WIDTH × CHILD_ROW_HEIGHT (see layout pass below); keep the
// largest "child-class" type (compute / database) within those bounds.
const NODE_STYLE: Record<TopologyNodeType, NodeStyleSpec> = {
  compute: {
    width: 116, height: 40,
    background: 'rgba(59, 130, 246, 0.10)', border: 'var(--theme-info, #3b82f6)',
    borderRadius: 10, borderStyle: 'solid', shape: 'rounded'
  },
  volume: {
    width: 80, height: 40,
    background: 'var(--theme-surface, #1f2937)', border: 'var(--theme-border, #4b5563)',
    borderRadius: 4, borderStyle: 'solid', shape: 'square'
  },
  database: {
    width: 116, height: 40,
    background: 'rgba(59, 130, 246, 0.10)', border: 'var(--theme-info, #3b82f6)',
    borderRadius: 20, borderStyle: 'solid', shape: 'cylinder'
  },
  cache: {
    width: 96, height: 40,
    background: 'rgba(234, 179, 8, 0.10)', border: 'var(--theme-warning, #eab308)',
    borderRadius: 8, borderStyle: 'solid', shape: 'hexagon'
  },
  network: {
    width: 240, height: 140,
    background: 'transparent', border: 'var(--theme-border, #4b5563)',
    borderRadius: 12, borderStyle: 'dashed', shape: 'rounded'
  },
  gateway: {
    width: 64, height: 40,
    background: 'rgba(34, 197, 94, 0.10)', border: 'var(--theme-success, #22c55e)',
    borderRadius: 10, borderStyle: 'solid', shape: 'diamond'
  },
  user_device: {
    width: 40, height: 40,
    background: 'var(--theme-surface, #1f2937)', border: 'var(--theme-border, #4b5563)',
    borderRadius: 20, borderStyle: 'solid', shape: 'circle'
  },
  external_provider: {
    width: 96, height: 40,
    background: 'var(--theme-surface, #1f2937)', border: 'var(--theme-border, #4b5563)',
    borderRadius: 6, borderStyle: 'solid', shape: 'rounded'
  }
};

const NODE_ICON: Record<TopologyNodeType, React.ComponentType<{ className?: string }>> = {
  compute: Cpu,
  volume: HardDrive,
  database: Database,
  cache: Zap,
  network: Network,
  gateway: Globe,
  user_device: Smartphone,
  external_provider: Cloud
};

// Layout geometry now computed by dagre's compound (subgraph) layout —
// see layoutTopology(). Container sizes adapt to children automatically;
// the manual region-column / child-grid constants we used previously are
// no longer needed.

/**
 * Build a ReactFlow node + edge graph from the backend topology preview.
 *
 * Two-pass dagre layout. Compound (subgraph) mode hits a known rank-
 * assignment bug ("Cannot set properties of undefined (setting 'rank')")
 * when edges cross subgraph boundaries, which is exactly our shape:
 * gateway → compute edges run from outside the `network` container into
 * children inside it. The two-pass approach sidesteps the bug:
 *
 *   1. INNER pass per container: dagre lays out only that container's
 *      children + edges between them. Output is the children's positions
 *      relative to the container's origin, plus the container's bounds.
 *   2. OUTER pass: dagre lays out non-container nodes + container proxies
 *      (fixed-size from inner pass) using only edges that don't both live
 *      inside a single container.
 *
 * Direction LR matches our left/right handle positions for clean
 * horizontal flow with smoothstep edges.
 */

const DAGRE_NODESEP = 18;
const DAGRE_RANKSEP = 36;
const DAGRE_MARGIN = 16;

const layoutTopology = (
  preview: TopologyPreview
): {
  positions: Map<string, { x: number; y: number }>;
  sizes: Map<string, { width: number; height: number }>;
} => {
  const positions = new Map<string, { x: number; y: number }>();
  const sizes = new Map<string, { width: number; height: number }>();

  const containerIds = new Set(
    preview.nodes.filter((n) => n.type === 'network').map((n) => n.id)
  );
  const childrenOf = new Map<string, TopologyNode[]>();
  preview.nodes.forEach((n) => {
    if (n.parent_id && containerIds.has(n.parent_id)) {
      const arr = childrenOf.get(n.parent_id) ?? [];
      arr.push(n);
      childrenOf.set(n.parent_id, arr);
    }
  });

  const sizeOf = (n: TopologyNode): { width: number; height: number } => {
    const style = NODE_STYLE[n.type] ?? NODE_STYLE.compute;
    return { width: style.width, height: style.height };
  };

  // Pass 1: lay out each container's children. Each container's children
  // are positioned relative to the container's local origin (0, 0).
  containerIds.forEach((containerId) => {
    const children = childrenOf.get(containerId) ?? [];
    if (children.length === 0) {
      sizes.set(containerId, { width: 200, height: 80 });
      return;
    }

    const g = new dagre.graphlib.Graph();
    g.setGraph({
      rankdir: 'LR',
      align: 'UL',
      nodesep: DAGRE_NODESEP,
      ranksep: DAGRE_RANKSEP,
      marginx: DAGRE_MARGIN,
      marginy: DAGRE_MARGIN,
      ranker: 'tight-tree'
    });
    g.setDefaultEdgeLabel(() => ({}));

    const childIds = new Set(children.map((c) => c.id));
    children.forEach((c) => {
      const dim = sizeOf(c);
      g.setNode(c.id, { width: dim.width, height: dim.height });
    });
    // Only edges where BOTH endpoints are inside this container.
    preview.edges.forEach((e) => {
      if (childIds.has(e.source) && childIds.has(e.target)) {
        g.setEdge(e.source, e.target);
      }
    });
    dagre.layout(g);

    // Compute child relative positions + container bounds from dagre output.
    let maxX = 0;
    let maxY = 0;
    children.forEach((c) => {
      const dn = g.node(c.id);
      if (!dn) return;
      const x = dn.x - dn.width / 2;
      const y = dn.y - dn.height / 2;
      positions.set(c.id, { x, y });
      sizes.set(c.id, { width: dn.width, height: dn.height });
      maxX = Math.max(maxX, x + dn.width);
      maxY = Math.max(maxY, y + dn.height);
    });
    sizes.set(containerId, {
      width: maxX + DAGRE_MARGIN,
      height: maxY + DAGRE_MARGIN
    });
  });

  // Pass 2: lay out non-container nodes + container proxies (using sizes
  // computed in pass 1). Skip edges that belong entirely inside a container.
  const outerGraph = new dagre.graphlib.Graph();
  outerGraph.setGraph({
    rankdir: 'LR',
    align: 'UL',
    nodesep: DAGRE_NODESEP,
    ranksep: DAGRE_RANKSEP,
    marginx: DAGRE_MARGIN,
    marginy: DAGRE_MARGIN,
    ranker: 'tight-tree'
  });
  outerGraph.setDefaultEdgeLabel(() => ({}));

  // Container parents that we've laid children inside, kept as opaque proxies
  // here. Non-container nodes go in directly.
  preview.nodes.forEach((n) => {
    if (n.parent_id && containerIds.has(n.parent_id)) return; // child handled in pass 1
    if (containerIds.has(n.id)) {
      const dim = sizes.get(n.id) ?? { width: 200, height: 80 };
      outerGraph.setNode(n.id, { width: dim.width, height: dim.height });
    } else {
      const dim = sizeOf(n);
      sizes.set(n.id, dim);
      outerGraph.setNode(n.id, { width: dim.width, height: dim.height });
    }
  });

  preview.edges.forEach((e) => {
    const sNode = preview.nodes.find((n) => n.id === e.source);
    const tNode = preview.nodes.find((n) => n.id === e.target);
    if (!sNode || !tNode) return;
    // Map endpoints to their outer-graph representative: a child becomes
    // its parent container; everything else is itself.
    const outerS = sNode.parent_id && containerIds.has(sNode.parent_id) ? sNode.parent_id : e.source;
    const outerT = tNode.parent_id && containerIds.has(tNode.parent_id) ? tNode.parent_id : e.target;
    if (outerS === outerT) return; // edge entirely inside one container
    if (outerGraph.hasNode(outerS) && outerGraph.hasNode(outerT)) {
      outerGraph.setEdge(outerS, outerT);
    }
  });

  dagre.layout(outerGraph);

  // Write absolute positions for outer-graph nodes (containers + outsiders).
  outerGraph.nodes().forEach((id) => {
    const dn = outerGraph.node(id);
    if (!dn) return;
    positions.set(id, { x: dn.x - dn.width / 2, y: dn.y - dn.height / 2 });
  });

  return { positions, sizes };
};

export const buildTopologyFlowGraph = (
  preview: TopologyPreview | null | undefined
): { nodes: FlowNode[]; edges: FlowEdge[] } => {
  if (!preview || !Array.isArray(preview.nodes) || preview.nodes.length === 0) {
    return { nodes: [], edges: [] };
  }

  const containers = preview.nodes.filter((n) => n.type === 'network');
  const leaves = preview.nodes.filter((n) => n.type !== 'network');

  const { positions, sizes } = layoutTopology(preview);

  const renderNode = (node: TopologyNode): FlowNode => {
    const style = NODE_STYLE[node.type] ?? NODE_STYLE.compute;
    const Icon = NODE_ICON[node.type] ?? Cpu;
    const pos = positions.get(node.id) ?? { x: 0, y: 0 };
    const isContainer = node.type === 'network';

    // Containers grow to fit their children via dagre's compound layout —
    // sizes.get(node.id) returns dagre's computed bounds.
    const dims = sizes.get(node.id) ?? { width: style.width, height: style.height };

    const baseStyle: React.CSSProperties = {
      width: dims.width,
      height: dims.height,
      background: style.background,
      border: `${style.borderStyle === 'dashed' ? '1px dashed' : '1.5px solid'} ${style.border}`,
      borderRadius: style.borderRadius,
      padding: 0,
      color: 'var(--theme-primary, #f9fafb)'
    };

    // Handles on left+right (rather than ReactFlow's default top+bottom)
    // so edges can route horizontally — much cleaner for the hub-and-spoke
    // topology (user → gateway → provider → compute clusters) than having
    // every line funnel through the same vertical handle points.
    //
    // ReactFlow uses top-level `width`/`height` for parent-container layout
    // calculations (separate from `style.width/height` which is just CSS).
    // Setting both ensures children's `extent: 'parent'` clamping uses the
    // dynamically-grown size, not ReactFlow's measured/default fallback.
    const flowNode: FlowNode = {
      id: node.id,
      position: pos,
      width: dims.width,
      height: dims.height,
      data: {
        label: (
          <div className="flex items-center gap-1.5 px-2 w-full justify-center" style={{ minWidth: 0 }}>
            <Icon className="w-4 h-4 flex-shrink-0" />
            <span className="text-xs truncate">{node.label}</span>
          </div>
        )
      },
      style: baseStyle,
      type: 'default',
      sourcePosition: Position.Right,
      targetPosition: Position.Left
    };

    if (node.parent_id) {
      flowNode.parentId = node.parent_id;
      flowNode.extent = 'parent';
    }
    if (isContainer) {
      // Containers must come before children in the array.
      flowNode.style = {
        ...baseStyle,
        // soften the label so it reads as a group container, not a node
        color: 'var(--theme-secondary, #9ca3af)'
      };
    }
    return flowNode;
  };

  // Containers must appear *before* their children for ReactFlow parentage to work.
  const flowNodes: FlowNode[] = [
    ...containers.map(renderNode),
    ...leaves.map(renderNode)
  ];

  const flowEdges: FlowEdge[] = (preview.edges ?? []).map((edge, idx) => ({
    id: `e-${idx}-${edge.source}-${edge.target}`,
    source: edge.source,
    target: edge.target,
    label: edge.label,
    // Smoothstep routes edges with right-angle bends instead of bezier
    // arcs — works well with the left/right handle positions and keeps
    // the diagram readable when many edges share endpoints.
    type: 'smoothstep',
    pathOptions: { borderRadius: 8 },
    markerEnd: { type: MarkerType.ArrowClosed, color: 'var(--theme-secondary, #9ca3af)' },
    style: { stroke: 'var(--theme-secondary, #9ca3af)', strokeWidth: 1.25 },
    labelStyle: { fontSize: 10, fill: 'var(--theme-secondary, #9ca3af)' },
    labelBgStyle: { fill: 'var(--theme-surface, #1f2937)', fillOpacity: 0.85 },
    labelBgPadding: [4, 2] as [number, number],
    labelBgBorderRadius: 3
  }));

  return { nodes: flowNodes, edges: flowEdges };
};

/**
 * StackTopologyPreview — read-only ReactFlow visualization of the provisioning
 * plan's resource topology. Embedded at 280×320 inside `ProvisioningPlanReview`,
 * expandable to a 70vh overlay for closer inspection.
 *
 * The diagram is intentionally non-interactive: the canonical edits happen via
 * "Modify in chat" or per-step Edit, not by dragging boxes around. Slice 5 may
 * add hover affordances; M1 keeps the surface read-only.
 */
export const StackTopologyPreview: React.FC<StackTopologyPreviewProps> = ({
  topology,
  width = 280,
  height = 320,
  expandable = true,
  className = ''
}) => {
  const [expanded, setExpanded] = useState(false);
  const { nodes, edges } = useMemo(() => buildTopologyFlowGraph(topology), [topology]);

  if (!topology || nodes.length === 0) {
    return (
      <div
        data-testid="stack-topology-preview-empty"
        className={`flex items-center justify-center bg-theme-surface border border-theme rounded text-theme-tertiary text-xs p-4 ${className}`}
        style={{ width, height }}
      >
        No topology preview available.
      </div>
    );
  }

  const containerStyle: React.CSSProperties = expanded
    ? { width: '100%', height: '70vh' }
    : { width, height };

  return (
    <div
      className={`relative bg-theme-surface border border-theme rounded overflow-hidden ${className}`}
      style={containerStyle}
      data-testid="stack-topology-preview"
    >
      {expandable && (
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          className="absolute top-2 right-2 z-10 p-1.5 rounded bg-theme-surface border border-theme text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover"
          aria-label={expanded ? 'Collapse topology' : 'Expand topology'}
          data-testid="stack-topology-expand-toggle"
        >
          {expanded ? <Minimize2 className="w-3.5 h-3.5" /> : <Maximize2 className="w-3.5 h-3.5" />}
        </button>
      )}
      <ReactFlow
        nodes={nodes}
        edges={edges}
        fitView
        nodesDraggable={false}
        nodesConnectable={false}
        elementsSelectable={false}
        proOptions={{ hideAttribution: true }}
      >
        <Background gap={16} />
        {expanded && <Controls showInteractive={false} />}
      </ReactFlow>
    </div>
  );
};

export default StackTopologyPreview;
