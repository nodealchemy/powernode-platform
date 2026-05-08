import React, { useMemo, useState } from 'react';
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

// Region column geometry. Containers and leaves stack within a column; the
// column width grows if a region's grid needs more columns than baseline.
const REGION_COL_BASE_WIDTH = 320;
const REGION_GUTTER = 32;
const ROW_HEIGHT = 60;
// Children inside a `network` container — laid out as a compact grid. Cell
// dimensions must fit the largest child-class node type (compute @ 116×40)
// plus a small gutter for breathing room between siblings; otherwise nodes
// overlap horizontally or vertically inside the parent box.
const CHILD_PADDING = 12;
const CHILD_COLS = 2;
const CHILD_COL_WIDTH = 132;
const CHILD_ROW_HEIGHT = 56;
const CHILD_HEADER_OFFSET = 26;

/**
 * Build a ReactFlow node + edge graph from the backend topology preview.
 *
 * Layout heuristic: arrange regions horizontally, nodes within a region
 * stacked vertically. Container nodes (`type=network`) are emitted first and
 * receive subgraph children via `parentId`. The MVP layout is intentionally
 * deterministic — slice 5 may swap in dagre, but for ≤20-node previews the
 * simple grid keeps the diagram legible without an extra dependency.
 */
export const buildTopologyFlowGraph = (
  preview: TopologyPreview | null | undefined
): { nodes: FlowNode[]; edges: FlowEdge[] } => {
  if (!preview || !Array.isArray(preview.nodes) || preview.nodes.length === 0) {
    return { nodes: [], edges: [] };
  }

  const regionToIndex = new Map<string, number>();
  preview.regions.forEach((r) => {
    if (!regionToIndex.has(r.id)) regionToIndex.set(r.id, regionToIndex.size);
  });

  // Container nodes don't share the regional column layout — they wrap children.
  const containers = preview.nodes.filter((n) => n.type === 'network');
  const leaves = preview.nodes.filter((n) => n.type !== 'network');

  const positions = new Map<string, { x: number; y: number }>();
  const containerChildCounts = new Map<string, number>();
  const perRegionLeafCount = new Map<string, number>();

  // Pre-pass: count children per container so we can size each container to
  // fit its grid before placing them. Without this, children spill out of
  // fixed-size containers and overlap with sibling region content.
  leaves.forEach((node) => {
    if (node.parent_id) {
      containerChildCounts.set(node.parent_id, (containerChildCounts.get(node.parent_id) ?? 0) + 1);
    }
  });

  const containerSize = (containerId: string): { width: number; height: number } => {
    const childCount = containerChildCounts.get(containerId) ?? 0;
    const cols = Math.min(CHILD_COLS, Math.max(1, childCount));
    const rows = Math.max(1, Math.ceil(childCount / CHILD_COLS));
    return {
      width: cols * CHILD_COL_WIDTH + CHILD_PADDING * 2,
      height: rows * CHILD_ROW_HEIGHT + CHILD_HEADER_OFFSET + CHILD_PADDING
    };
  };

  // Containers laid out first across regions so they "own" their slots. The
  // column width grows with the widest container to keep regions visually
  // separated.
  const regionColumnWidth = new Map<string, number>();
  containers.forEach((node, idx) => {
    const regionId = node.region_id ?? `__container_${idx}`;
    if (!regionToIndex.has(regionId)) regionToIndex.set(regionId, regionToIndex.size);
    const size = containerSize(node.id);
    const current = regionColumnWidth.get(regionId) ?? REGION_COL_BASE_WIDTH;
    regionColumnWidth.set(regionId, Math.max(current, size.width + REGION_GUTTER));
  });

  const regionXOffset = (regionIdx: number, regionId: string): number => {
    let x = 0;
    for (let i = 0; i < regionIdx; i += 1) {
      const id = [...regionToIndex.entries()].find(([, idx]) => idx === i)?.[0];
      x += id ? (regionColumnWidth.get(id) ?? REGION_COL_BASE_WIDTH) : REGION_COL_BASE_WIDTH;
    }
    void regionId;
    return x;
  };

  containers.forEach((node, idx) => {
    const regionId = node.region_id ?? `__container_${idx}`;
    const regionIdx = regionToIndex.get(regionId) ?? idx;
    positions.set(node.id, { x: regionXOffset(regionIdx, regionId), y: 0 });
  });

  leaves.forEach((node) => {
    if (node.parent_id) {
      // Child of a container — laid out as a CHILD_COLS-wide grid inside
      // its parent's bounding box.
      const within = (perRegionLeafCount.get(`child:${node.parent_id}`) ?? 0);
      perRegionLeafCount.set(`child:${node.parent_id}`, within + 1);
      const col = within % CHILD_COLS;
      const row = Math.floor(within / CHILD_COLS);
      positions.set(node.id, {
        x: CHILD_PADDING + col * CHILD_COL_WIDTH,
        y: CHILD_HEADER_OFFSET + row * CHILD_ROW_HEIGHT
      });
      return;
    }
    const regionId = node.region_id ?? '__default';
    if (!regionToIndex.has(regionId)) regionToIndex.set(regionId, regionToIndex.size);
    const regionIdx = regionToIndex.get(regionId) ?? 0;
    const within = perRegionLeafCount.get(`region:${regionId}`) ?? 0;
    perRegionLeafCount.set(`region:${regionId}`, within + 1);
    // Leaves below the region's containers — the tallest container in this
    // region defines where leaves start so we don't sit on top of containers.
    const containersInRegion = containers.filter((c) => (c.region_id ?? '') === regionId);
    const tallestContainer = containersInRegion.reduce(
      (h, c) => Math.max(h, containerSize(c.id).height),
      0
    );
    positions.set(node.id, {
      x: regionXOffset(regionIdx, regionId) + 8,
      y: tallestContainer + 24 + within * ROW_HEIGHT
    });
  });

  const renderNode = (node: TopologyNode): FlowNode => {
    const style = NODE_STYLE[node.type] ?? NODE_STYLE.compute;
    const Icon = NODE_ICON[node.type] ?? Cpu;
    const pos = positions.get(node.id) ?? { x: 0, y: 0 };
    const isContainer = node.type === 'network';

    // Containers grow to fit their children — see containerSize().
    const dims = isContainer
      ? containerSize(node.id)
      : { width: style.width, height: style.height };

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
