import React, { useState, useMemo } from 'react';
import { RefreshCw, AlertCircle } from 'lucide-react';
import { McpFlowCanvas } from './McpFlowCanvas';
import { McpToolLog, type ToolLogEntry } from './McpToolLog';
import { useMcpTopology } from '../hooks/useMcpTopology';
import { Loading } from '@/shared/components/ui/Loading';
import { Button } from '@/shared/components/ui/Button';

export const McpStudioTab: React.FC = () => {
  const { agents, servers, tools, connections, isLoading, error, refetch } = useMcpTopology();
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);

  // Build a synthetic tool log from the topology data
  // In production this would come from a real-time execution feed
  const toolLogEntries: ToolLogEntry[] = useMemo(() => {
    // Generate entries from tools as placeholder log
    return tools.slice(0, 20).map((tool, i) => ({
      id: `log-${tool.id}-${i}`,
      timestamp: new Date(Date.now() - i * 60000).toISOString(),
      serverName: tool.serverName,
      toolName: tool.name,
      status: 'completed' as const,
      durationMs: Math.floor(Math.random() * 500) + 50,
    }));
  }, [tools]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-16">
        <Loading size="lg" message="Loading MCP topology..." />
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex flex-col items-center justify-center py-16 gap-4">
        <AlertCircle className="w-8 h-8 text-theme-danger" />
        <p className="text-sm text-theme-secondary">
          Failed to load MCP topology: {error.message}
        </p>
        <Button variant="outline" size="sm" onClick={() => refetch()}>
          <RefreshCw className="w-4 h-4 mr-2" />
          Retry
        </Button>
      </div>
    );
  }

  if (servers.length === 0 && agents.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-16 gap-3">
        <p className="text-sm text-theme-secondary">
          No MCP servers or agents configured yet.
        </p>
        <p className="text-xs text-theme-muted">
          Add MCP servers in the "MCP Servers" tab and agents in the Agents page.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-[calc(100vh-16rem)] border border-theme rounded-lg overflow-hidden">
      {/* Toolbar */}
      <div className="flex items-center justify-between px-3 py-2 bg-theme-surface border-b border-theme">
        <div className="flex items-center gap-4 text-xs text-theme-secondary">
          <span>{agents.length} agents</span>
          <span>{servers.length} servers</span>
          <span>{tools.length} tools</span>
          <span>{connections.length} connections</span>
        </div>
        <Button variant="ghost" size="sm" onClick={() => refetch()}>
          <RefreshCw className="w-3.5 h-3.5" />
        </Button>
      </div>

      {/* Canvas area */}
      <McpFlowCanvas
        agents={agents}
        servers={servers}
        tools={tools}
        connections={connections}
        selectedNodeId={selectedNodeId}
        onSelectNode={setSelectedNodeId}
      />

      {/* Tool log (bottom panel, ~200px) */}
      <McpToolLog entries={toolLogEntries} />
    </div>
  );
};

export default McpStudioTab;
