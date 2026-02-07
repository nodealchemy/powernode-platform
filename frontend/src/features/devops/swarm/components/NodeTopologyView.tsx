import React from 'react';
import { swarmApi } from '../services/swarmApi';
import type { SwarmNodeSummary } from '../types';

interface NodeTopologyViewProps {
  nodes: SwarmNodeSummary[];
}

export const NodeTopologyView: React.FC<NodeTopologyViewProps> = ({ nodes }) => {
  const managers = nodes.filter((n) => n.role === 'manager');
  const workers = nodes.filter((n) => n.role === 'worker');

  const renderNode = (node: SwarmNodeSummary) => {
    const statusColor = swarmApi.getNodeStatusColor(node.status);

    return (
      <div key={node.id} className="flex items-center gap-3 p-3 rounded-lg bg-theme-surface border border-theme">
        <div className={`w-3 h-3 rounded-full flex-shrink-0 ${
          node.status === 'ready' ? 'bg-theme-success' :
          node.status === 'down' ? 'bg-theme-error' :
          'bg-theme-warning'
        }`} />
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-theme-primary truncate">{node.hostname}</p>
          <div className="flex items-center gap-2 text-xs text-theme-tertiary">
            {node.ip_address && <span>{node.ip_address}</span>}
            <span className={`px-1.5 py-0.5 rounded ${statusColor}`}>{node.status}</span>
          </div>
        </div>
        <div className="text-right text-xs text-theme-tertiary">
          {node.cpu_count && <div>{node.cpu_count} CPU</div>}
          {node.memory_gb && <div>{node.memory_gb} GB</div>}
        </div>
      </div>
    );
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-theme-info" />
          Manager Nodes ({managers.length})
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {managers.map(renderNode)}
        </div>
      </div>

      {managers.length > 0 && workers.length > 0 && (
        <div className="flex items-center gap-3">
          <div className="flex-1 border-t border-theme border-dashed" />
          <span className="text-xs text-theme-tertiary">Orchestration layer</span>
          <div className="flex-1 border-t border-theme border-dashed" />
        </div>
      )}

      <div>
        <h3 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-theme-success" />
          Worker Nodes ({workers.length})
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {workers.map(renderNode)}
        </div>
      </div>

      {nodes.length === 0 && (
        <div className="text-center py-12 text-theme-tertiary">No nodes available.</div>
      )}
    </div>
  );
};
