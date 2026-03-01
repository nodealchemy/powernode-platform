import React, { useRef, useEffect, useState, useCallback } from 'react';
import { McpNodeCard } from './McpNodeCard';
import { cn } from '@/shared/utils/cn';
import type { TopologyAgent, TopologyServer, TopologyTool, TopologyConnection } from '../hooks/useMcpTopology';

interface McpFlowCanvasProps {
  agents: TopologyAgent[];
  servers: TopologyServer[];
  tools: TopologyTool[];
  connections: TopologyConnection[];
  selectedNodeId: string | null;
  onSelectNode: (id: string | null) => void;
}

interface NodePosition {
  id: string;
  x: number;
  y: number;
  height: number;
}

const CONNECTION_COLORS: Record<string, string> = {
  healthy: 'stroke-theme-success',
  warning: 'stroke-theme-warning',
  error: 'stroke-theme-danger',
};

const COLUMN_WIDTH = 200;
const NODE_GAP = 8;
const NODE_HEIGHT = 52;
const COLUMN_GAP = 120;
const HEADER_HEIGHT = 32;
const PADDING_TOP = 16;

export const McpFlowCanvas: React.FC<McpFlowCanvasProps> = ({
  agents,
  servers,
  tools,
  connections,
  selectedNodeId,
  onSelectNode,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const [positions, setPositions] = useState<Map<string, NodePosition>>(new Map());

  // Calculate node positions
  const calculatePositions = useCallback(() => {
    const map = new Map<string, NodePosition>();
    const colX = [PADDING_TOP, COLUMN_WIDTH + COLUMN_GAP, (COLUMN_WIDTH + COLUMN_GAP) * 2];

    // Position agents (left column)
    agents.forEach((agent, i) => {
      map.set(agent.id, {
        id: agent.id,
        x: colX[0],
        y: HEADER_HEIGHT + PADDING_TOP + i * (NODE_HEIGHT + NODE_GAP),
        height: NODE_HEIGHT,
      });
    });

    // Position servers (center column)
    servers.forEach((server, i) => {
      map.set(server.id, {
        id: server.id,
        x: colX[1],
        y: HEADER_HEIGHT + PADDING_TOP + i * (NODE_HEIGHT + NODE_GAP),
        height: NODE_HEIGHT,
      });
    });

    // Position tools (right column)
    tools.forEach((tool, i) => {
      map.set(tool.id, {
        id: tool.id,
        x: colX[2],
        y: HEADER_HEIGHT + PADDING_TOP + i * (NODE_HEIGHT + NODE_GAP),
        height: NODE_HEIGHT,
      });
    });

    setPositions(map);
  }, [agents, servers, tools]);

  useEffect(() => {
    calculatePositions();
  }, [calculatePositions]);

  // Compute SVG lines between connected nodes
  const renderConnections = () => {
    return connections.map((conn) => {
      const source = positions.get(conn.sourceId);
      const target = positions.get(conn.targetId);
      if (!source || !target) return null;

      const x1 = source.x + COLUMN_WIDTH;
      const y1 = source.y + source.height / 2;
      const x2 = target.x;
      const y2 = target.y + target.height / 2;

      const isHighlighted =
        selectedNodeId === conn.sourceId || selectedNodeId === conn.targetId;

      const colorClass = CONNECTION_COLORS[conn.status] || CONNECTION_COLORS.healthy;

      return (
        <line
          key={conn.id}
          x1={x1}
          y1={y1}
          x2={x2}
          y2={y2}
          className={cn(colorClass, isHighlighted ? 'opacity-100' : 'opacity-40')}
          strokeWidth={isHighlighted ? 2 : 1}
        />
      );
    });
  };

  // Calculate canvas dimensions
  const maxRows = Math.max(agents.length, servers.length, tools.length, 1);
  const canvasHeight = HEADER_HEIGHT + PADDING_TOP + maxRows * (NODE_HEIGHT + NODE_GAP) + PADDING_TOP;
  const canvasWidth = (COLUMN_WIDTH + COLUMN_GAP) * 3 - COLUMN_GAP + PADDING_TOP * 2;

  const handleBackgroundClick = (e: React.MouseEvent) => {
    if (e.target === e.currentTarget) {
      onSelectNode(null);
    }
  };

  return (
    <div
      ref={containerRef}
      className="relative flex-1 overflow-auto bg-theme-background"
      onClick={handleBackgroundClick}
    >
      <div className="relative" style={{ minWidth: canvasWidth, minHeight: canvasHeight }}>
        {/* SVG overlay for connections */}
        <svg
          className="absolute inset-0 pointer-events-none"
          width={canvasWidth}
          height={canvasHeight}
        >
          {renderConnections()}
        </svg>

        {/* Column headers */}
        <div className="flex" style={{ paddingLeft: PADDING_TOP }}>
          {['Agents', 'MCP Servers', 'Tools'].map((label, i) => (
            <div
              key={label}
              className="text-xs font-semibold text-theme-secondary uppercase tracking-wider py-2"
              style={{ width: COLUMN_WIDTH, marginLeft: i > 0 ? COLUMN_GAP : 0 }}
            >
              {label}
            </div>
          ))}
        </div>

        {/* Agent nodes */}
        {agents.map((agent) => {
          const pos = positions.get(agent.id);
          if (!pos) return null;
          return (
            <div
              key={agent.id}
              className="absolute"
              style={{ left: pos.x, top: pos.y, width: COLUMN_WIDTH }}
            >
              <McpNodeCard
                id={agent.id}
                name={agent.name}
                variant="agent"
                status={agent.status}
                metric={`${agent.serverIds.length}`}
                metricLabel="servers"
                isSelected={selectedNodeId === agent.id}
                onClick={onSelectNode}
              />
            </div>
          );
        })}

        {/* Server nodes */}
        {servers.map((server) => {
          const pos = positions.get(server.id);
          if (!pos) return null;
          return (
            <div
              key={server.id}
              className="absolute"
              style={{ left: pos.x, top: pos.y, width: COLUMN_WIDTH }}
            >
              <McpNodeCard
                id={server.id}
                name={server.name}
                variant="server"
                status={server.status}
                metric={`${server.tools_count}`}
                metricLabel="tools"
                isSelected={selectedNodeId === server.id}
                onClick={onSelectNode}
              />
            </div>
          );
        })}

        {/* Tool nodes */}
        {tools.map((tool) => {
          const pos = positions.get(tool.id);
          if (!pos) return null;
          return (
            <div
              key={tool.id}
              className="absolute"
              style={{ left: pos.x, top: pos.y, width: COLUMN_WIDTH }}
            >
              <McpNodeCard
                id={tool.id}
                name={tool.name}
                variant="tool"
                status="active"
                metric={tool.category || undefined}
                isSelected={selectedNodeId === tool.id}
                onClick={onSelectNode}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default McpFlowCanvas;
