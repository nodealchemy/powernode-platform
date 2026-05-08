import React, { useMemo, useState } from 'react';
import * as dagre from 'dagre';
import {
  ReactFlow,
  Background,
  Controls,
  MarkerType,
  Position,
  BaseEdge,
  EdgeLabelRenderer,
  getSmoothStepPath,
  useInternalNode,
  type Node as FlowNode,
  type Edge as FlowEdge,
  type EdgeProps,
  type InternalNode as RfInternalNode
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
// Sizes are tuned for the embedded preview. Widths chosen so the most
// common labels fit without truncation: "Compute node 1" / "Volume 1" /
// "SDWAN Gateway" / "Cloud provider". Heights stay at a 44px baseline
// to keep the diagram dense.
const NODE_STYLE: Record<TopologyNodeType, NodeStyleSpec> = {
  compute: {
    width: 168, height: 44,
    background: 'rgba(59, 130, 246, 0.10)', border: 'var(--theme-info, #3b82f6)',
    borderRadius: 10, borderStyle: 'solid', shape: 'rounded'
  },
  volume: {
    width: 116, height: 44,
    background: 'var(--theme-surface, #1f2937)', border: 'var(--theme-border, #4b5563)',
    borderRadius: 4, borderStyle: 'solid', shape: 'square'
  },
  database: {
    width: 168, height: 44,
    background: 'rgba(59, 130, 246, 0.10)', border: 'var(--theme-info, #3b82f6)',
    borderRadius: 22, borderStyle: 'solid', shape: 'cylinder'
  },
  cache: {
    width: 116, height: 44,
    background: 'rgba(234, 179, 8, 0.10)', border: 'var(--theme-warning, #eab308)',
    borderRadius: 8, borderStyle: 'solid', shape: 'hexagon'
  },
  network: {
    width: 240, height: 140,
    background: 'transparent', border: 'var(--theme-border, #4b5563)',
    borderRadius: 12, borderStyle: 'dashed', shape: 'rounded'
  },
  gateway: {
    width: 132, height: 44,
    background: 'rgba(34, 197, 94, 0.10)', border: 'var(--theme-success, #22c55e)',
    borderRadius: 10, borderStyle: 'solid', shape: 'diamond'
  },
  user_device: {
    width: 96, height: 44,
    background: 'var(--theme-surface, #1f2937)', border: 'var(--theme-border, #4b5563)',
    borderRadius: 22, borderStyle: 'solid', shape: 'rounded'
  },
  external_provider: {
    width: 132, height: 44,
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

/**
 * Floating-edge geometry: find where a straight line from the source node's
 * center to the target node's center crosses the source node's bounding
 * rectangle. Used by FloatingSmoothEdge to anchor edges at the closest
 * perimeter point rather than fixed handle positions.
 *
 * Algorithm: project the dx/dy direction onto the rectangle's aspect ratio
 * — whichever dimension's slope is exceeded first decides which side
 * (top/bottom vs left/right) is hit. Returns the absolute (x, y) of the
 * intersection plus the matching ReactFlow Position.
 */
const getNodeIntersection = (
  source: RfInternalNode,
  target: RfInternalNode
): { x: number; y: number; position: Position } => {
  const sw = source.measured?.width ?? source.width ?? 100;
  const sh = source.measured?.height ?? source.height ?? 40;
  const tw = target.measured?.width ?? target.width ?? 100;
  const th = target.measured?.height ?? target.height ?? 40;

  const sx = (source.internals.positionAbsolute?.x ?? source.position.x) + sw / 2;
  const sy = (source.internals.positionAbsolute?.y ?? source.position.y) + sh / 2;
  const tx = (target.internals.positionAbsolute?.x ?? target.position.x) + tw / 2;
  const ty = (target.internals.positionAbsolute?.y ?? target.position.y) + th / 2;

  const dx = tx - sx;
  const dy = ty - sy;

  // Avoid div-by-zero for stacked or coincident nodes.
  if (dx === 0 && dy === 0) {
    return { x: sx, y: sy, position: Position.Right };
  }

  const halfW = sw / 2;
  const halfH = sh / 2;

  // Compare slopes: which side of the source rect does the line hit first?
  const aspect = Math.abs(dy) * halfW - Math.abs(dx) * halfH;

  if (aspect < 0) {
    // Hits left or right edge first
    const xOff = halfW * Math.sign(dx);
    const yOff = (xOff * dy) / dx;
    return {
      x: sx + xOff,
      y: sy + yOff,
      position: dx > 0 ? Position.Right : Position.Left
    };
  }
  // Hits top or bottom edge first
  const yOff = halfH * Math.sign(dy);
  const xOff = dy === 0 ? 0 : (yOff * dx) / dy;
  return {
    x: sx + xOff,
    y: sy + yOff,
    position: dy > 0 ? Position.Bottom : Position.Top
  };
};

interface FloatingSmoothEdgeData extends Record<string, unknown> {
  routedLabel?: string;
}

const FloatingSmoothEdge: React.FC<EdgeProps<FlowEdge<FloatingSmoothEdgeData>>> = ({
  id,
  source,
  target,
  markerEnd,
  style,
  data,
  label
}) => {
  const sourceNode = useInternalNode(source);
  const targetNode = useInternalNode(target);

  if (!sourceNode || !targetNode) return null;

  const sourceIntersection = getNodeIntersection(sourceNode, targetNode);
  const targetIntersection = getNodeIntersection(targetNode, sourceNode);

  const [path, labelX, labelY] = getSmoothStepPath({
    sourceX: sourceIntersection.x,
    sourceY: sourceIntersection.y,
    sourcePosition: sourceIntersection.position,
    targetX: targetIntersection.x,
    targetY: targetIntersection.y,
    targetPosition: targetIntersection.position,
    borderRadius: 8
  });

  const text = (data?.routedLabel ?? label ?? '') as string;

  return (
    <>
      <BaseEdge id={id} path={path} markerEnd={markerEnd} style={style} />
      {text ? (
        <EdgeLabelRenderer>
          <div
            style={{
              position: 'absolute',
              transform: `translate(-50%, -50%) translate(${labelX}px, ${labelY}px)`,
              background: 'var(--theme-surface, #1f2937)',
              padding: '1px 4px',
              borderRadius: 3,
              fontSize: 10,
              color: 'var(--theme-secondary, #9ca3af)',
              pointerEvents: 'none'
            }}
            className="nodrag nopan"
          >
            {text}
          </div>
        </EdgeLabelRenderer>
      ) : null}
    </>
  );
};

const EDGE_TYPES = { floating: FloatingSmoothEdge };

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

  // Drop edges that just restate container→child or child→container
  // membership — the dashed parent border already conveys "this child is
  // inside this container", and the label ("lan", etc.) lands inside the
  // child node since the edge is tiny. Visual containment IS the
  // relationship; the explicit edge adds nothing.
  const nodeById = new Map(preview.nodes.map((n) => [n.id, n]));
  const isContainmentEdge = (sourceId: string, targetId: string): boolean => {
    const s = nodeById.get(sourceId);
    const t = nodeById.get(targetId);
    if (!s || !t) return false;
    return s.parent_id === targetId || t.parent_id === sourceId;
  };

  const flowEdges: FlowEdge[] = (preview.edges ?? [])
    .filter((edge) => !isContainmentEdge(edge.source, edge.target))
    .map((edge, idx) => ({
      id: `e-${idx}-${edge.source}-${edge.target}`,
      source: edge.source,
      target: edge.target,
      // Floating edges anchor at the closest perimeter point of each node
      // rather than fixed left/right handles — minimizes edge length when
      // source and target aren't horizontally aligned. Geometry in
      // FloatingSmoothEdge.
      type: 'floating',
      data: { routedLabel: edge.label },
      markerEnd: { type: MarkerType.ArrowClosed, color: 'var(--theme-secondary, #9ca3af)' },
      style: { stroke: 'var(--theme-secondary, #9ca3af)', strokeWidth: 1.25 }
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
      className={`relative bg-theme-surface border border-theme rounded overflow-hidden topology-preview-root ${className}`}
      style={containerStyle}
      data-testid="stack-topology-preview"
    >
      {/* Hide ReactFlow's decorative handle dots — the diagram is read-only
          (nodesConnectable=false) so the dots add no affordance, but they
          render at the edge connection points and visually conflict with
          the edge labels we draw at midpoints. Scoped to the topology
          preview wrapper so we don't affect other ReactFlow surfaces in
          the app (mission task graph, knowledge graph, etc). */}
      <style>{`
        .topology-preview-root .react-flow__handle {
          opacity: 0;
          pointer-events: none;
          width: 0;
          height: 0;
        }
      `}</style>
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
        edgeTypes={EDGE_TYPES}
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
