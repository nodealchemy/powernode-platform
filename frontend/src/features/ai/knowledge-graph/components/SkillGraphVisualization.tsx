import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
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
  Connection,
  type ReactFlowInstance,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { Wrench, Search, RefreshCw, Unlink } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Button } from '@/shared/components/ui/Button';
import { autoArrangeNodes } from '@/shared/utils/workflowLayout';
import { SkillNodeDetailPanel } from './SkillNodeDetailPanel';
import { SkillGraphStatisticsPanel } from './SkillGraphStatisticsPanel';
import { useSkillGraph, useCreateSkillEdge, useSyncSkills } from '../api/skillGraphApi';
import { SKILL_EDGE_DISPLAY } from '../types/skillGraph';
import type { SkillGraphNodeData, SkillEdgeRelation } from '../types/skillGraph';

const graphStyles = `
.sg-controls .react-flow__controls-button {
  background-color: var(--color-surface);
  border-color: var(--color-border);
  border-bottom-width: 1px;
  border-bottom-style: solid;
  fill: var(--color-text-primary);
  color: var(--color-text-primary);
}
.sg-controls .react-flow__controls-button:hover {
  background-color: var(--color-surface-hover);
}
.sg-controls .react-flow__controls-button svg {
  fill: var(--color-text-primary);
}
.react-flow__minimap-mask {
  fill: var(--color-bg, rgba(0,0,0,0.1));
  opacity: 0.6;
}
`;

const CATEGORY_ICONS: Record<string, string> = {
  productivity: '⚡',
  sales: '💼',
  customer_support: '🎧',
  product_management: '📋',
  marketing: '📢',
  legal: '⚖️',
  finance: '💰',
  data: '📊',
  enterprise_search: '🔍',
  bio_research: '🧬',
  skill_management: '🛠️',
};

function SkillGraphNode({ data }: { data: SkillGraphNodeData }) {
  const icon = CATEGORY_ICONS[data.category] || '🔧';
  const statusClass = data.status === 'active' ? 'bg-theme-success' : 'bg-theme-surface-secondary';

  return (
    <div className="px-3 py-2 rounded-lg border-2 border-theme bg-theme-surface shadow min-w-[200px] max-w-[240px]">
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <div className="flex items-center gap-2">
        <span className="text-lg flex-shrink-0">{icon}</span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <span className="font-medium text-theme-primary text-xs truncate">{data.label}</span>
            <span className={`w-2 h-2 rounded-full ${statusClass} flex-shrink-0`} />
          </div>
          <div className="text-[10px] text-theme-tertiary">
            {data.commandCount} cmds | {data.connectorCount} servers
          </div>
        </div>
        {data.dependencyCount > 0 && (
          <span className="px-1.5 py-0.5 text-[10px] rounded-full bg-theme-warning text-theme-warning flex-shrink-0">
            {data.dependencyCount} deps
          </span>
        )}
      </div>
      <Handle type="source" position={Position.Bottom} className="!bg-theme-border" />
    </div>
  );
}

const nodeTypes: NodeTypes = {
  skillNode: SkillGraphNode,
};

interface SkillGraphVisualizationProps {
  focusSkillId?: string;
  onNodeSelect?: (nodeId: string) => void;
  onViewSkill?: (skillId: string) => void;
}

export const SkillGraphVisualization: React.FC<SkillGraphVisualizationProps> = ({ focusSkillId, onNodeSelect: externalNodeSelect, onViewSkill }) => {
  const [loading, setLoading] = useState(true);
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [searchFilter, setSearchFilter] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string>('');
  const [showUnconnected, setShowUnconnected] = useState(true);
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([]);
  const [connectModal, setConnectModal] = useState<{ source: string; target: string } | null>(null);
  const [connectRelation, setConnectRelation] = useState<SkillEdgeRelation>('requires');
  const rfInstance = useRef<ReactFlowInstance | null>(null);

  const { data: graphData, isLoading: graphLoading } = useSkillGraph();
  const createEdge = useCreateSkillEdge();
  const syncSkills = useSyncSkills();

  const connectedNodeIds = useMemo(() => {
    if (!graphData?.edges) return new Set<string>();
    const ids = new Set<string>();
    for (const e of graphData.edges) {
      ids.add(e.source_skill_id);
      ids.add(e.target_skill_id);
    }
    return ids;
  }, [graphData]);

  const unconnectedCount = useMemo(() => {
    if (!graphData?.nodes) return 0;
    return graphData.nodes.filter(n => !connectedNodeIds.has(n.id)).length;
  }, [graphData, connectedNodeIds]);

  const categories = useMemo(() => {
    if (!graphData?.nodes) return [];
    const cats = new Set(graphData.nodes.map(n => n.category));
    return Array.from(cats).sort();
  }, [graphData]);

  const filteredNodes = useMemo(() => {
    if (!graphData?.nodes) return [];
    let filtered = graphData.nodes;
    if (!showUnconnected) {
      filtered = filtered.filter(n => connectedNodeIds.has(n.id));
    }
    if (searchFilter) {
      const q = searchFilter.toLowerCase();
      filtered = filtered.filter(n => n.name.toLowerCase().includes(q));
    }
    if (categoryFilter) {
      filtered = filtered.filter(n => n.category === categoryFilter);
    }
    return filtered;
  }, [graphData, searchFilter, categoryFilter, showUnconnected, connectedNodeIds]);

  useEffect(() => {
    if (graphLoading) {
      setLoading(true);
      return;
    }

    if (!graphData || filteredNodes.length === 0) {
      setNodes([]);
      setEdges([]);
      setLoading(false);
      return;
    }

    const nodeIdSet = new Set(filteredNodes.map(n => n.id));

    const flowNodes: Node[] = filteredNodes.map((node) => ({
      id: node.id,
      type: 'skillNode',
      data: {
        label: node.name,
        category: node.category,
        status: node.status,
        commandCount: node.command_count,
        connectorCount: node.connector_count,
        skillId: node.skill_id,
        dependencyCount: node.dependency_count,
      } satisfies SkillGraphNodeData,
      position: { x: 0, y: 0 },
    }));

    const flowEdges: Edge[] = (graphData.edges || [])
      .filter(edge => nodeIdSet.has(edge.source_skill_id) && nodeIdSet.has(edge.target_skill_id))
      .map((edge) => {
        const display = SKILL_EDGE_DISPLAY[edge.relation_type] || SKILL_EDGE_DISPLAY.requires;
        return {
          id: `skill-edge-${edge.id}`,
          source: edge.source_skill_id,
          target: edge.target_skill_id,
          label: display.label,
          type: 'default',
          animated: display.animated,
          markerEnd: { type: MarkerType.ArrowClosed, color: display.strokeColor },
          style: { stroke: display.strokeColor, strokeWidth: 2 },
          labelStyle: { fontSize: 9, fill: display.strokeColor },
        };
      });

    const arrangedNodes = autoArrangeNodes(flowNodes, flowEdges, {
      direction: 'TB',
      nodeWidth: 240,
      nodeHeight: 80,
      spacing: 100,
    });

    setNodes(arrangedNodes);
    setEdges(flowEdges);
    setLoading(false);

    // Fit viewport after layout changes (toggle, filter, search)
    setTimeout(() => {
      rfInstance.current?.fitView({ padding: 0.3 });
    }, 50);
  }, [graphData, filteredNodes, graphLoading, setNodes, setEdges]);

  // Focus on a specific skill node when focusSkillId is provided
  const hasFocused = useRef(false);
  useEffect(() => {
    if (!focusSkillId || hasFocused.current || loading || nodes.length === 0) return;

    const targetNode = nodes.find(
      (n) => (n.data as SkillGraphNodeData).skillId === focusSkillId || n.id === focusSkillId
    );
    if (!targetNode) return;

    hasFocused.current = true;
    setSelectedNodeId(targetNode.id);

    // Zoom to the node after a short delay to let ReactFlow settle
    setTimeout(() => {
      rfInstance.current?.fitView({
        nodes: [{ id: targetNode.id }],
        padding: 1.5,
        duration: 400,
      });
    }, 150);
  }, [focusSkillId, loading, nodes]);

  const onNodeClick = useCallback((_event: React.MouseEvent, node: Node) => {
    setSelectedNodeId(node.id);
    externalNodeSelect?.(node.id);
  }, [externalNodeSelect]);

  const onConnect = useCallback((connection: Connection) => {
    if (connection.source && connection.target) {
      setConnectModal({ source: connection.source, target: connection.target });
    }
  }, []);

  const handleCreateEdge = useCallback(() => {
    if (!connectModal) return;
    createEdge.mutate({
      source_skill_id: connectModal.source,
      target_skill_id: connectModal.target,
      relation_type: connectRelation,
    }, {
      onSuccess: () => setConnectModal(null),
    });
  }, [connectModal, connectRelation, createEdge]);

  return (
    <div className="space-y-4">
      <style>{graphStyles}</style>

      <SkillGraphStatisticsPanel nodes={graphData?.nodes || []} edges={graphData?.edges || []} />

      {/* Toolbar */}
      <Card className="p-4">
        <div className="flex items-center gap-3 flex-wrap">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
            <input
              type="text"
              value={searchFilter}
              onChange={(e) => setSearchFilter(e.target.value)}
              placeholder="Search skills..."
              className="w-full pl-8 pr-3 py-1.5 text-sm bg-theme-surface border border-theme rounded-md text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-1 focus:ring-theme-primary"
            />
          </div>

          <div className="flex items-center gap-1.5 flex-wrap">
            <button
              onClick={() => setCategoryFilter('')}
              className={`px-2.5 py-1 text-xs rounded-full transition-colors ${
                !categoryFilter ? 'bg-theme-interactive-primary text-theme-surface' : 'bg-theme-surface-secondary text-theme-secondary hover:bg-theme-surface-hover'
              }`}
            >
              All
            </button>
            {categories.map(cat => (
              <button
                key={cat}
                onClick={() => setCategoryFilter(cat === categoryFilter ? '' : cat)}
                className={`px-2.5 py-1 text-xs rounded-full transition-colors ${
                  categoryFilter === cat ? 'bg-theme-interactive-primary text-theme-surface' : 'bg-theme-surface-secondary text-theme-secondary hover:bg-theme-surface-hover'
                }`}
              >
                {CATEGORY_ICONS[cat] || '🔧'} {cat.replace(/_/g, ' ')}
              </button>
            ))}
          </div>

          {unconnectedCount > 0 && (
            <Button
              variant={showUnconnected ? 'primary' : 'secondary'}
              size="sm"
              onClick={() => setShowUnconnected(!showUnconnected)}
            >
              <Unlink className="h-3.5 w-3.5 mr-1" />
              {showUnconnected ? 'Hide' : 'Show'} unconnected ({unconnectedCount})
            </Button>
          )}

          <Button
            variant="secondary"
            size="sm"
            onClick={() => syncSkills.mutate()}
            disabled={syncSkills.isPending}
          >
            <RefreshCw className={`h-3.5 w-3.5 mr-1 ${syncSkills.isPending ? 'animate-spin' : ''}`} />
            Sync
          </Button>
        </div>
      </Card>

      {/* Graph */}
      {loading ? (
        <LoadingSpinner size="lg" className="py-12" message="Loading skill graph..." />
      ) : nodes.length === 0 ? (
        <EmptyState
          icon={Wrench}
          title="No connected skills found"
          description={unconnectedCount > 0
            ? `${unconnectedCount} unconnected skill${unconnectedCount !== 1 ? 's' : ''} hidden. Click "Show unconnected" to reveal them.`
            : 'The skill graph is empty. Sync skills to populate it.'}
        />
      ) : (
        <div className="relative h-[600px] rounded-lg border border-theme bg-theme-surface">
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onNodeClick={onNodeClick}
            onConnect={onConnect}
            onInit={(instance) => { rfInstance.current = instance; }}
            nodeTypes={nodeTypes}
            fitView
            fitViewOptions={{ padding: 0.3 }}
            minZoom={0.2}
            maxZoom={2}
          >
            <Background variant={BackgroundVariant.Dots} gap={16} size={1} />
            <Controls className="sg-controls" />
            <MiniMap
              nodeColor={() => {
                const style = getComputedStyle(document.documentElement);
                return style.getPropertyValue('--color-text-secondary').trim() || '#6b7280';
              }}
              maskColor="rgba(0,0,0,0.1)"
            />
          </ReactFlow>

          {/* Edge Legend */}
          <div className="absolute bottom-4 right-4 bg-theme-surface border border-theme rounded-lg p-3 shadow-lg z-10">
            <div className="text-[10px] font-semibold text-theme-primary mb-1.5">Edge Types</div>
            <div className="space-y-1">
              {Object.entries(SKILL_EDGE_DISPLAY).map(([key, config]) => (
                <div key={key} className="flex items-center gap-2">
                  <div className="w-4 h-0.5" style={{ backgroundColor: config.strokeColor }} />
                  <span className="text-[10px] text-theme-secondary">{config.label}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Node Detail Slide-over */}
      <SkillNodeDetailPanel
        nodeId={selectedNodeId}
        graphData={graphData || { nodes: [], edges: [] }}
        onClose={() => setSelectedNodeId(null)}
        onNodeSelect={setSelectedNodeId}
        onViewSkill={onViewSkill}
      />

      {/* Connection Modal */}
      {connectModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-theme-primary/40">
          <div className="bg-theme-surface border border-theme rounded-lg p-6 shadow-xl w-80">
            <h3 className="text-sm font-semibold text-theme-primary mb-4">Create Skill Edge</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-xs text-theme-secondary mb-1">Relation Type</label>
                <select
                  value={connectRelation}
                  onChange={(e) => setConnectRelation(e.target.value as SkillEdgeRelation)}
                  className="w-full px-3 py-1.5 text-sm bg-theme-surface border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-primary"
                >
                  {Object.entries(SKILL_EDGE_DISPLAY).map(([key, config]) => (
                    <option key={key} value={key}>{config.label} — {config.description}</option>
                  ))}
                </select>
              </div>
              <div className="flex justify-end gap-2">
                <Button variant="secondary" size="sm" onClick={() => setConnectModal(null)}>Cancel</Button>
                <Button
                  variant="primary"
                  size="sm"
                  onClick={handleCreateEdge}
                  disabled={createEdge.isPending}
                >
                  {createEdge.isPending ? 'Creating...' : 'Create'}
                </Button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
