import React, { useState, useEffect, useCallback } from 'react';
import {
  ReactFlow,
  MiniMap,
  Controls,
  Background,
  useNodesState,
  useEdgesState,
  Node,
  Edge,
  MarkerType,
  BackgroundVariant,
  NodeTypes,
  Handle,
  Position,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { Circle, FileText, Bot, Wrench, BookOpen, Brain, Lightbulb } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { autoArrangeNodes } from '@/shared/utils/workflowLayout';
import { GraphSearch } from './GraphSearch';
import { NodeDetailPanel } from './NodeDetailPanel';
import { GraphStatisticsPanel } from './GraphStatisticsPanel';
import { useKnowledgeNodes, useKnowledgeEdges } from '../api/knowledgeGraphApi';
import type { EntityType, SearchMode } from '../types/knowledgeGraph';

// Theme-aware ReactFlow styles (reuse pattern from AgentConnectionsGraph)
const graphStyles = `
.kg-controls .react-flow__controls-button {
  background-color: var(--color-surface);
  border-color: var(--color-border);
  border-bottom-width: 1px;
  border-bottom-style: solid;
  fill: var(--color-text-primary);
  color: var(--color-text-primary);
}
.kg-controls .react-flow__controls-button:hover {
  background-color: var(--color-surface-hover);
}
.kg-controls .react-flow__controls-button svg {
  fill: var(--color-text-primary);
}
.react-flow__minimap-mask {
  fill: var(--color-bg, rgba(0,0,0,0.1));
  opacity: 0.6;
}
`;

const ENTITY_ICONS: Record<EntityType, React.FC<{ className?: string }>> = {
  concept: Brain,
  entity: Circle,
  document: FileText,
  agent: Bot,
  skill: Wrench,
  context: BookOpen,
  learning: Lightbulb,
};

const ENTITY_COLORS: Record<EntityType, string> = {
  concept: 'text-theme-info',
  entity: 'text-theme-success',
  document: 'text-theme-warning',
  agent: 'text-theme-interactive-primary',
  skill: 'text-theme-accent',
  context: 'text-theme-error',
  learning: 'text-theme-success',
};

const ENTITY_BORDER_COLORS: Record<EntityType, string> = {
  concept: 'border-theme-info',
  entity: 'border-theme-success',
  document: 'border-theme-warning',
  agent: 'border-theme-interactive-primary',
  skill: 'border-theme',
  context: 'border-theme-error',
  learning: 'border-theme-success',
};

interface KGNodeData {
  label: string;
  entityType: EntityType;
  description: string;
  edgeCount: number;
  selected?: boolean;
  [key: string]: unknown;
}

function KGNode({ data }: { data: KGNodeData }) {
  const Icon = ENTITY_ICONS[data.entityType] || Circle;
  const colorClass = ENTITY_COLORS[data.entityType] || 'text-theme-primary';
  const borderClass = ENTITY_BORDER_COLORS[data.entityType] || 'border-theme';

  return (
    <div className={`px-3 py-2 rounded-lg border-2 ${borderClass} bg-theme-surface shadow min-w-[120px] max-w-[180px]`}>
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <div className="flex items-center gap-2">
        <Icon className={`h-4 w-4 ${colorClass} flex-shrink-0`} />
        <div className="min-w-0">
          <div className="font-medium text-theme-primary text-xs truncate">{data.label}</div>
          <div className="text-[10px] text-theme-tertiary">{data.entityType} | {data.edgeCount} edges</div>
        </div>
      </div>
      <Handle type="source" position={Position.Bottom} className="!bg-theme-border" />
    </div>
  );
}

const nodeTypes: NodeTypes = {
  kgNode: KGNode,
};

export const KnowledgeGraphVisualization: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [searchFilter, setSearchFilter] = useState<string>('');
  const [entityFilter, setEntityFilter] = useState<EntityType | undefined>(undefined);
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([]);

  const { data: nodesData, isLoading: nodesLoading } = useKnowledgeNodes({
    per_page: 100,
    entity_type: entityFilter,
    search: searchFilter || undefined,
  });
  const { data: edgesData, isLoading: edgesLoading } = useKnowledgeEdges({ per_page: 500 });

  useEffect(() => {
    if (nodesLoading || edgesLoading) {
      setLoading(true);
      return;
    }

    const knowledgeNodes = nodesData?.data || [];
    const knowledgeEdges = edgesData?.data || [];

    if (knowledgeNodes.length === 0) {
      setNodes([]);
      setEdges([]);
      setLoading(false);
      return;
    }

    const nodeIdSet = new Set(knowledgeNodes.map((n) => n.id));

    const flowNodes: Node[] = knowledgeNodes.map((node) => ({
      id: node.id,
      type: 'kgNode',
      data: {
        label: node.name,
        entityType: node.entity_type,
        description: node.description,
        edgeCount: node.edge_count,
      } satisfies KGNodeData,
      position: { x: 0, y: 0 },
    }));

    const flowEdges: Edge[] = knowledgeEdges
      .filter((edge) => nodeIdSet.has(edge.source_id) && nodeIdSet.has(edge.target_id))
      .map((edge, idx) => ({
        id: `edge-${idx}-${edge.id}`,
        source: edge.source_id,
        target: edge.target_id,
        label: edge.relation_type.replace('_', ' '),
        type: 'default',
        animated: edge.relation_type === 'depends_on',
        markerEnd: { type: MarkerType.ArrowClosed, color: 'var(--color-text-tertiary)' },
        style: { stroke: 'var(--color-text-tertiary)', strokeWidth: 1.5 },
        labelStyle: { fontSize: 9, fill: 'var(--color-text-tertiary)' },
      }));

    const arrangedNodes = autoArrangeNodes(flowNodes, flowEdges, {
      direction: 'TB',
      nodeWidth: 180,
      nodeHeight: 60,
      spacing: 80,
    });

    setNodes(arrangedNodes);
    setEdges(flowEdges);
    setLoading(false);
  }, [nodesData, edgesData, nodesLoading, edgesLoading, setNodes, setEdges]);

  const onNodeClick = useCallback((_event: React.MouseEvent, node: Node) => {
    setSelectedNodeId(node.id);
  }, []);

  const handleSearch = useCallback((query: string, entityType?: EntityType, _mode?: SearchMode) => {
    setSearchFilter(query);
    setEntityFilter(entityType);
  }, []);

  const handleClearSearch = useCallback(() => {
    setSearchFilter('');
    setEntityFilter(undefined);
  }, []);

  return (
    <div className="space-y-4">
      <style>{graphStyles}</style>

      {/* Statistics */}
      <GraphStatisticsPanel />

      {/* Search */}
      <Card className="p-4">
        <GraphSearch onSearch={handleSearch} onClear={handleClearSearch} />
      </Card>

      {/* Graph */}
      {loading ? (
        <LoadingSpinner size="lg" className="py-12" message="Loading knowledge graph..." />
      ) : nodes.length === 0 ? (
        <EmptyState
          icon={Brain}
          title="No nodes found"
          description="The knowledge graph is empty or no nodes match your search criteria."
        />
      ) : (
        <div className="h-[600px] rounded-lg border border-theme bg-theme-surface">
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onNodeClick={onNodeClick}
            nodeTypes={nodeTypes}
            fitView
            fitViewOptions={{ padding: 0.3 }}
            minZoom={0.2}
            maxZoom={2}
          >
            <Background variant={BackgroundVariant.Dots} gap={16} size={1} />
            <Controls className="kg-controls" />
            <MiniMap
              nodeColor={(node) => {
                const style = getComputedStyle(document.documentElement);
                const data = node.data as KGNodeData | undefined;
                const entityType = data?.entityType;
                switch (entityType) {
                  case 'concept': return style.getPropertyValue('--color-info').trim() || '#3b82f6';
                  case 'entity': return style.getPropertyValue('--color-success').trim() || '#14b8a6';
                  case 'document': return style.getPropertyValue('--color-warning').trim() || '#f97316';
                  case 'agent': return style.getPropertyValue('--color-interactive-primary').trim() || '#a855f7';
                  case 'skill': return style.getPropertyValue('--color-text-secondary').trim() || '#6b7280';
                  case 'context': return style.getPropertyValue('--color-error').trim() || '#ef4444';
                  case 'learning': return style.getPropertyValue('--color-success').trim() || '#14b8a6';
                  default: return style.getPropertyValue('--color-text-secondary').trim() || '#6b7280';
                }
              }}
              maskColor="rgba(0,0,0,0.1)"
            />
          </ReactFlow>
        </div>
      )}

      {/* Node Detail Slide-over */}
      <NodeDetailPanel
        nodeId={selectedNodeId}
        onClose={() => setSelectedNodeId(null)}
        onNodeSelect={setSelectedNodeId}
      />
    </div>
  );
};
