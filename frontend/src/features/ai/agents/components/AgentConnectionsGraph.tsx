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
import { useNavigate } from 'react-router-dom';
import { Bot, Users, Server, Database } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { autoArrangeNodes } from '@/shared/utils/workflowLayout';
import { agentConnectionsApi } from '../services/agentConnectionsApi';
import type { AgentConnectionNode, AgentConnectionEdge, AgentConnectionsSummary } from '../services/agentConnectionsApi';

// Theme-aware ReactFlow styles
const graphStyles = `
.connections-controls .react-flow__controls-button {
  background-color: var(--color-surface);
  border-color: var(--color-border);
  border-bottom-width: 1px;
  border-bottom-style: solid;
  fill: var(--color-text-primary);
  color: var(--color-text-primary);
}
.connections-controls .react-flow__controls-button:hover {
  background-color: var(--color-surface-hover);
}
.connections-controls .react-flow__controls-button svg {
  fill: var(--color-text-primary);
}
.react-flow__minimap-mask {
  fill: var(--color-bg, rgba(0,0,0,0.1));
  opacity: 0.6;
}
`;

interface ConnectionNodeData {
  label: string;
  nodeType: string;
  status: string;
  metadata: Record<string, unknown>;
  selected?: boolean;
  [key: string]: unknown;
}

// Custom node for the selected agent (center)
function AgentNode({ data }: { data: ConnectionNodeData }) {
  return (
    <div className="px-4 py-3 rounded-lg border-2 border-theme-info bg-theme-surface shadow-lg min-w-[140px]">
      <Handle type="target" position={Position.Top} className="!bg-theme-info" />
      <div className="flex items-center gap-2">
        <Bot className="h-5 w-5 text-theme-info" />
        <div>
          <div className="font-semibold text-theme-primary text-sm">{data.label}</div>
          <div className="text-xs text-theme-tertiary">{String(data.metadata?.agent_type || 'agent')}</div>
        </div>
      </div>
      <Handle type="source" position={Position.Bottom} className="!bg-theme-info" />
    </div>
  );
}

// Custom node for peer agents
function PeerAgentNode({ data }: { data: ConnectionNodeData }) {
  const statusColor = data.status === 'active' ? 'text-theme-success' : 'text-theme-tertiary';
  return (
    <div className="px-3 py-2 rounded-lg border border-theme bg-theme-surface shadow min-w-[120px]">
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <div className="flex items-center gap-2">
        <Bot className={`h-4 w-4 ${statusColor}`} />
        <div>
          <div className="font-medium text-theme-primary text-xs">{data.label}</div>
          <div className="text-[10px] text-theme-tertiary">{String(data.metadata?.agent_type || 'peer')}</div>
        </div>
      </div>
      <Handle type="source" position={Position.Bottom} className="!bg-theme-border" />
    </div>
  );
}

// Custom node for teams
function TeamNode({ data }: { data: ConnectionNodeData }) {
  return (
    <div className="px-3 py-2 rounded-lg border border-theme bg-theme-surface shadow min-w-[120px]">
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <div className="flex items-center gap-2">
        <Users className="h-4 w-4 text-theme-accent" />
        <div>
          <div className="font-medium text-theme-primary text-xs">{data.label}</div>
          <div className="text-[10px] text-theme-tertiary">
            {data.metadata?.member_count ? `${data.metadata.member_count} members` : 'team'}
          </div>
        </div>
      </div>
      <Handle type="source" position={Position.Bottom} className="!bg-theme-border" />
    </div>
  );
}

// Custom node for MCP servers
function McpServerNode({ data }: { data: ConnectionNodeData }) {
  return (
    <div className="px-3 py-2 rounded-lg border border-theme bg-theme-surface shadow min-w-[120px]">
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <div className="flex items-center gap-2">
        <Server className="h-4 w-4 text-theme-warning" />
        <div>
          <div className="font-medium text-theme-primary text-xs">{data.label}</div>
          <div className="text-[10px] text-theme-tertiary">MCP Server</div>
        </div>
      </div>
      <Handle type="source" position={Position.Bottom} className="!bg-theme-border" />
    </div>
  );
}

// Custom node for memory pools
function MemoryPoolNode({ data }: { data: ConnectionNodeData }) {
  return (
    <div className="px-3 py-2 rounded-lg border border-theme bg-theme-surface shadow min-w-[120px]">
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <div className="flex items-center gap-2">
        <Database className="h-4 w-4 text-theme-success" />
        <div>
          <div className="font-medium text-theme-primary text-xs">{data.label}</div>
          <div className="text-[10px] text-theme-tertiary">Memory Pool</div>
        </div>
      </div>
      <Handle type="source" position={Position.Bottom} className="!bg-theme-border" />
    </div>
  );
}

const nodeTypes: NodeTypes = {
  agent: AgentNode,
  peer_agent: PeerAgentNode,
  team: TeamNode,
  mcp_server: McpServerNode,
  memory_pool: MemoryPoolNode,
};

interface AgentConnectionsGraphProps {
  agentId: string;
}

export const AgentConnectionsGraph: React.FC<AgentConnectionsGraphProps> = ({ agentId }) => {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [summary, setSummary] = useState<AgentConnectionsSummary | null>(null);
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([]);
  const navigate = useNavigate();

  const loadConnections = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await agentConnectionsApi.getAgentConnections(agentId);

      const flowNodes: Node[] = data.nodes.map((node: AgentConnectionNode) => ({
        id: node.id,
        type: node.type,
        data: {
          label: node.name,
          nodeType: node.type,
          status: node.status,
          metadata: node.metadata,
          selected: node.type === 'agent',
        },
        position: { x: 0, y: 0 },
      }));

      const flowEdges: Edge[] = data.edges.map((edge: AgentConnectionEdge, idx: number) => ({
        id: `edge-${idx}`,
        source: edge.source,
        target: edge.target,
        label: edge.label,
        type: 'default',
        animated: edge.relationship === 'a2a_communication',
        markerEnd: { type: MarkerType.ArrowClosed, color: 'var(--color-text-tertiary)' },
        style: { stroke: 'var(--color-text-tertiary)', strokeWidth: 1.5 },
        labelStyle: { fontSize: 10, fill: 'var(--color-text-tertiary)' },
      }));

      // Layout nodes using dagre
      const arrangedNodes = autoArrangeNodes(flowNodes, flowEdges, {
        direction: 'TB',
        nodeWidth: 160,
        nodeHeight: 60,
        spacing: 80,
      });

      setNodes(arrangedNodes);
      setEdges(flowEdges);
      setSummary(data.summary);
    } catch (_err) {
      setError('Failed to load agent connections');
    } finally {
      setLoading(false);
    }
  }, [agentId, setNodes, setEdges]);

  useEffect(() => {
    loadConnections();
  }, [loadConnections]);

  const onNodeClick = useCallback((_event: React.MouseEvent, node: Node) => {
    const nodeType = node.type;
    if (nodeType === 'peer_agent') {
      navigate(`/app/ai/agents/${node.id}`);
    } else if (nodeType === 'team') {
      navigate('/app/ai/agent-teams');
    }
  }, [navigate]);

  if (loading) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading connections..." />;
  }

  if (error) {
    return (
      <EmptyState
        icon={Bot}
        title="Failed to load connections"
        description={error}
      />
    );
  }

  const hasConnections = nodes.length > 1;

  return (
    <div className="space-y-4">
      <style>{graphStyles}</style>

      {/* Summary cards */}
      {summary && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <Card className="p-3">
            <div className="flex items-center gap-2">
              <Users className="h-4 w-4 text-theme-accent" />
              <div>
                <div className="text-xs text-theme-tertiary">Teams</div>
                <div className="text-lg font-semibold text-theme-primary">{summary.teams}</div>
              </div>
            </div>
          </Card>
          <Card className="p-3">
            <div className="flex items-center gap-2">
              <Bot className="h-4 w-4 text-theme-info" />
              <div>
                <div className="text-xs text-theme-tertiary">Peers</div>
                <div className="text-lg font-semibold text-theme-primary">{summary.peers}</div>
              </div>
            </div>
          </Card>
          <Card className="p-3">
            <div className="flex items-center gap-2">
              <Server className="h-4 w-4 text-theme-warning" />
              <div>
                <div className="text-xs text-theme-tertiary">MCP Servers</div>
                <div className="text-lg font-semibold text-theme-primary">{summary.mcp_servers}</div>
              </div>
            </div>
          </Card>
          <Card className="p-3">
            <div className="flex items-center gap-2">
              <Database className="h-4 w-4 text-theme-success" />
              <div>
                <div className="text-xs text-theme-tertiary">Connections</div>
                <div className="text-lg font-semibold text-theme-primary">{summary.connections}</div>
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* Graph */}
      {hasConnections ? (
        <div className="h-[500px] rounded-lg border border-theme bg-theme-surface">
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onNodeClick={onNodeClick}
            nodeTypes={nodeTypes}
            fitView
            fitViewOptions={{ padding: 0.3 }}
            minZoom={0.3}
            maxZoom={2}
          >
            <Background variant={BackgroundVariant.Dots} gap={16} size={1} />
            <Controls className="connections-controls" />
            <MiniMap
              nodeColor={(node) => {
                const style = getComputedStyle(document.documentElement);
                switch (node.type) {
                  case 'agent': return style.getPropertyValue('--color-info').trim() || '#3b82f6';
                  case 'peer_agent': return style.getPropertyValue('--color-text-secondary').trim() || '#6b7280';
                  case 'team': return style.getPropertyValue('--color-interactive-primary').trim() || '#a855f7';
                  case 'mcp_server': return style.getPropertyValue('--color-warning').trim() || '#f97316';
                  case 'memory_pool': return style.getPropertyValue('--color-success').trim() || '#14b8a6';
                  default: return style.getPropertyValue('--color-text-secondary').trim() || '#6b7280';
                }
              }}
              maskColor="rgba(0,0,0,0.1)"
            />
          </ReactFlow>
        </div>
      ) : (
        <EmptyState
          icon={Bot}
          title="No connections found"
          description="This agent is not connected to any teams, peers, or MCP servers yet."
        />
      )}
    </div>
  );
};
