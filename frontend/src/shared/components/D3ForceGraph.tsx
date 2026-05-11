import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ReactFlow,
  Node,
  Edge,
  Background,
  BackgroundVariant,
  Controls,
  MiniMap,
  ReactFlowProvider,
  useNodesState,
  useEdgesState,
  Position
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import * as dagre from 'dagre';
import { Maximize2, Minimize2 } from 'lucide-react';

// Graph node data interface
export interface GraphNodeData {
  id: string;
  label: string;
  type?: string;
  enabled?: boolean;
  metadata?: Record<string, unknown>;
  [key: string]: unknown;
}

// Graph link interface
export interface GraphLink {
  source: string;
  target: string;
  type?: string;
  label?: string;
}

// Component props
interface D3ForceGraphProps {
  /** Array of nodes to display */
  nodes: GraphNodeData[];
  /** Array of links between nodes */
  links: GraphLink[];
  /** Callback when a node is clicked */
  onNodeClick?: (node: GraphNodeData) => void;
  /** Custom node renderer */
  nodeRenderer?: (node: GraphNodeData) => React.ReactNode;
  /** Graph direction: 'TB' (top-bottom) or 'LR' (left-right) */
  direction?: 'TB' | 'LR';
  /** Height of the graph container */
  height?: number | string;
  /** Show mini map */
  showMiniMap?: boolean;
  /** Show controls */
  showControls?: boolean;
  /** Show background grid */
  showBackground?: boolean;
  /** Optional className */
  className?: string;
  /** Node width for layout calculation */
  nodeWidth?: number;
  /** Node height for layout calculation */
  nodeHeight?: number;
  /** Spacing between nodes */
  spacing?: number;
  /** Whether to allow fullscreen mode */
  allowFullscreen?: boolean;
}

/**
 * Custom node component for the graph
 */
const GraphNode: React.FC<{
  data: GraphNodeData & { customRenderer?: (node: GraphNodeData) => React.ReactNode };
}> = ({ data }) => {
  if (data.customRenderer) {
    return <>{data.customRenderer(data)}</>;
  }

  const bgColor = data.enabled !== false ? 'bg-theme-interactive-primary' : 'bg-theme-background-secondary';
  const textColor = 'text-white';

  return (
    <div
      className={`px-4 py-2 rounded-lg shadow-md border border-theme ${bgColor} ${textColor} min-w-[120px] text-center`}
    >
      <div className="font-medium text-sm truncate max-w-[150px]">{data.label}</div>
      {data.type && (
        <div className="text-xs opacity-75 mt-1">{data.type}</div>
      )}
    </div>
  );
};

const nodeTypes = {
  graphNode: GraphNode
};

/**
 * Layout nodes using dagre algorithm
 */
function layoutNodes(
  graphNodes: GraphNodeData[],
  graphLinks: GraphLink[],
  options: {
    direction: 'TB' | 'LR';
    nodeWidth: number;
    nodeHeight: number;
    spacing: number;
  }
): Node[] {
  if (graphNodes.length === 0) return [];

  const { direction, nodeWidth, nodeHeight, spacing } = options;

  const g = new dagre.graphlib.Graph({ compound: false, multigraph: false });

  g.setGraph({
    rankdir: direction,
    align: 'UL',
    nodesep: spacing,
    edgesep: spacing / 2,
    ranksep: spacing * 1.5,
    marginx: 20,
    marginy: 20
  });

  g.setDefaultEdgeLabel(() => ({}));

  // Add nodes
  graphNodes.forEach((node) => {
    g.setNode(node.id, {
      width: nodeWidth,
      height: nodeHeight,
      label: node.id
    });
  });

  // Add edges
  graphLinks.forEach((link) => {
    if (g.hasNode(link.source) && g.hasNode(link.target)) {
      g.setEdge(link.source, link.target);
    }
  });

  // Run layout
  dagre.layout(g);

  // Extract positions
  return graphNodes.map((node) => {
    const nodeData = g.node(node.id);
    const isHorizontal = direction === 'LR';

    return {
      id: node.id,
      type: 'graphNode',
      position: {
        x: nodeData.x - nodeWidth / 2,
        y: nodeData.y - nodeHeight / 2
      },
      data: node,
      sourcePosition: isHorizontal ? Position.Right : Position.Bottom,
      targetPosition: isHorizontal ? Position.Left : Position.Top
    };
  });
}

/**
 * Convert graph links to ReactFlow edges
 */
function createEdges(links: GraphLink[]): Edge[] {
  return links.map((link, index) => ({
    id: `edge-${link.source}-${link.target}-${index}`,
    source: link.source,
    target: link.target,
    type: 'smoothstep',
    animated: true,
    style: { stroke: 'var(--color-border)', strokeWidth: 2 },
    markerEnd: {
      type: 'arrowclosed' as const,
      width: 8,
      height: 8,
      color: 'var(--color-border)'
    },
    label: link.label,
    labelStyle: { fontSize: 10, fill: 'var(--color-text-secondary)' }
  }));
}

/**
 * D3ForceGraph - A force-directed graph visualization component
 *
 * Uses ReactFlow with dagre layout for displaying dependency trees,
 * module relationships, and other graph structures.
 *
 * @example
 * ```tsx
 * <D3ForceGraph
 *   nodes={[
 *     { id: '1', label: 'Module A', type: 'config' },
 *     { id: '2', label: 'Module B', type: 'instance' }
 *   ]}
 *   links={[
 *     { source: '1', target: '2', type: 'requires' }
 *   ]}
 *   onNodeClick={(node) => console.log('Clicked:', node)}
 *   height={400}
 * />
 * ```
 */
const D3ForceGraphInner: React.FC<D3ForceGraphProps> = ({
  nodes: graphNodes,
  links,
  onNodeClick,
  nodeRenderer,
  direction = 'TB',
  height = 400,
  showMiniMap = true,
  showControls = true,
  showBackground = true,
  className = '',
  nodeWidth = 160,
  nodeHeight = 60,
  spacing = 80,
  allowFullscreen = true
}) => {
  const [isFullscreen, setIsFullscreen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Layout nodes
  const layoutedNodes = useMemo(() => {
    const nodes = layoutNodes(graphNodes, links, {
      direction,
      nodeWidth,
      nodeHeight,
      spacing
    });

    // Add custom renderer to node data if provided
    if (nodeRenderer) {
      return nodes.map((node) => ({
        ...node,
        data: {
          ...node.data,
          customRenderer: nodeRenderer
        }
      }));
    }

    return nodes;
  }, [graphNodes, links, direction, nodeWidth, nodeHeight, spacing, nodeRenderer]);

  // Create edges
  const layoutedEdges = useMemo(() => createEdges(links), [links]);

  // ReactFlow state
  const [nodes, setNodes, onNodesChange] = useNodesState(layoutedNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(layoutedEdges);

  // Update nodes when input changes
  useEffect(() => {
    setNodes(layoutedNodes);
  }, [layoutedNodes, setNodes]);

  // Update edges when input changes
  useEffect(() => {
    setEdges(layoutedEdges);
  }, [layoutedEdges, setEdges]);

  // Handle node click
  const handleNodeClick = useCallback(
    (_event: React.MouseEvent, node: Node) => {
      if (onNodeClick) {
        onNodeClick(node.data as GraphNodeData);
      }
    },
    [onNodeClick]
  );

  // Toggle fullscreen
  const toggleFullscreen = useCallback(() => {
    if (!containerRef.current) return;

    if (!isFullscreen) {
      if (containerRef.current.requestFullscreen) {
        containerRef.current.requestFullscreen();
      }
    } else {
      if (document.exitFullscreen) {
        document.exitFullscreen();
      }
    }
  }, [isFullscreen]);

  // Track fullscreen state
  useEffect(() => {
    const handleFullscreenChange = () => {
      setIsFullscreen(document.fullscreenElement === containerRef.current);
    };

    document.addEventListener('fullscreenchange', handleFullscreenChange);
    return () => document.removeEventListener('fullscreenchange', handleFullscreenChange);
  }, []);

  const containerStyle = useMemo(
    () => ({
      height: isFullscreen ? '100vh' : typeof height === 'number' ? `${height}px` : height,
      width: '100%'
    }),
    [height, isFullscreen]
  );

  return (
    <div
      ref={containerRef}
      className={`relative border border-theme rounded-lg overflow-hidden bg-theme-background ${className}`}
      style={containerStyle}
    >
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onNodeClick={handleNodeClick}
        nodeTypes={nodeTypes}
        fitView
        fitViewOptions={{
          padding: 0.2,
          maxZoom: 1.5,
          minZoom: 0.3
        }}
        nodesDraggable={true}
        nodesConnectable={false}
        elementsSelectable={true}
        panOnDrag={true}
        zoomOnScroll={true}
        className="bg-theme-background"
      >
        {showBackground && (
          <Background
            variant={BackgroundVariant.Dots}
            gap={20}
            size={1}
            color="var(--color-border)"
          />
        )}

        {showControls && (
          <Controls
            className="bg-theme-surface border border-theme"
            showInteractive={false}
          />
        )}

        {showMiniMap && graphNodes.length > 5 && (
          <MiniMap
            style={{
              backgroundColor: 'var(--color-surface)',
              border: '1px solid var(--color-border)'
            }}
            nodeColor="var(--color-primary-500)"
            maskColor="rgba(0, 0, 0, 0.1)"
          />
        )}
      </ReactFlow>

      {/* Fullscreen toggle button */}
      {allowFullscreen && (
        <button
          onClick={toggleFullscreen}
          className="absolute top-2 right-2 p-2 bg-theme-surface border border-theme rounded-lg hover:bg-theme-surface-hover transition-colors z-10"
          title={isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}
        >
          {isFullscreen ? (
            <Minimize2 className="w-4 h-4 text-theme-secondary" />
          ) : (
            <Maximize2 className="w-4 h-4 text-theme-secondary" />
          )}
        </button>
      )}

      {/* Empty state */}
      {graphNodes.length === 0 && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="text-center text-theme-secondary">
            <p>No data to display</p>
          </div>
        </div>
      )}
    </div>
  );
};

/**
 * D3ForceGraph with ReactFlowProvider wrapper
 */
export const D3ForceGraph: React.FC<D3ForceGraphProps> = (props) => {
  return (
    <ReactFlowProvider>
      <D3ForceGraphInner {...props} />
    </ReactFlowProvider>
  );
};

/**
 * Hook for building graph data from module dependencies
 */
export function useGraphData<T extends { id: string; name: string; enabled?: boolean }>(
  items: T[],
  getDependencies: (item: T) => string[],
  getType?: (item: T) => string
): { nodes: GraphNodeData[]; links: GraphLink[] } {
  return useMemo(() => {
    const nodes: GraphNodeData[] = items.map((item) => ({
      id: item.id,
      label: item.name,
      type: getType?.(item),
      enabled: item.enabled
    }));

    const itemIds = new Set(items.map((item) => item.id));
    const links: GraphLink[] = [];

    items.forEach((item) => {
      const deps = getDependencies(item);
      deps.forEach((depId) => {
        if (itemIds.has(depId)) {
          links.push({
            source: item.id,
            target: depId,
            type: 'depends'
          });
        }
      });
    });

    return { nodes, links };
  }, [items, getDependencies, getType]);
}
