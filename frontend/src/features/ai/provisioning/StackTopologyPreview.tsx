import React, { useMemo, useState } from 'react';
import {
  ReactFlow,
  Background,
  Controls,
  MarkerType,
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
const NODE_STYLE: Record<TopologyNodeType, NodeStyleSpec> = {
  compute: {
    width: 160, height: 64,
    background: 'rgba(59, 130, 246, 0.10)', border: 'var(--theme-info, #3b82f6)',
    borderRadius: 12, borderStyle: 'solid', shape: 'rounded'
  },
  volume: {
    width: 96, height: 64,
    background: 'var(--theme-surface, #1f2937)', border: 'var(--theme-border, #4b5563)',
    borderRadius: 4, borderStyle: 'solid', shape: 'square'
  },
  database: {
    width: 160, height: 64,
    background: 'rgba(59, 130, 246, 0.10)', border: 'var(--theme-info, #3b82f6)',
    borderRadius: 32, borderStyle: 'solid', shape: 'cylinder'
  },
  cache: {
    width: 120, height: 64,
    background: 'rgba(234, 179, 8, 0.10)', border: 'var(--theme-warning, #eab308)',
    borderRadius: 8, borderStyle: 'solid', shape: 'hexagon'
  },
  network: {
    width: 240, height: 140,
    background: 'transparent', border: 'var(--theme-border, #4b5563)',
    borderRadius: 12, borderStyle: 'dashed', shape: 'rounded'
  },
  gateway: {
    width: 96, height: 96,
    background: 'rgba(34, 197, 94, 0.10)', border: 'var(--theme-success, #22c55e)',
    borderRadius: 12, borderStyle: 'solid', shape: 'diamond'
  },
  user_device: {
    width: 56, height: 56,
    background: 'var(--theme-surface, #1f2937)', border: 'var(--theme-border, #4b5563)',
    borderRadius: 28, borderStyle: 'solid', shape: 'circle'
  },
  external_provider: {
    width: 144, height: 56,
    background: 'var(--theme-surface, #1f2937)', border: 'var(--theme-border, #4b5563)',
    borderRadius: 8, borderStyle: 'solid', shape: 'rounded'
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

const REGION_COL_WIDTH = 280;
const ROW_HEIGHT = 110;

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
  const perRegionCount = new Map<string, number>();

  // Containers laid out first across regions so they "own" their slots.
  containers.forEach((node, idx) => {
    const regionId = node.region_id ?? `__container_${idx}`;
    if (!regionToIndex.has(regionId)) regionToIndex.set(regionId, regionToIndex.size);
    const regionIdx = regionToIndex.get(regionId) ?? idx;
    positions.set(node.id, { x: regionIdx * REGION_COL_WIDTH, y: 0 });
  });

  leaves.forEach((node) => {
    if (node.parent_id) {
      // child of a container — local coords inside the container
      const within = perRegionCount.get(node.parent_id) ?? 0;
      perRegionCount.set(node.parent_id, within + 1);
      positions.set(node.id, { x: 16 + (within % 2) * 110, y: 24 + Math.floor(within / 2) * 56 });
      return;
    }
    const regionId = node.region_id ?? '__default';
    if (!regionToIndex.has(regionId)) regionToIndex.set(regionId, regionToIndex.size);
    const regionIdx = regionToIndex.get(regionId) ?? 0;
    const within = perRegionCount.get(`region:${regionId}`) ?? 0;
    perRegionCount.set(`region:${regionId}`, within + 1);
    positions.set(node.id, {
      x: regionIdx * REGION_COL_WIDTH + 8,
      y: 160 + within * ROW_HEIGHT // leave room above for any container
    });
  });

  const renderNode = (node: TopologyNode): FlowNode => {
    const style = NODE_STYLE[node.type] ?? NODE_STYLE.compute;
    const Icon = NODE_ICON[node.type] ?? Cpu;
    const pos = positions.get(node.id) ?? { x: 0, y: 0 };
    const isContainer = node.type === 'network';

    const baseStyle: React.CSSProperties = {
      width: style.width,
      height: style.height,
      background: style.background,
      border: `${style.borderStyle === 'dashed' ? '1px dashed' : '1.5px solid'} ${style.border}`,
      borderRadius: style.borderRadius,
      padding: 0,
      color: 'var(--theme-primary, #f9fafb)'
    };

    const flowNode: FlowNode = {
      id: node.id,
      position: pos,
      data: {
        label: (
          <div className="flex items-center gap-1.5 px-2 w-full justify-center" style={{ minWidth: 0 }}>
            <Icon className="w-4 h-4 flex-shrink-0" />
            <span className="text-xs truncate">{node.label}</span>
          </div>
        )
      },
      style: baseStyle,
      type: 'default'
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
    markerEnd: { type: MarkerType.ArrowClosed },
    labelStyle: { fontSize: 10, fill: 'currentColor' }
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
